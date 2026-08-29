BEGIN;

CREATE TABLE recoveries.facts (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    fact_type text NOT NULL CHECK (btrim(fact_type) <> ''),
    subject text NOT NULL CHECK (btrim(subject) <> ''),
    value jsonb NOT NULL CHECK (jsonb_typeof(value) = 'object'),
    unit text,
    currency text CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$'),
    source_evidence_id uuid NOT NULL,
    source_location text NOT NULL CHECK (btrim(source_location) <> ''),
    extraction_method text NOT NULL CHECK (btrim(extraction_method) <> ''),
    model_or_parser_version text NOT NULL CHECK (btrim(model_or_parser_version) <> ''),
    candidate_confidence numeric(6, 5)
        CHECK (candidate_confidence IS NULL OR candidate_confidence BETWEEN 0 AND 1),
    verification_status text NOT NULL
        CHECK (verification_status IN ('CANDIDATE', 'VERIFIED', 'REJECTED')),
    verified_by uuid REFERENCES recoveries.users(id) ON DELETE RESTRICT,
    verified_at timestamptz,
    supersedes_fact_id uuid,
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    FOREIGN KEY (organization_id, project_id, source_evidence_id)
        REFERENCES recoveries.evidence(organization_id, project_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, supersedes_fact_id)
        REFERENCES recoveries.facts(organization_id, id) ON DELETE RESTRICT,
    CHECK (
        (verification_status = 'VERIFIED' AND verified_by IS NOT NULL AND verified_at IS NOT NULL)
        OR verification_status <> 'VERIFIED'
    ),
    CHECK (supersedes_fact_id IS NULL OR supersedes_fact_id <> id)
);

CREATE TABLE recoveries.project_events (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    event_type text NOT NULL CHECK (btrim(event_type) <> ''),
    occurred_at timestamptz NOT NULL,
    source_evidence_id uuid NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(attributes) = 'object'),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    FOREIGN KEY (organization_id, project_id, source_evidence_id)
        REFERENCES recoveries.evidence(organization_id, project_id, id) ON DELETE RESTRICT
);

CREATE TABLE recoveries.recovery_opportunities (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    baseline_id uuid NOT NULL,
    detection_class text NOT NULL CHECK (detection_class IN (
        'DRAWING_QUANTITY_DELTA',
        'RFI_DIRECTIVE_SCOPE_CHANGE',
        'TM_UNCONVERTED',
        'ATTACHED_COST_RECORDS'
    )),
    status text NOT NULL CHECK (status IN (
        'DETECTED', 'EVIDENCE_PENDING', 'READY_FOR_REVIEW', 'APPROVED',
        'NOTICE_READY', 'NOTICE_SENT', 'COR_PREPARED', 'COR_SUBMITTED',
        'APPROVED_BY_COUNTERPARTY', 'INVOICED', 'PARTIALLY_PAID', 'FULLY_PAID',
        'DUPLICATE', 'REJECTED', 'WITHDRAWN', 'EXPIRED', 'DISPUTED',
        'MORE_EVIDENCE_REQUIRED', 'VERIFICATION_ONLY', 'WRITTEN_OFF'
    )),
    domain_rule_version text NOT NULL CHECK (btrim(domain_rule_version) <> ''),
    pricing_rule_version text NOT NULL CHECK (btrim(pricing_rule_version) <> ''),
    notice_rule_version text NOT NULL CHECK (btrim(notice_rule_version) <> ''),
    evaluation_time timestamptz NOT NULL,
    evaluation_hash text NOT NULL CHECK (evaluation_hash ~ '^[a-f0-9]{64}$'),
    decision jsonb NOT NULL CHECK (jsonb_typeof(decision) = 'object'),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    UNIQUE (organization_id, project_id, evaluation_hash),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES recoveries.projects(organization_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, project_id, baseline_id)
        REFERENCES recoveries.contract_baselines(organization_id, project_id, id) ON DELETE RESTRICT
);

CREATE TABLE recoveries.opportunity_facts (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    opportunity_id uuid NOT NULL,
    fact_id uuid NOT NULL,
    purpose text NOT NULL CHECK (btrim(purpose) <> ''),
    PRIMARY KEY (organization_id, opportunity_id, fact_id),
    FOREIGN KEY (organization_id, project_id, opportunity_id)
        REFERENCES recoveries.recovery_opportunities(organization_id, project_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, project_id, fact_id)
        REFERENCES recoveries.facts(organization_id, project_id, id) ON DELETE RESTRICT
);

CREATE TABLE recoveries.opportunity_evidence (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    opportunity_id uuid NOT NULL,
    evidence_id uuid NOT NULL,
    purpose text NOT NULL CHECK (btrim(purpose) <> ''),
    PRIMARY KEY (organization_id, opportunity_id, evidence_id),
    FOREIGN KEY (organization_id, project_id, opportunity_id)
        REFERENCES recoveries.recovery_opportunities(organization_id, project_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, project_id, evidence_id)
        REFERENCES recoveries.evidence(organization_id, project_id, id) ON DELETE RESTRICT
);

CREATE TABLE recoveries.pricing_calculations (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    opportunity_id uuid NOT NULL,
    currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    raw_subtotal numeric(24, 2) NOT NULL CHECK (raw_subtotal >= 0),
    total_markup numeric(24, 2) NOT NULL CHECK (total_markup >= 0),
    tax numeric(24, 2) NOT NULL CHECK (tax >= 0),
    total numeric(24, 2) NOT NULL CHECK (total >= 0),
    pricing_rule_version text NOT NULL CHECK (btrim(pricing_rule_version) <> ''),
    rounding_rule_version text NOT NULL CHECK (btrim(rounding_rule_version) <> ''),
    tax_rule_version text NOT NULL CHECK (btrim(tax_rule_version) <> ''),
    canonical_sha256 text NOT NULL CHECK (canonical_sha256 ~ '^[a-f0-9]{64}$'),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    UNIQUE (organization_id, opportunity_id),
    FOREIGN KEY (organization_id, project_id, opportunity_id)
        REFERENCES recoveries.recovery_opportunities(organization_id, project_id, id) ON DELETE RESTRICT,
    CHECK (total = raw_subtotal + total_markup + tax)
);

CREATE TABLE recoveries.pricing_lines (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    pricing_calculation_id uuid NOT NULL,
    line_number integer NOT NULL CHECK (line_number > 0),
    class text NOT NULL CHECK (class IN (
        'LABOR', 'MATERIAL', 'EQUIPMENT', 'SUBCONTRACTOR', 'BURDEN',
        'MATERIAL_MARKUP', 'EQUIPMENT_MARKUP', 'TAX'
    )),
    description text NOT NULL CHECK (btrim(description) <> ''),
    amount numeric(24, 2) NOT NULL,
    currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    rule_version text NOT NULL CHECK (btrim(rule_version) <> ''),
    evidence_ids uuid[] NOT NULL DEFAULT '{}',
    PRIMARY KEY (organization_id, pricing_calculation_id, line_number),
    FOREIGN KEY (organization_id, project_id, pricing_calculation_id)
        REFERENCES recoveries.pricing_calculations(organization_id, project_id, id) ON DELETE RESTRICT
);

COMMIT;
