#!/usr/bin/env python3
"""Meshy asset pipeline: manifest-driven generation, rigging and animation.

Reads ``assets/manifest.yaml`` and drives the Meshy API (https://docs.meshy.ai):

    text-to-3d preview(s) -> refine (PBR texture) -> rig -> animate (action ids)

Every paid task is appended to ``assets/meshy-ledger.jsonl`` the moment it is created, so a
crashed or interrupted run resumes by polling the recorded task instead of paying again.
Finished stages recorded in the ledger are skipped. ``--max-credits`` is a hard guard: a task
is never created if the ledger total plus its estimated cost would exceed it.

The API key is read from the ``MESHY_API_KEY`` environment variable and is never printed,
logged or written to disk.

    export MESHY_API_KEY=$(tr -d '[:space:]' < ~/meshy.txt)
    python3 tools/meshy/meshy.py plan
    python3 tools/meshy/meshy.py generate gnome_ranger --max-credits 900

Requires Python 3.10+ and PyYAML (``pip install pyyaml``).
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover - environment dependent
    sys.exit("meshy.py needs PyYAML: pip install pyyaml")

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = REPO_ROOT / "assets" / "manifest.yaml"
DEFAULT_LEDGER = REPO_ROOT / "assets" / "meshy-ledger.jsonl"
API_BASE = "https://api.meshy.ai"
LIBRARY_PATH = "/openapi/v1/animations/library"

ENDPOINTS = {
    "preview": "/openapi/v2/text-to-3d",
    "refine": "/openapi/v2/text-to-3d",
    "image": "/openapi/v1/image-to-3d",
    "rig": "/openapi/v1/rigging",
    "animate": "/openapi/v1/animations",
}
MESH_CREDITS = {"meshy-7.1": 20, "latest": 20, "meshy-7": 20, "meshy-6": 20}
LOW_MESH_CREDITS = 5  # meshy-6-lite, meshy-t2, meshy-t2.5
TEXTURE_CREDITS = {"2k": 10, "4k": 10, "8k": 15}
RIG_CREDITS = 5
ANIMATION_CREDITS_PER_ACTION = 3
MAX_ACTIONS_PER_REQUEST = 10
POLL_TIMEOUT_S = 45 * 60
EXIT_BUDGET = 3
EXIT_FAILED = 4


class MeshyError(RuntimeError):
    """A recoverable, user-facing failure (bad manifest, API error, budget guard)."""


# --------------------------------------------------------------------------- manifest


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        manifest = yaml.safe_load(handle)
    if not isinstance(manifest, dict) or "assets" not in manifest:
        raise MeshyError(f"{path}: expected a mapping with an 'assets' key")
    return manifest


def asset_names(manifest: dict[str, Any], requested: list[str]) -> list[str]:
    known = list(manifest["assets"])
    if not requested:
        return known
    unknown = [name for name in requested if name not in manifest["assets"]]
    if unknown:
        raise MeshyError(f"unknown asset(s) {unknown}; manifest has {known}")
    return requested


def asset_dir(asset: dict[str, Any]) -> Path:
    return REPO_ROOT / asset["output"]


def work_dir(asset: dict[str, Any]) -> Path:
    return asset_dir(asset) / "work"


def action_batches(asset: dict[str, Any]) -> list[list[dict[str, Any]]]:
    """Split the animation list into API-sized batches, preserving manifest order."""
    clips = asset.get("animations", [])
    return [
        clips[i : i + MAX_ACTIONS_PER_REQUEST]
        for i in range(0, len(clips), MAX_ACTIONS_PER_REQUEST)
    ]


# --------------------------------------------------------------------------- ledger


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Ledger:
    """Append-only JSONL log of every paid Meshy task."""

    def __init__(self, path: Path) -> None:
        self.path = path

    def records(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        lines = self.path.read_text(encoding="utf-8").splitlines()
        return [json.loads(line) for line in lines if line.strip()]

    def append(self, record: dict[str, Any]) -> None:
        record = {"ts": now_iso(), **record}
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, sort_keys=False) + "\n")

    def task_states(self) -> dict[str, dict[str, Any]]:
        """Fold created/finished events into one state per task id."""
        tasks: dict[str, dict[str, Any]] = {}
        for rec in self.records():
            task_id = rec.get("task_id")
            if not task_id:
                continue
            state = tasks.setdefault(task_id, {"task_id": task_id})
            state.update({k: v for k, v in rec.items() if k not in ("ts", "event")})
            state["event"] = rec["event"]
        return tasks

    def spent(self) -> int:
        """Credits consumed. In-flight tasks count at their estimate (charged at creation)."""
        total = 0
        for state in self.task_states().values():
            if state["event"] == "created":
                total += int(state.get("est_credits", 0))
            elif state.get("status") != "FAILED":
                total += int(state.get("consumed_credits") or 0)
        return total

    def find(self, asset: str, stage: str, variant: int = 0) -> dict[str, Any] | None:
        """Latest non-failed task for (asset, stage, variant), else None."""
        match = None
        for state in self.task_states().values():
            same = (
                state.get("asset") == asset
                and state.get("stage") == stage
                and state.get("variant", 0) == variant
            )
            if same and state.get("status") != "FAILED":
                match = state
        return match


# --------------------------------------------------------------------------- API client


class Client:
    """Minimal Meshy REST client. The key only ever travels in the Authorization header."""

    def __init__(self, key: str) -> None:
        self._key = key

    def request(self, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        data = json.dumps(body).encode() if body is not None else None
        for attempt in range(6):
            req = urllib.request.Request(
                API_BASE + path,
                data=data,
                method=method,
                headers={
                    "Authorization": f"Bearer {self._key}",
                    "Content-Type": "application/json",
                    "User-Agent": "gnome-rangers-meshy-cli",
                },
            )
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    return json.loads(resp.read() or b"null")
            except urllib.error.HTTPError as err:
                detail = err.read().decode(errors="replace")[:400]
                retryable = err.code == 429 or err.code >= 500
                if retryable and attempt < 5 and "NoMore" not in detail:
                    time.sleep(int(err.headers.get("Retry-After", 5 * (attempt + 1))))
                    continue
                raise MeshyError(f"{method} {path} -> HTTP {err.code}: {detail}") from None
            except (urllib.error.URLError, TimeoutError):
                if attempt == 5:
                    raise MeshyError(f"{method} {path}: network error") from None
                time.sleep(5 * (attempt + 1))
        raise MeshyError(f"{method} {path}: retries exhausted")


def download(url: str, dest: Path) -> None:
    """Fetch a signed asset URL (no auth header) to ``dest`` atomically."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "gnome-rangers-meshy-cli"})
    with urllib.request.urlopen(req, timeout=300) as resp, tmp.open("wb") as out:
        shutil.copyfileobj(resp, out)
    tmp.replace(dest)


