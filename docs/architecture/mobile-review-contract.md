# iPad and iPhone review contract

Status: Step 37 framework-neutral mobile review baseline

The shared UI package now exposes a mobile review view-model for the frozen
phone/tablet behavior:

```text
amount → deadline → delta → entitlement → proof → financial model → approval
```

An iPhone viewport is constrained to the phone breakpoint (at or below 768px).
An iPad review target is constrained to 768–1100px. Both targets carry
provenance-backed money values and visible status labels. Heavy drawing
comparison is either available on the tablet target or produces the explicit
`Open on desktop/iPad` prompt on the phone target.

The approval value is a shared, confirmation-required action; it is not an
offline execution path and does not submit a notice. This contract has no iOS
or App Store project, push provider, or live server adapter yet.
