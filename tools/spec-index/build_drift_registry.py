#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SPEC_PATH = REPOSITORY_ROOT / "docs/specification/SPEC-1.6-AnarchI-Tech-Recoveries-FROZEN.md"
OUTPUT_PATH = REPOSITORY_ROOT / "governance/drift-control-registry.v1.json"
HEADING = "### 68. Drift-control registry"


def main() -> None:
    spec_bytes = SPEC_PATH.read_bytes()
    spec_text = spec_bytes.decode("utf-8")
    try:
        section = spec_text.split(HEADING, 1)[1].split("\n---", 1)[0]
    except IndexError as error:
        raise SystemExit("frozen drift-control section not found") from error

    parsed = re.findall(r"^(\d+)\. (.+)$", section, flags=re.MULTILINE)
    numbers = [int(number) for number, _ in parsed]
    if numbers != list(range(1, 91)):
        raise SystemExit(f"expected frozen drift rules 1..90, observed {numbers}")

    registry = {
        "schema": "anarchi.recoveries.drift-control-registry.v1",
        "status": "FROZEN",
        "source": {
            "path": str(SPEC_PATH.relative_to(REPOSITORY_ROOT)),
            "heading": HEADING,
            "sha256": hashlib.sha256(spec_bytes).hexdigest(),
        },
        "rule_count": len(parsed),
        "rules": [
            {
                "id": f"DRIFT-{number:03d}",
                "number": number,
                "text": text,
            }
            for number, text in ((int(number), text) for number, text in parsed)
        ],
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(
        json.dumps(registry, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )


if __name__ == "__main__":
    main()

