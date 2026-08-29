#!/usr/bin/env python3

from __future__ import annotations

import unittest

from adjudicate_review import adjudicate
from run_rehearsal import build_rehearsal, build_blind_packet


class IndependentAdjudicationTests(unittest.TestCase):
    def test_reviewer_can_adjudicate_without_expected_labels(self) -> None:
        bundle = build_rehearsal(run_id="pilot-adjudication-test")
        blind = build_blind_packet(bundle["packet"])
        input_value = {
            "schema": "anarchi.recoveries.independent-adjudication.v1",
            "reviewer_id": "reviewer-test-001",
            "reviewed_at": "2026-08-29T00:00:00Z",
            "cases": [
                {
                    "case_id": item["case_id"],
                    "human_conclusion": item["observed"]["decision"],
                    "dimensions": {
                        "opportunity_precision": True,
                        "financial_exactness": True,
                        "evidence_sufficiency": True,
                        "authority_correctness": True,
                        "replay_identity": True,
                        "action_integrity": True,
                        "attribution_correctness": True,
                        "unknown_preservation": True,
                        "false_positive_prevention": True,
                    },
                }
                for item in blind["decision_trace"]
            ],
        }
        result = adjudicate(blind, input_value)
        self.assertEqual(result["threshold_decision"], "DEFERRED_TO_FORMAL_PILOT_ADJUDICATION")
        self.assertTrue(all(item["conclusion_agreement"] for item in result["comparisons"]))
        self.assertEqual(result["dimension_results"]["authority_correctness"]["fail"], 0)

    def test_incomplete_adjudication_is_rejected(self) -> None:
        bundle = build_rehearsal(run_id="pilot-adjudication-test")
        blind = build_blind_packet(bundle["packet"])
        with self.assertRaises(ValueError):
            adjudicate(
                blind,
                {
                    "schema": "anarchi.recoveries.independent-adjudication.v1",
                    "reviewer_id": "reviewer-test-001",
                    "cases": [],
                },
            )


if __name__ == "__main__":
    unittest.main()
