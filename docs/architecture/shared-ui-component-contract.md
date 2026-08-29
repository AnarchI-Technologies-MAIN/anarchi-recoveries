# Shared UI component contract

Status: Step 29 shared primitive baseline

`@anarchi/ui` is framework-neutral so the web, Windows Tauri shell, and later
mobile clients can share the same component semantics. It does not create a
second authority or perform network work.

The primitives enforce four product rules from SPEC-1.6:

- status labels carry visible text and an ARIA label; color is never the only
  meaning;
- money lines carry decimal-string amount, explicit ISO currency, and a
  provenance reference;
- proof-chain items carry event, time, core/policy versions, and a lowercase
  SHA-256 evaluation hash;
- external actions name the side effect and target system and require explicit
  confirmation.

Screen layout, accessibility audits, and client adapters remain later steps.
