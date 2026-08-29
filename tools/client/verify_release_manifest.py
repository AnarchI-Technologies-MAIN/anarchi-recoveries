#!/usr/bin/env python3
"""Validate the fail-closed Windows release manifest without releasing anything."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "apps/client/release-manifest.v1.json"
SPEC_SHA256 = "0e3877aff0832db9cc0503d9a8769f2b867a1536441fba149874360fbb8f8869"


def _sha256(value: str) -> bool:
    return len(value) == 64 and all(character in "0123456789abcdef" for character in value)


def validate(manifest: object) -> None:
    if not isinstance(manifest, dict):
        raise ValueError("release manifest must be an object")
    if manifest.get("schema") != "anarchi.recoveries.client-release-manifest.v1":
        raise ValueError("unexpected release manifest schema")
    if manifest.get("spec_sha256") != SPEC_SHA256:
        raise ValueError("release manifest is not pinned to the frozen spec")
    if manifest.get("status") not in {"NOT_RELEASED", "RELEASED"}:
        raise ValueError("release status must be NOT_RELEASED or RELEASED")
    if manifest.get("product") != "ANARCHI / RECOVERIES":
        raise ValueError("release product identity mismatch")
    target = manifest.get("target")
    if target != {
        "platform": "windows",
        "architecture": "x64",
        "installer_name": "AnarchI-Recoveries-x64-Setup.exe",
        "install_scope": "user",
    }:
        raise ValueError("Windows user-level target must match the frozen release target")
    update = manifest.get("update")
    if not isinstance(update, dict) or update.get("requires_signed_artifact") is not True or update.get("requires_release_receipt") is not True:
        raise ValueError("updates require signed artifact and release receipt")
    artifact = manifest.get("artifact")
    signature = manifest.get("signature")
    if manifest["status"] == "NOT_RELEASED":
        if artifact is not None or signature is not None:
            raise ValueError("unreleased manifest cannot claim artifact or signature")
        if update.get("channel") != "disabled_until_signed":
            raise ValueError("unreleased update channel must be disabled")
        return
    if not isinstance(artifact, dict) or not isinstance(signature, dict):
        raise ValueError("released manifest requires artifact and signature records")
    if artifact.get("path") != "AnarchI-Recoveries-x64-Setup.exe" or not _sha256(artifact.get("sha256", "")):
        raise ValueError("released artifact path/hash is invalid")
    if signature.get("algorithm") != "Authenticode" or not _sha256(signature.get("certificate_sha256", "")):
        raise ValueError("released artifact signature proof is invalid")
    if update.get("channel") == "disabled_until_signed":
        raise ValueError("released update channel cannot remain disabled")


def main() -> None:
    validate(json.loads(MANIFEST.read_text(encoding="utf-8")))
    print("release_manifest=PASS")
    print("release_status=NOT_RELEASED")
    print(f"manifest_sha256={hashlib.sha256(MANIFEST.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
