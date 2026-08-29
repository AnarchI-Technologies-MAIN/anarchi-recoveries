#!/usr/bin/env python3

from __future__ import annotations

import unittest

from payment_boundary import run_test_boundary, sign_webhook, verify_signature


class PaymentBoundaryTests(unittest.TestCase):
    def test_complete_test_mode_boundary_is_receipted_without_network_or_credentials(self) -> None:
        receipt = run_test_boundary(checkout_id="checkout-001", amount="2200.00")
        self.assertTrue(receipt["checkout_requested"])
        self.assertTrue(receipt["payment_initiated"])
        self.assertTrue(receipt["webhook_received"])
        self.assertTrue(receipt["signature_verified"])
        self.assertTrue(receipt["event_deduplicated"])
        self.assertTrue(receipt["amount_currency_catalog_matched"])
        self.assertEqual(receipt["business_state"], "PAID")
        self.assertEqual(receipt["network_contact_count"], 0)
        self.assertFalse(receipt["credentials_loaded"])

    def test_signature_and_catalog_mismatch_fail_closed(self) -> None:
        payload = b"{}"
        signature = sign_webhook(payload)
        self.assertTrue(verify_signature(payload, signature))
        self.assertFalse(verify_signature(b"{\"mutated\":true}", signature))
        receipt = run_test_boundary(
            checkout_id="checkout-mismatch",
            amount="2200.00",
            catalog_price="2201.00",
        )
        self.assertFalse(receipt["amount_currency_catalog_matched"])
        self.assertEqual(receipt["business_state"], "HOLD")


if __name__ == "__main__":
    unittest.main()
