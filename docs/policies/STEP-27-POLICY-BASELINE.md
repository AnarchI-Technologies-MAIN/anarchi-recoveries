# Step 27 policy baseline — review required

Status: `DRAFT_FOR_REVIEW`; not a signed contract, privacy notice, DPA, or
security certification. This baseline translates the frozen SPEC-1.6 launch
posture into reviewable controls. Production activation is explicitly false.

## Customer data and AI

- The customer owns customer data and evidence; AnarchI receives only the
  limited license needed to operate the service.
- Customer evidence is not used for general-purpose model training by default.
- External AI receives only minimum evidence for configured extraction, under a
  reviewed provider/subprocessor agreement that prohibits training where
  available.
- AI access is policy-authorized and version-attributed. AI receives no Vault
  secrets, connector credentials, raw tokens, or unrestricted database access.
- A customer may disable external-AI processing and use manual/local workflows.
- Deletion propagates through AnarchI systems and contracted processors under
  the selected retention policy. Governance canon/history is institutional
  history, not customer data.

## Retention and deletion

Deletion is a lifecycle transition, not a boolean. The launch defaults are:

```text
ACTIVE while service is active
EXPORT_WINDOW for 30 days after termination
DELETION_SCHEDULED after the export window
BACKUP_EXPIRING with ordinary backups aging out within 90 days
LEGAL_HOLD only when required by law, contract, fraud prevention, accounting, or security
GOVERNANCE_CANON institutional retention where applicable
```

Customer project evidence remains customer-controlled; longer retention must be
selected or contracted. An export path and deletion propagation proof are
required before a customer-facing launch claim.

## Legal and commercial posture

The launch assumption is United States service delivery under Kansas governing
law and venue, with a signed MSA plus Order Form, electronic execution, and a
30-day success-fee dispute window. The service is software-assisted recovery
identification, evidence organization, deterministic calculation, workflow,
submission preparation, tracking, reconciliation, and attribution.

It is not legal advice, legal representation, a guaranteed recovery, or final
authoritative contract interpretation. The customer remains responsible for
legal/contractual judgment and supplied-data accuracy. Counsel must review the
MSA, Order Form, Success Fee Schedule, Privacy Policy, DPA, Acceptable Use
Policy, Security Overview, Subprocessor List, and Support Policy before use.

## Pilot support and security

Pilot/Early Access offers commercially reasonable availability, practical
maintenance notice, severity-based response, and no service-credit SLA. The
initial response targets are SEV-1: 1 hour, SEV-2: 4 hours, SEV-3: 1 business
day, and SEV-4: 2 business days.

The security program is organized around GOVERN, IDENTIFY, PROTECT, DETECT,
RESPOND, and RECOVER, with TLS, encrypted OAuth secrets, privileged MFA,
tenant RLS, private S3 and signed URLs, separate NATS credentials, CSRF and
webhook validation, OAuth state/PKCE, rate limiting, dependency/secret
scanning, backup/restore validation, environment separation, least privilege,
audit trails, incident response, vulnerability management, vendor review,
secure SDLC, endpoint security, key management, and disclosure process.