def get_client() -> Client:
    key = os.environ.get("MESHY_API_KEY", "").strip()
    if not key:
        raise MeshyError("MESHY_API_KEY is not set (see tools/meshy/README.md)")
    return Client(key)


# --------------------------------------------------------------------------- task model


@dataclass
class Task:
    asset: str
    stage: str
    variant: int
    est_credits: int
    payload: dict[str, Any]
    summary: str
    state: dict[str, Any] | None = None
    notes: list[str] = field(default_factory=list)

    @property
    def status(self) -> str:
        if self.state is None:
            return "pending"
        if self.state["event"] == "created":
            return "in-flight"
        return "done"


def mesh_cost(spec: dict[str, Any]) -> int:
    base = MESH_CREDITS.get(spec.get("ai_model", "latest"), LOW_MESH_CREDITS)
    if spec.get("geometry_resolution") in ("2k", "4k"):
        base += 5
    return base


def texture_cost(spec: dict[str, Any]) -> int:
    return TEXTURE_CREDITS[spec.get("texture", {}).get("resolution", "2k")]


def image_data_uri(rel_path: str) -> str:
    path = REPO_ROOT / rel_path
    mime = mimetypes.guess_type(path.name)[0] or "image/png"
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"


def preview_payload(spec: dict[str, Any]) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "mode": "preview",
        "prompt": spec["prompt"],
        "ai_model": spec["ai_model"],
        "target_formats": ["glb"],
    }
    if spec.get("model_type"):
        payload["model_type"] = spec["model_type"]
    if spec.get("target_polycount"):
        payload["target_polycount"] = spec["target_polycount"]
        if spec.get("model_type") != "smart-topology":
            payload["should_remesh"] = True
    for key in ("pose_mode", "geometry_resolution"):
        if spec.get(key):
            payload[key] = spec[key]
    return payload


