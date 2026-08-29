# ADR-003: Governance bindings are a separate, fail-closed registry

Status: Accepted for Step 23 of SPEC-1.6

The enforcement-binding registry is the machine bridge between canonical
governance text and executable code. It is intentionally empty and
`NOT_READY` until a later step binds the first Recoveries authority rule.

Each binding must name its canonical rule, authority class, system component,
operation, enforcement point, implementation commit, test, proof fixture, and
fail mode. The only permitted fail mode is `DENY`. Binding IDs are unique, and
an `ACTIVE` binding must point to files that exist in this repository.

The validator checks exact fields, identifier formats, frozen-spec provenance,
duplicate IDs, and active-reference existence. It does not grant authority,
execute actions, or infer readiness from prose. Readiness remains `NOT_READY`
until the first binding has positive, negative, mutation, and release-provenance
proof.
