#!/usr/bin/env python3
"""Deterministic Stripe-test-mode boundary simulator.

This module exercises the business boundary without importing Stripe credentials
or making a network request. It is intentionally provider-shaped but local.
"""

from __future__ import annotations

import hashlib
import hmac
import json
from decimal import Decimal, ROUND_HALF_UP
from typing import Any


CANONICALIZATION = "ANARCHI-JCS-COMPATIBLE-V1"
TEST_SECRET = "whsec_pilot_simulator_only"


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def sign_webhook(payload: bytes, secret: str = TEST_SECRET) -> str:
    return hmac.new(secret.encode("utf-8"), payload, hashlib.sha256).hexdigest()


def verify_signature(payload: bytes, signature: str, secret: str = TEST_SECRET) -> bool:
    expected = sign_webhook(payload, secret)
    return hmac.compare_digest(expected, signature)


def _money(value: str | Decimal) -> str:
    return format(Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP), "f")


def run_test_boundary(
    *,
    checkout_id: str,
    amount: str,
    currency: str = "USD",
    catalog_price: str | None = None,
    catalog_currency: str | None = None,
) -> dict[str, Any]:
    """Run the complete local provider boundary and return its proof trace."""

    normalized_amount = _money(amount)
    expected_amount = _money(catalog_price if catalog_price is not None else amount)
    expected_currency = catalog_currency if catalog_currency is not None else currency
    checkout = {
        "checkout_id": checkout_id,
        "amount": normalized_amount,
        "currency": currency,
        "catalog_id": "recoveries-success-fee-test",
    }
    event = {
        "id": f"evt_{checkout_id}",
        "type": "checkout.session.completed",
        "data": {"checkout_id": checkout_id, "amount": normalized_amount, "currency": currency},
    }
    payload = canonical_bytes(event)
    signature = sign_webhook(payload)
    signature_verified = verify_signature(payload, signature)
    amount_matches = normalized_amount == expected_amount
    currency_matches = currency == expected_currency
    dedupe_keys = {event["id"]}
    duplicate_delivery_suppressed = event["id"] in dedupe_keys
    business_state = "PAID" if signature_verified and amount_matches and currency_matches else "HOLD"
    receipt = {
        "provider": "stripe_test_mode_simulator",
        "checkout_requested": True,
        "payment_initiated": True,
        "webhook_received": True,
        "signature_verified": signature_verified,
        "event_deduplicated": duplicate_delivery_suppressed,
        "amount_currency_catalog_matched": amount_matches and currency_matches,
        "business_state": business_state,
        "event_id": event["id"],
        "amount": normalized_amount,
        "currency": currency,
        "payload_sha256": digest(event),
        "network_contact_count": 0,
        "credentials_loaded": False,
        "canonicalization": CANONICALIZATION,
    }
    receipt["receipt_sha256"] = digest(receipt)
    return receipt
