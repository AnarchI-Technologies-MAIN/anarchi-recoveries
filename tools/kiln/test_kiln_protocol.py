import copy
import json
import unittest
from pathlib import Path

from kiln_protocol import (
    forbid_authority,
    fracture_proof,
    make_specimen,
    mutate,
    restoration_proof,
    survivor_proof,
)


ROOT = Path(__file__).resolve().parents[2]


class KilnProtocolTests(unittest.TestCase):
    def setUp(self):
        source = json.loads((ROOT / "fixtures/kiln/recovery-specimen.v1.json").read_text(encoding="utf-8"))
        self.specimen = make_specimen("kiln-specimen-1", source)

    def test_mutation_fractures_digest_without_mutating_source(self):
        original = copy.deepcopy(self.specimen.source)
        result = mutate(self.specimen, ("payload", "amount"), "125.00")
        self.assertEqual(self.specimen.source, original)
        self.assertTrue(fracture_proof(result).passed)

    def test_survivor_and_restoration_proofs_are_explicit(self):
        result = mutate(self.specimen, ("payload", "amount"), "125.00")
        self.assertTrue(survivor_proof(result, (("payload", "recovery_id"), ("payload", "amount"))).passed)
        self.assertTrue(restoration_proof(self.specimen, copy.deepcopy(self.specimen.source)).passed)
        self.assertFalse(restoration_proof(self.specimen, result.mutated).passed)

    def test_kiln_cannot_grant_authority(self):
        for action in ("repair", "promote", "commit", "push", "publish", "deploy", "authorize"):
            with self.assertRaisesRegex(PermissionError, "Kiln cannot"):
                forbid_authority(action)


if __name__ == "__main__":
    unittest.main()
