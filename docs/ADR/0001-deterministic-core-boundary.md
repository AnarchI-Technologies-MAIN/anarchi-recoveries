# ADR 0001: Deterministic recovery-core boundary

Status: accepted for M1

## Decision

The recovery core is a stateless pure Rust library. Every value that can affect
a decision is supplied explicitly, including evaluation time and all rule
versions. The core does not read a clock, database, network, environment,
secret, governance repository, or model provider.

Financial values cross the boundary as decimal strings with explicit ISO 4217
currency. Required rate, markup, tax, and rounding rules fail closed when
missing or unsupported.

AI-extracted facts are outside this boundary until verified. Authorization and
execution remain outside this boundary entirely.

## Consequences

The same semantic inputs and versions produce the same semantic decision and
canonical digest. A valid no-opportunity result is a domain decision, not an
engine error. Missing mandatory financial or provenance data is an error and
cannot silently produce a price.