def texture_payload(spec: dict[str, Any]) -> dict[str, Any]:
    tex = spec.get("texture", {})
    payload: dict[str, Any] = {
        "enable_pbr": tex.get("enable_pbr", True),
        "texture_resolution": tex.get("resolution", "2k"),
    }
    if tex.get("prompt"):
        payload["texture_prompt"] = tex["prompt"]
    if tex.get("ai_model"):
        payload["ai_model"] = tex["ai_model"]
    return payload


def build_tasks(name: str, spec: dict[str, Any], ledger: Ledger) -> list[Task]:
    """The full ordered task list for one asset, annotated with ledger state."""
    tasks: list[Task] = []
    pick = spec.get("pick")
    if spec["mode"] == "image-to-3d":
        payload = {
            "image_url": image_data_uri(spec["image"]),
            "ai_model": spec["ai_model"],
            "should_texture": True,
            "target_formats": ["glb"],
            **texture_payload(spec),
        }
        if spec.get("model_type"):
            payload["model_type"] = spec["model_type"]
        if spec.get("target_polycount"):
            payload["target_polycount"] = spec["target_polycount"]
        if spec.get("pose_mode"):
            payload["pose_mode"] = spec["pose_mode"]
        cost = mesh_cost(spec) + texture_cost(spec)
        tasks.append(Task(name, "image", 0, cost, payload, f"image-to-3d {spec['image']}"))
        model_stage = "image"
    else:
        variants = [pick] if pick is not None else range(spec.get("previews", 1))
        for variant in variants:
            summary = f"text-to-3d preview #{variant} ({spec['ai_model']})"
            tasks.append(
                Task(name, "preview", variant, mesh_cost(spec), preview_payload(spec), summary)
            )
        if pick is not None:
            summary = f"refine preview #{pick} (PBR {texture_payload(spec)['texture_resolution']})"
            tasks.append(Task(name, "refine", 0, texture_cost(spec), texture_payload(spec), summary))
        model_stage = "refine"
    rig_payload = {
        "height_meters": spec["height_meters"],
        "skeleton_template": spec.get("rig", {}).get("skeleton_template", "mixamo"),
    }
    tasks.append(Task(name, "rig", 0, RIG_CREDITS, rig_payload, f"rig {rig_payload}"))
    for index, batch in enumerate(action_batches(spec)):
        cost = ANIMATION_CREDITS_PER_ACTION * len(batch)
        ids = [clip["action_id"] for clip in batch]
        tasks.append(
            Task(name, "animate", index, cost, {"action_ids": ids}, f"animate batch {index}: {ids}")
        )
    for task in tasks:
        task.state = ledger.find(name, task.stage, task.variant)
    _ = model_stage
    return tasks


def model_stage_of(spec: dict[str, Any]) -> str:
    return "image" if spec["mode"] == "image-to-3d" else "refine"


# --------------------------------------------------------------------------- execution


