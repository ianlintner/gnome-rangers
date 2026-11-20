#!/usr/bin/env python3
"""Offline tests for meshy.py (no network, no key): python3 tools/meshy/test_meshy.py"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import meshy  # noqa: E402

SPEC = {
    "mode": "text-to-3d",
    "ai_model": "meshy-7.1",
    "previews": 2,
    "pick": 0,
    "prompt": "test",
    "height_meters": 1.0,
    "texture": {"resolution": "2k"},
    "animations": [{"name": f"c{i}", "action_id": i} for i in range(12)],
}


class LedgerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.ledger = meshy.Ledger(Path(self.tmp.name) / "ledger.jsonl")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_in_flight_counts_estimate_then_consumed(self) -> None:
        self.ledger.append(
            {"event": "created", "asset": "a", "stage": "preview", "task_id": "t1", "est_credits": 20}
        )
        self.assertEqual(self.ledger.spent(), 20)
        self.ledger.append(
            {"event": "finished", "asset": "a", "stage": "preview", "task_id": "t1",
             "status": "SUCCEEDED", "consumed_credits": 20}
        )
        self.assertEqual(self.ledger.spent(), 20)

    def test_failed_task_is_refunded_and_retryable(self) -> None:
        self.ledger.append(
            {"event": "created", "asset": "a", "stage": "rig", "task_id": "t2", "est_credits": 5}
        )
        self.ledger.append(
            {"event": "finished", "asset": "a", "stage": "rig", "task_id": "t2",
             "status": "FAILED", "consumed_credits": 0}
        )
        self.assertEqual(self.ledger.spent(), 0)
        self.assertIsNone(self.ledger.find("a", "rig"))

    def test_plan_batches_actions_by_ten_and_prices_them(self) -> None:
        tasks = meshy.build_tasks("a", SPEC, self.ledger)
        animate = [t for t in tasks if t.stage == "animate"]
        self.assertEqual([len(t.payload["action_ids"]) for t in animate], [10, 2])
        self.assertEqual(sum(t.est_credits for t in animate), 36)
        self.assertTrue(all(t.status == "pending" for t in tasks))

    def test_budget_guard_blocks_before_any_request(self) -> None:
        runner = meshy.Runner({"assets": {"a": SPEC}}, self.ledger, max_credits=10, dry_run=False)
        task = meshy.build_tasks("a", SPEC, self.ledger)[0]
        with self.assertRaises(meshy.MeshyError):
            runner.guard(task)


if __name__ == "__main__":
    unittest.main()
