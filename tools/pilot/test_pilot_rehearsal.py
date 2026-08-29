#!/usr/bin/env python3
"""Tests for the isolated pilot rehearsal proof layer."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from run_rehearsal import (
    ROOT,
    build_rehearsal,
    evaluate_case,
    read_json,
    validate_compose_isolation,
    write_proof,
)
from verify_pilot_rehearsal import validate


class PilotRehearsalTests(unittest.TestCase):
    def test_compose_isolation_is_loopback_and_internal(self) -> None:
        stack = validate_compose_isolation()
        self.assertTrue(stack["network_internal"])
        self.assertGreaterEqual(stack["loopback_ports"], 6)
        self.assertEqual(stack["production_endpoint_contact_count"], 0)

    def test_bundle_is_verifiable_and_holds_release(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            bundle = build_rehearsal(run_id="pilot-test-replay")
            write_proof(bundle, Path(directory))
            result = validate(Path(directory))
            self.assertEqual(result["case_count"], 14)
            self.assertEqual(result["pilot_recommendation"], "HOLD")
            self.assertEqual(result["review"], "PENDING")
            packet = read_json(Path(directory) / "pilot-evidence-packet.v1.json")
            blind = read_json(Path(directory) / "blind-review-packet.v1.json")
            self.assertEqual(packet["final_state"]["pilot_recommendation"], "HOLD")
            blind_text = json.dumps(blind, sort_keys=True)
            self.assertNotIn('"expected":', blind_text)
            self.assertNotIn('"label":', blind_text)

    def test_same_run_id_reproduces_case_and_receipt_hashes(self) -> None:
        first = build_rehearsal(run_id="pilot-test-replay")
        second = build_rehearsal(run_id="pilot-test-replay")
        self.assertEqual(first["report"]["report_sha256"], second["report"]["report_sha256"])
        self.assertEqual(first["run_manifest"]["receipt_chain_root_sha256"], second["run_manifest"]["receipt_chain_root_sha256"])
        self.assertEqual(
            [item["output_sha256"] for item in first["report"]["case_results"]],
            [item["output_sha256"] for item in second["report"]["case_results"]],
        )

    def test_authority_mutations_fail_closed(self) -> None:
        fixtures = read_json(ROOT / "fixtures/pilot/manifest.v1.json")
        cases = {item["case_id"]: item for item in fixtures["cases"]}
        observed = evaluate_case(cases["action-payload-mutation"])
        self.assertEqual(observed["observed"]["decision"], "DENY")
        self.assertEqual(observed["observed"]["reason"], "PAYLOAD_MUTATION")
        self.assertFalse(observed["opportunity_prediction"])

    def test_provider_outage_persists_no_facts(self) -> None:
        fixtures = read_json(ROOT / "fixtures/pilot/manifest.v1.json")
        outage = next(item for item in fixtures["cases"] if item["case_id"] == "provider-outage")
        result = evaluate_case(outage)
        self.assertEqual(result["observed"]["decision"], "PROVIDER_FAILURE")
        self.assertEqual(result["observed"]["persisted_candidate_facts"], 0)
        self.assertEqual(result["observed"]["persisted_verified_facts"], 0)


if __name__ == "__main__":
    unittest.main()