class Runner:
    def __init__(
        self,
        manifest: dict[str, Any],
        ledger: Ledger,
        max_credits: int,
        dry_run: bool,
    ) -> None:
        self.manifest = manifest
        self.ledger = ledger
        self.max_credits = max_credits
        self.dry_run = dry_run
        self._client: Client | None = None

    @property
    def client(self) -> Client:
        if self._client is None:
            self._client = get_client()
        return self._client

    def guard(self, task: Task) -> None:
        total = self.ledger.spent() + task.est_credits
        if total > self.max_credits:
            raise MeshyError(
                f"budget guard: ledger {self.ledger.spent()} + {task.est_credits} for "
                f"{task.asset}/{task.stage} would exceed --max-credits {self.max_credits}"
            )

    def resolve_inputs(self, task: Task, spec: dict[str, Any]) -> dict[str, Any]:
        """Fill in the upstream task id (preview -> refine -> rig -> animate)."""
        payload = dict(task.payload)
        name = task.asset
        if task.stage == "refine":
            upstream = self.ledger.find(name, "preview", spec["pick"])
            payload["preview_task_id"] = self.require(upstream, name, "preview")
            payload["mode"] = "refine"
        elif task.stage == "rig":
            payload["input_task_id"] = self.require(
                self.ledger.find(name, model_stage_of(spec)), name, model_stage_of(spec)
            )
        elif task.stage == "animate":
            payload["rig_task_id"] = self.require(self.ledger.find(name, "rig"), name, "rig")
        return payload

    @staticmethod
    def require(state: dict[str, Any] | None, name: str, stage: str) -> str:
        if not state or state["event"] != "finished" or state.get("status") != "SUCCEEDED":
            raise MeshyError(f"{name}: stage '{stage}' has not succeeded yet")
        return str(state["task_id"])

    def ensure(self, task: Task, spec: dict[str, Any]) -> dict[str, Any]:
        """Create (if needed) and wait for one task; returns its finished ledger state."""
        if task.state and task.state["event"] == "finished":
            print(f"  skip   {task.asset}/{task.stage}#{task.variant}: done ({task.state['task_id']})")
            return task.state
        if task.state is None:
            self.guard(task)
            body = self.resolve_inputs(task, spec)
            path = ENDPOINTS[task.stage]
            result = self.client.request("POST", path, body)
            task_id = result["result"]
            record = {
                "event": "created",
                "asset": task.asset,
                "stage": task.stage,
                "variant": task.variant,
                "task_id": task_id,
                "endpoint": path,
                "est_credits": task.est_credits,
                "ai_model": task.payload.get("ai_model"),
            }
            if task.stage == "preview":
                record["prompt"] = task.payload["prompt"]
            if task.stage == "animate":
                record["action_ids"] = task.payload["action_ids"]
            self.ledger.append(record)
            print(f"  create {task.asset}/{task.stage}#{task.variant}: {task_id} (~{task.est_credits} cr)")
            task.state = {**record}
        else:
            print(f"  resume {task.asset}/{task.stage}#{task.variant}: {task.state['task_id']}")
        return self.wait(task)

    def wait(self, task: Task) -> dict[str, Any]:
        assert task.state is not None
        task_id = task.state["task_id"]
        path = status_path(task.state["endpoint"], task_id)
        deadline = time.time() + POLL_TIMEOUT_S
        while time.time() < deadline:
            data = self.client.request("GET", path)
            status = data.get("status")
            if status in ("SUCCEEDED", "FAILED", "CANCELED"):
                error = (data.get("task_error") or {}).get("message", "")
                credits = 0 if status != "SUCCEEDED" else data.get("consumed_credits", task.est_credits)
                self.ledger.append(
                    {
                        "event": "finished",
                        "asset": task.asset,
                        "stage": task.stage,
                        "variant": task.variant,
                        "task_id": task_id,
                        "status": status,
                        "consumed_credits": credits,
                        "error": error or None,
                    }
                )
                if status != "SUCCEEDED":
                    raise MeshyError(f"{task.asset}/{task.stage} {task_id} {status}: {error}")
                task.state = {**task.state, "event": "finished", "status": status}
                self.fetch_outputs(task, data)
                return task.state
            time.sleep(8)
        raise MeshyError(f"{task_id}: still running after {POLL_TIMEOUT_S // 60} min; re-run to resume")

    def fetch_outputs(self, task: Task, data: dict[str, Any]) -> None:
        spec = self.manifest["assets"][task.asset]
        work = work_dir(spec)
        if task.stage in ("preview", "refine", "image"):
            url = (data.get("model_urls") or {}).get("glb")
            label = f"preview_{task.variant}" if task.stage == "preview" else "textured"
            thumb = data.get("thumbnail_url")
            if thumb and task.stage == "preview":
                download(thumb, work / f"preview_{task.variant}.png")
        elif task.stage == "rig":
            url = (data.get("result") or {}).get("rigged_character_glb_url")
            label = "rigged"
        else:
            url = (data.get("result") or {}).get("animation_glb_url")
            label = f"anim_{task.variant}"
        if not url:
            raise MeshyError(f"{task.asset}/{task.stage}: no GLB url in task result")
        dest = work / f"{label}.glb"
        download(url, dest)
        print(f"  saved  {dest.relative_to(REPO_ROOT)} ({dest.stat().st_size // 1024} KiB)")


