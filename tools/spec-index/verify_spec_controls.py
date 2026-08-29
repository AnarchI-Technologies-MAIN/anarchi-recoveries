#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    drift_path = REPOSITORY_ROOT / "governance/drift-control-registry.v1.json"
    repository_map_path = REPOSITORY_ROOT / "governance/repository-map.v1.json"
    drift = json.loads(drift_path.read_text(encoding="utf-8"))
    repository_map = json.loads(repository_map_path.read_text(encoding="utf-8"))

    rules = drift["rules"]
    numbers = [rule["number"] for rule in rules]
    if drift["rule_count"] != 90 or numbers != list(range(1, 91)):
        raise SystemExit("drift registry is not exactly sequential rules 1..90")
    if len({rule["id"] for rule in rules}) != 90:
        raise SystemExit("drift registry contains duplicate identifiers")

    missing = [
        entry["path"]
        for entry in repository_map["directories"]
        if not (REPOSITORY_ROOT / entry["path"]).is_dir()
    ]
    if missing:
        raise SystemExit(f"repository map paths are missing: {missing}")

    valid_statuses = {"IMPLEMENTED", "PARTIAL", "SCAFFOLDED", "NOT_STARTED"}
    invalid = [
        entry for entry in repository_map["directories"] if entry["status"] not in valid_statuses
    ]
    if invalid:
        raise SystemExit(f"repository map contains invalid status values: {invalid}")

    print(f"drift_rules={len(rules)} PASS")
    print(f"repository_paths={len(repository_map['directories'])} PASS")


if __name__ == "__main__":
    main()

