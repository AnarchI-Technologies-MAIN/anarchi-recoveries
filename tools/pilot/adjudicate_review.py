#!/usr/bin/env python3
"""Compare an independent blind adjudication with the recorded conclusion."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from verify_pilot_rehearsal import digest, VerificationError


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def adjudicate(blind_packet: dict[str, Any], input_value: dict[str, Any]) -> dict[str, Any]:
    if blind_packet.get("schema") != "anarchi.recoveries.pilot-blind-review-packet.v1":
        raise VerificationError("review input must be a blind packet")
    if input_value.get("schema") != "anarchi.recoveries.independent-adjudication.v1":
        raise VerificationError("unexpected adjudication schema")
    if not input_value.get("reviewer_id"):
        raise VerificationError("reviewer identity is required")
    observed = {item["case_id"]: item["observed"] for item in blind_packet["decision_trace"]}
    supplied = {item["case_id"]: item for item in input_value.get("cases", [])}
    if set(supplied) != set(observed):
        raise VerificationError("adjudication must cover every blind-packet case exactly once")
    comparisons = []
    dimension_totals: dict[str, dict[str, int]] = {}
    for case_id, item in supplied.items():
        human = item.get("human_conclusion")
        if not isinstance(human, str) or not human.strip():
            raise VerificationError(f"human conclusion is required for {case_id}")
        recoveries = observed[case_id].get("decision")
        dimensions = item.get("dimensions", {})
        if not isinstance(dimensions, dict):
            raise VerificationError(f"dimensions must be an object for {case_id}")
        comparisons.append({
            "case_id": case_id,
            "recoveries_conclusion": recoveries,
            "independent_conclusion": human,
            "conclusion_agreement": recoveries == human,
            "dimensions": dimensions,
        })
        for name, value in dimensions.items():
            if not isinstance(value, bool):
                raise VerificationError(f"dimension {name} must be boolean for {case_id}")
            totals = dimension_totals.setdefault(name, {"pass": 0, "fail": 0})
            totals["pass" if value else "fail"] += 1
    result = {
        "schema": "anarchi.recoveries.independent-adjudication-result.v1",
        "canonicalization": "ANARCHI-JCS-COMPATIBLE-V1",
        "run_id": blind_packet.get("run_id"),
        "blind_packet_sha256": blind_packet.get("packet_sha256"),
        "reviewer_id": input_value["reviewer_id"],
        "reviewed_at": input_value.get("reviewed_at"),
        "comparisons": comparisons,
        "dimension_results": dimension_totals,
        "threshold_decision": "DEFERRED_TO_FORMAL_PILOT_ADJUDICATION",
        "authority": {"production_mutated": False, "release_authority": "none"},
    }
    result["result_sha256"] = digest(result)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("blind_packet", type=Path)
    parser.add_argument("adjudication", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = adjudicate(load(args.blind_packet), load(args.adjudication))
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print("independent_adjudication=PASS")
        print(f"result_sha256={result['result_sha256']}")
        return 0
    except (OSError, json.JSONDecodeError, VerificationError) as error:
        print(f"independent_adjudication=HOLD: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