def status_path(endpoint: str, task_id: str) -> str:
    return f"{endpoint}/{task_id}"


# --------------------------------------------------------------------------- commands


def print_plan(manifest: dict[str, Any], names: list[str], ledger: Ledger, max_credits: int) -> int:
    remaining = 0
    for name in names:
        spec = manifest["assets"][name]
        print(f"\n{name}  [{spec['mode']}, {spec['ai_model']}, {spec['height_meters']} m]")
        if spec.get("pick") is None and spec["mode"] == "text-to-3d":
            print("  note: no 'pick' set in the manifest; refine/rig/animate unlock after you pick a preview")
        for task in build_tasks(name, spec, ledger):
            cost = 0 if task.status == "done" else task.est_credits
            remaining += 0 if task.status == "in-flight" else cost
            print(f"  {task.status:<9} {task.stage:<8} #{task.variant}  ~{task.est_credits:>3} cr  {task.summary}")
    spent = ledger.spent()
    print(f"\nLedger spent so far : {spent} credits")
    print(f"Estimated remaining : {remaining} credits (no spend: dry run)")
    print(f"Projected total     : {spent + remaining} / --max-credits {max_credits}")
    return 0 if spent + remaining <= max_credits else EXIT_BUDGET


def cmd_balance(args: argparse.Namespace, manifest: dict[str, Any], ledger: Ledger) -> int:
    data = get_client().request("GET", "/openapi/v1/balance")
    print(f"balance: {data['balance']} credits")
    if args.record:
        ledger.append({"event": "balance", "balance": data["balance"], "note": args.record})
    return 0


def cmd_plan(args: argparse.Namespace, manifest: dict[str, Any], ledger: Ledger) -> int:
    names = asset_names(manifest, args.names)
    return print_plan(manifest, names, ledger, args.max_credits)


def cmd_library(args: argparse.Namespace, manifest: dict[str, Any], ledger: Ledger) -> int:
    """List the free animation library (helps choose action ids)."""
    query = f"?search={args.search}" if args.search else ""
    for item in get_client().request("GET", LIBRARY_PATH + query):
        if item["rig_type"] == "biped":
            print(f"{item['action_id']:>4}  {item['name']:<36} {item['category']}/{item['sub_category']}")
    return 0


def run_stages(args: argparse.Namespace, manifest: dict[str, Any], ledger: Ledger, stages: set[str]) -> int:
    runner = Runner(manifest, ledger, args.max_credits, args.dry_run)
    for name in asset_names(manifest, args.names):
        spec = manifest["assets"][name]
        tasks = [t for t in build_tasks(name, spec, ledger) if t.stage in stages]
        if not tasks:
            print(f"{name}: nothing to do for {sorted(stages)}")
            continue
        print(f"{name}:")
        if args.dry_run:
            for task in tasks:
                print(f"  would {task.status} {task.stage}#{task.variant} (~{task.est_credits} cr)")
            continue
        for task in tasks:
            runner.ensure(task, spec)
        if "animate" in stages:
            finalize_animation(name, spec)
    print(f"ledger total: {ledger.spent()} / {args.max_credits} credits")
    return 0


def cmd_generate(args: argparse.Namespace, manifest: dict[str, Any], ledger: Ledger) -> int:
    return run_stages(args, manifest, ledger, {"preview", "refine", "image"})


def cmd_rig(args: argparse.Namespace, manifest: dict[str, Any], ledger: Ledger) -> int:
    return run_stages(args, manifest, ledger, {"rig"})


def cmd_animate(args: argparse.Namespace, manifest: dict[str, Any], ledger: Ledger) -> int:
    return run_stages(args, manifest, ledger, {"animate"})


def cmd_status(args: argparse.Namespace, manifest: dict[str, Any], ledger: Ledger) -> int:
    known = ledger.task_states().get(args.task_id)
    endpoints = [known["endpoint"]] if known else sorted(set(ENDPOINTS.values()))
    client = get_client()
    for endpoint in endpoints:
        try:
            data = client.request("GET", status_path(endpoint, args.task_id))
        except MeshyError:
            continue
        safe = {k: data.get(k) for k in ("id", "type", "status", "progress", "consumed_credits")}
        safe["task_error"] = (data.get("task_error") or {}).get("message")
        print(json.dumps(safe, indent=2))
        return 0
    raise MeshyError(f"task {args.task_id} not found on any endpoint")


