#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MAP_PATH = REPOSITORY_ROOT / "governance/repository-map.v1.json"


def main() -> None:
    repository_map = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    for entry in repository_map["directories"]:
        directory = REPOSITORY_ROOT / entry["path"]
        directory.mkdir(parents=True, exist_ok=True)
        if not any(directory.iterdir()):
            (directory / ".gitkeep").touch(exist_ok=True)


if __name__ == "__main__":
    main()
