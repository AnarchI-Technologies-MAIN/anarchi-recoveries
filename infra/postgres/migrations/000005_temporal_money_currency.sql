BEGIN;

CREATE UNIQUE INDEX contract_baselines_one_active_per_project
    ON recoveries.contract_baselines (organization_id, project_id)
    WHERE status = 'ACTIVE';

ALTER TABLE recoveries.scope_item_versions
    ADD CONSTRAINT scope_item_versions_no_overlapping_validity
    EXCLUDE USING gist (
        organization_id WITH =,
        scope_item_id WITH =,
        int4range(valid_from_baseline_version, valid_to_baseline_version, '[]') WITH &&
    );

ALTER TABLE recoveries.pricing_calculations
    ADD CONSTRAINT pricing_calculations_tenant_project_currency_key
    UNIQUE (organization_id, project_id, id, currency);

ALTER TABLE recoveries.pricing_lines
    DROP CONSTRAINT pricing_lines_organization_id_project_id_pricing_calculati_fkey,
    ADD CONSTRAINT pricing_lines_amount_nonnegative CHECK (amount >= 0),
    ADD CONSTRAINT pricing_lines_calculation_currency_fkey
        FOREIGN KEY (organization_id, project_id, pricing_calculation_id, currency)
        REFERENCES recoveries.pricing_calculations(organization_id, project_id, id, currency)
        ON DELETE RESTRICT;

CREATE TABLE recoveries.fx_conversions (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    source_currency text NOT NULL CHECK (source_currency ~ '^[A-Z]{3}$'),
    target_currency text NOT NULL CHECK (target_currency ~ '^[A-Z]{3}$'),
    rate numeric(38, 18) NOT NULL CHECK (rate > 0),
    source text NOT NULL CHECK (btrim(source) <> ''),
    observed_at timestamptz NOT NULL,
    evidence_id uuid NOT NULL,
    conversion_rule_version text NOT NULL CHECK (btrim(conversion_rule_version) <> ''),
    canonical_sha256 text NOT NULL CHECK (canonical_sha256 ~ '^[a-f0-9]{64}$'),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES recoveries.projects(organization_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, project_id, evidence_id)
        REFERENCES recoveries.evidence(organization_id, project_id, id) ON DELETE RESTRICT,
    CHECK (source_currency <> target_currency)
);

COMMIT;