def finalize_animation(name: str, spec: dict[str, Any]) -> None:
    """Write the final GLB and import.json once every animation batch has been downloaded."""
    work = work_dir(spec)
    batches = action_batches(spec)
    sources = [work / f"anim_{i}.glb" for i in range(len(batches))]
    if not sources or not all(p.exists() for p in sources):
        return
    final = asset_dir(spec) / f"{name}.glb"
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import glb_merge  # local helper: reads clip names, merges clips from several GLBs

    if len(sources) == 1:
        shutil.copyfile(sources[0], final)
    else:
        glb_merge.merge_animations(sources[0], sources[1:], final)
    # Clip order in each Meshy file follows the action_ids order of its request.
    meshy_names: list[str] = []
    for source in sources:
        meshy_names += [a.get("name", "") for a in glb_merge.read_glb(source)[0]["animations"]]
    flat = [clip for batch in batches for clip in batch]
    if len(meshy_names) != len(flat):
        raise MeshyError(f"{name}: {len(meshy_names)} clips in GLBs but {len(flat)} in manifest")
    clips = [
        {
            "name": clip["name"],
            "meshy_clip": meshy_name,
            "action_id": clip["action_id"],
            "library_name": clip.get("library_name"),
            "loop": bool(clip.get("loop", False)),
            "note": clip.get("note"),
        }
        for clip, meshy_name in zip(flat, meshy_names)
    ]
    document = {"rim_light": bool(spec.get("rim_light", False)), "clips": clips}
    (asset_dir(spec) / "import.json").write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print(f"  wrote  {final.relative_to(REPO_ROOT)} and import.json ({len(clips)} clips)")


# --------------------------------------------------------------------------- CLI


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Manifest-driven Meshy pipeline (generate, rig, animate) with a spend ledger.",
        epilog="Key: export MESHY_API_KEY=$(tr -d '[:space:]' < ~/meshy.txt). See tools/meshy/README.md.",
    )
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER)
    sub = parser.add_subparsers(dest="command", required=True)

    def add_run_flags(p: argparse.ArgumentParser) -> None:
        p.add_argument("names", nargs="*", help="asset names from the manifest (default: all)")
        p.add_argument("--max-credits", type=int, default=None, help="hard cap on total ledger spend")

    p = sub.add_parser("balance", help="show the Meshy credit balance (free)")
    p.add_argument("--record", metavar="NOTE", help="also append a balance event to the ledger")
    p.set_defaults(func=cmd_balance)

    p = sub.add_parser("plan", help="dry run: list tasks and the credit estimate, no spend")
    add_run_flags(p)
    p.set_defaults(func=cmd_plan)

    p = sub.add_parser("library", help="list the free biped animation library")
    p.add_argument("search", nargs="?", help="filter by name or key")
    p.set_defaults(func=cmd_library)

    for cmd, func, text in (
        ("generate", cmd_generate, "previews, then refine/texture once 'pick' is set in the manifest"),
        ("rig", cmd_rig, "auto-rig the textured model"),
        ("animate", cmd_animate, "apply the manifest action_ids and write the final GLB"),
    ):
        p = sub.add_parser(cmd, help=text)
        add_run_flags(p)
        p.add_argument("--dry-run", action="store_true", help="show what would run, spend nothing")
        p.set_defaults(func=func)

    p = sub.add_parser("status", help="show the status of one Meshy task (free)")
    p.add_argument("task_id")
    p.set_defaults(func=cmd_status)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        manifest = load_manifest(args.manifest)
        if getattr(args, "max_credits", None) is None:
            args.max_credits = int(manifest.get("budget", {}).get("max_credits", 900))
        return args.func(args, manifest, Ledger(args.ledger))
    except MeshyError as err:
        text = re.sub(r"m" r"sy_[A-Za-z0-9_-]+", "[redacted]", str(err))
        print(f"error: {text}", file=sys.stderr)
        return EXIT_BUDGET if "budget guard" in text else EXIT_FAILED


if __name__ == "__main__":
    sys.exit(main())
