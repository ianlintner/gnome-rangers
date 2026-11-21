#!/usr/bin/env python3
"""Offline tests for meshy.py (no network, no key): python3 tools/meshy/test_meshy.py"""

from __future__ import annotations

import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import meshy  # noqa: E402

SPEC = {
    "mode": "text-to-3d",
    "ai_model": "meshy-7.1",
    "previews": 2,
    "pick": 0,
    "prompt": "test",
    "height_meters": 1.0,
    "output": "out/a",
    "texture": {"resolution": "2k"},
    "animations": [{"name": f"c{i}", "action_id": i} for i in range(12)],
}
TID = "01a1f99b-8ddc-721a-bee9-8ad524dc7415"


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        patcher = mock.patch.object(meshy, "REPO_ROOT", root)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.ledger = meshy.Ledger(root / "ledger.jsonl")
        self.manifest = {"assets": {"a": SPEC}}

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def runner(self, client: object, max_credits: int = 900) -> meshy.Runner:
        runner = meshy.Runner(self.manifest, self.ledger, max_credits, dry_run=False)
        runner._client = client  # type: ignore[assignment]
        return runner

    def rec(self, **kw: object) -> None:
        self.ledger.append({"asset": "a", "stage": "preview", "variant": 0, **kw})


def fake_download(_url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(b"glb")


class FakeClient:
    def __init__(self, post: object = None, get: object = None) -> None:
        self.post, self.get = post, get
        self.calls: list[tuple[str, str]] = []

    def request(self, method: str, path: str, body: object = None) -> object:
        self.calls.append((method, path))
        handler = self.post if method == "POST" else self.get
        if isinstance(handler, Exception):
            raise handler
        return handler(path) if callable(handler) else handler


class LedgerTests(Base):
    def test_in_flight_counts_estimate_then_consumed(self) -> None:
        self.rec(event="created", task_id="t1", est_credits=20)
        self.assertEqual(self.ledger.spent(), 20)
        self.rec(event="finished", task_id="t1", status="SUCCEEDED", consumed_credits=20)
        self.assertEqual(self.ledger.spent(), 20)

    def test_failed_task_costs_nothing_and_is_retryable(self) -> None:
        self.rec(event="created", stage="rig", task_id="t2", est_credits=5)
        self.rec(event="finished", stage="rig", task_id="t2", status="FAILED", consumed_credits=0)
        self.assertEqual(self.ledger.spent(), 0)
        self.assertIsNone(self.ledger.find("a", "rig"))

    def test_canceled_task_is_not_reused_but_still_counts(self) -> None:
        self.rec(event="created", task_id="t3", est_credits=20)
        self.rec(event="finished", task_id="t3", status="CANCELED", consumed_credits=0)
        self.assertIsNone(self.ledger.find("a", "preview"))
        self.assertEqual(self.ledger.spent(), 20)

    def test_supersede_keeps_spend_and_unblocks_regeneration(self) -> None:
        self.rec(event="created", task_id="t4", est_credits=20)
        self.rec(event="finished", task_id="t4", status="SUCCEEDED", consumed_credits=20)
        self.assertIsNotNone(self.ledger.find("a", "preview"))
        self.rec(event="superseded", task_id="t4")
        self.assertIsNone(self.ledger.find("a", "preview"))
        self.assertEqual(self.ledger.spent(), 20)

    def test_plan_batches_actions_by_ten_and_prices_them(self) -> None:
        tasks = meshy.build_tasks("a", SPEC, self.ledger)
        animate = [t for t in tasks if t.stage == "animate"]
        self.assertEqual([len(t.payload["action_ids"]) for t in animate], [10, 2])
        self.assertEqual(sum(t.est_credits for t in animate), 36)
        self.assertTrue(all(t.status == "pending" for t in tasks))


class UnriggedTests(Base):
    def test_unrigged_asset_stops_at_the_textured_mesh(self) -> None:
        spec = {**SPEC, "rig": {"skeleton_template": "none"}}
        self.assertTrue(meshy.is_unrigged(spec))
        self.assertFalse(meshy.is_unrigged(SPEC))
        tasks = meshy.build_tasks("a", spec, self.ledger)
        self.assertEqual({t.stage for t in tasks}, {"preview", "refine"})
        self.assertEqual(sum(t.est_credits for t in tasks), 20 + 10)  # picked preview + refine


class GuardTests(Base):
    def test_budget_guard_blocks_before_any_request(self) -> None:
        client = FakeClient(post=lambda _p: {"result": TID})
        task = meshy.build_tasks("a", SPEC, self.ledger)[0]
        with self.assertRaises(meshy.MeshyError):
            self.runner(client, max_credits=10).ensure(task, SPEC)
        self.assertEqual(client.calls, [])

    def test_cap_survives_regeneration(self) -> None:
        self.rec(event="created", task_id="t5", est_credits=20)
        self.rec(event="finished", task_id="t5", status="SUCCEEDED", consumed_credits=20)
        self.rec(event="superseded", task_id="t5")
        task = meshy.build_tasks("a", SPEC, self.ledger)[0]
        with self.assertRaises(meshy.MeshyError):
            self.runner(FakeClient(), max_credits=30).guard(task)

    def test_concurrent_reservations_cannot_both_pass(self) -> None:
        task = meshy.build_tasks("a", SPEC, self.ledger)[0]  # 20 credits
        outcomes: list[str] = []

        def attempt(variant: int) -> None:
            t = meshy.Task("a", "preview", variant, 20, {}, "x")
            try:
                self.runner(FakeClient(), max_credits=20).reserve(t)
                outcomes.append("ok")
            except meshy.MeshyError:
                outcomes.append("blocked")

        threads = [threading.Thread(target=attempt, args=(i,)) for i in (0, 1)]
        for th in threads:
            th.start()
        for th in threads:
            th.join()
        self.assertEqual(sorted(outcomes), ["blocked", "ok"])
        self.assertEqual(task.est_credits, 20)
        self.assertEqual(self.ledger.spent(), 20)


class DuplicateChargeTests(Base):
    def test_ambiguous_post_is_not_retried_and_blocks_recreate(self) -> None:
        client = FakeClient(post=meshy.AmbiguousCreateError("timeout"))
        task = meshy.build_tasks("a", SPEC, self.ledger)[0]
        with self.assertRaises(meshy.MeshyError):
            self.runner(client).ensure(task, SPEC)
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(self.ledger.spent(), 20)  # reserved
        retry = meshy.build_tasks("a", SPEC, self.ledger)[0]
        client2 = FakeClient(post=lambda _p: {"result": TID})
        with self.assertRaisesRegex(meshy.MeshyError, "reconcile"):
            self.runner(client2).ensure(retry, SPEC)
        self.assertEqual(client2.calls, [])

    def test_definitive_rejection_releases_reservation(self) -> None:
        client = FakeClient(post=meshy.MeshyError("HTTP 400"))
        task = meshy.build_tasks("a", SPEC, self.ledger)[0]
        with self.assertRaises(meshy.MeshyError):
            self.runner(client).ensure(task, SPEC)
        self.assertEqual(self.ledger.spent(), 0)
        self.assertEqual(self.ledger.pending_intents(), {})

    def test_reconcile_adopt_and_none(self) -> None:
        self.rec(event="intent", est_credits=20)
        args = mock.Mock(asset="a", stage="preview", variant=0, none=False, task_id=TID)
        meshy.cmd_reconcile(args, self.manifest, self.ledger)
        found = self.ledger.find("a", "preview")
        assert found is not None
        self.assertEqual(found["task_id"], TID)
        self.rec(event="intent", variant=1, est_credits=20)
        args = mock.Mock(asset="a", stage="preview", variant=1, none=True, task_id=None)
        meshy.cmd_reconcile(args, self.manifest, self.ledger)
        self.assertEqual(self.ledger.pending_intents(), {})

    def test_client_post_5xx_and_timeout_raise_ambiguous_without_retry(self) -> None:
        client = meshy.Client("k" * 10)
        err = urllib.error.HTTPError("u", 502, "bad", {}, None)  # type: ignore[arg-type]
        for failure in (err, TimeoutError(), urllib.error.URLError("x")):
            with mock.patch.object(client._opener, "open", side_effect=failure) as opener:
                with mock.patch.object(meshy.time, "sleep"):
                    with self.assertRaises(meshy.AmbiguousCreateError):
                        client.request("POST", "/openapi/v2/text-to-3d", {})
                self.assertEqual(opener.call_count, 1)


class EndpointSafetyTests(Base):
    def test_client_rejects_foreign_or_odd_paths(self) -> None:
        client = meshy.Client("k" * 10)
        for bad in ("@evil.example/x", "//evil.example/openapi/v1/x", "/other/v1/x",
                    "/openapi/v1/../x", "https://evil.example/openapi/v1/x"):
            with self.assertRaises(meshy.MeshyError):
                client.request("GET", bad)

    def test_client_refuses_redirects(self) -> None:
        handler = meshy._NoRedirect()
        self.assertIsNone(handler.redirect_request(mock.Mock(), None, 302, "m", {}, "https://evil"))

    def test_ledger_endpoint_is_ignored(self) -> None:
        self.rec(event="created", task_id=TID, est_credits=20, endpoint="@evil.example/x")
        client = FakeClient(get={"status": "FAILED"})
        task = meshy.build_tasks("a", SPEC, self.ledger)[0]
        with self.assertRaises(meshy.MeshyError):
            self.runner(client).wait(task)
        self.assertEqual(client.calls, [("GET", f"/openapi/v2/text-to-3d/{TID}")])

    def test_status_path_validates_task_id(self) -> None:
        for bad in ("../x", "a/b", "x?y=1", ""):
            with self.assertRaises(meshy.MeshyError):
                meshy.status_path("preview", bad)


class ResumeTests(Base):
    def done(self, status: str = "SUCCEEDED") -> dict[str, object]:
        return {"status": status, "model_urls": {"glb": "https://cdn/x.glb"}, "consumed_credits": 20}

    def test_download_failure_does_not_mark_finished(self) -> None:
        self.rec(event="created", task_id=TID, est_credits=20)
        task = meshy.build_tasks("a", SPEC, self.ledger)[0]
        client = FakeClient(get=self.done())
        with mock.patch.object(meshy, "download", side_effect=OSError("boom")):
            with self.assertRaises(OSError):
                self.runner(client).wait(task)
        found = self.ledger.find("a", "preview")
        assert found is not None
        self.assertEqual(found["event"], "created")

    def test_finished_task_with_missing_output_is_refetched_without_post(self) -> None:
        self.rec(event="created", task_id=TID, est_credits=20)
        self.rec(event="finished", task_id=TID, status="SUCCEEDED", consumed_credits=20)
        task = meshy.build_tasks("a", SPEC, self.ledger)[0]
        client = FakeClient(get=self.done())
        with mock.patch.object(meshy, "download", side_effect=fake_download) as dl:
            self.runner(client).ensure(task, SPEC)
        dl.assert_called_once()
        self.assertEqual([m for m, _ in client.calls], ["GET"])

    def test_finalize_fails_when_a_batch_is_missing(self) -> None:
        work = meshy.work_dir(SPEC)
        work.mkdir(parents=True)
        (work / "anim_0.glb").write_bytes(b"x")  # anim_1 absent
        with self.assertRaisesRegex(meshy.MeshyError, "anim_1.glb"):
            meshy.finalize_animation("a", SPEC)

    def test_canceled_task_is_recreated_not_skipped(self) -> None:
        self.rec(event="created", task_id=TID, est_credits=20)
        self.rec(event="finished", task_id=TID, status="CANCELED", consumed_credits=0)
        task = meshy.build_tasks("a", SPEC, self.ledger)[0]
        self.assertEqual(task.status, "pending")
        client = FakeClient(post={"result": "01a1f99c-0000-0000-0000-000000000000"},
                            get=self.done())
        with mock.patch.object(meshy, "download", side_effect=fake_download):
            self.runner(client).ensure(task, SPEC)
        self.assertIn("POST", [m for m, _ in client.calls])


if __name__ == "__main__":
    unittest.main()
