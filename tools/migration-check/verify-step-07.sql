\set ON_ERROR_STOP on

BEGIN;

DO $proof$
DECLARE
    org_id constant uuid := '00000000-0000-4000-8000-000000000701';
    project_id constant uuid := '00000000-0000-4000-8000-000000000702';
    evidence_id constant uuid := '00000000-0000-4000-8000-000000000703';
    baseline_id constant uuid := '00000000-0000-4000-8000-000000000704';
    scope_id constant uuid := '00000000-0000-4000-8000-000000000705';
    opportunity_id constant uuid := '00000000-0000-4000-8000-000000000706';
    pricing_id constant uuid := '00000000-0000-4000-8000-000000000707';
BEGIN
    INSERT INTO recoveries.organizations (id, legal_name)
    VALUES (org_id, 'Step 07 Proof Organization');

    INSERT INTO recoveries.projects (id, organization_id, project_number, name, timezone, currency)
    VALUES (project_id, org_id, 'STEP-07', 'Step 07 Proof Project', 'America/Chicago', 'USD');

    INSERT INTO recoveries.evidence (
        organization_id, project_id, id, source_system, source_version,
        source_observed_at, object_uri, original_filename, mime_type, size_bytes, sha256
    ) VALUES (
        org_id, project_id, evidence_id, 'PROOF', 'v1',
        '2026-08-29T00:00:00Z',
        's3://proof/org/00000000-0000-4000-8000-000000000701/project/00000000-0000-4000-8000-000000000702/evidence/00000000-0000-4000-8000-000000000703/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/proof.txt',
        'proof.txt', 'text/plain', 1,
        repeat('a', 64)
    );

    INSERT INTO recoveries.contract_baselines (
        organization_id, project_id, id, version, status, compiled_at, canonical_sha256
    ) VALUES (
        org_id, project_id, baseline_id, 1, 'ACTIVE',
        '2026-08-29T00:00:00Z', repeat('b', 64)
    );

    BEGIN
        INSERT INTO recoveries.contract_baselines (
            organization_id, project_id, version, status, compiled_at, canonical_sha256
        ) VALUES (
            org_id, project_id, 2, 'ACTIVE',
            '2026-08-29T00:00:00Z', repeat('c', 64)
        );
        RAISE EXCEPTION 'active baseline uniqueness did not reject a second ACTIVE row';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;

    INSERT INTO recoveries.scope_items (organization_id, project_id, id, stable_key)
    VALUES (org_id, project_id, scope_id, 'proof.scope');

    INSERT INTO recoveries.scope_item_versions (
        organization_id, project_id, scope_item_id,
        valid_from_baseline_version, valid_to_baseline_version,
        quantity, unit, description, source_evidence_id
    ) VALUES (
        org_id, project_id, scope_id, 1, 3,
        1.0000000000, 'EA', 'Initial proof range', evidence_id
    );

    BEGIN
        INSERT INTO recoveries.scope_item_versions (
            organization_id, project_id, scope_item_id,
            valid_from_baseline_version, valid_to_baseline_version,
            quantity, unit, description, source_evidence_id
        ) VALUES (
            org_id, project_id, scope_id, 3, 4,
            2.0000000000, 'EA', 'Overlapping proof range', evidence_id
        );
        RAISE EXCEPTION 'scope exclusion constraint accepted an overlapping range';
    EXCEPTION
        WHEN exclusion_violation THEN NULL;
    END;

    INSERT INTO recoveries.scope_item_versions (
        organization_id, project_id, scope_item_id,
        valid_from_baseline_version, valid_to_baseline_version,
        quantity, unit, description, source_evidence_id
    ) VALUES (
        org_id, project_id, scope_id, 4, 5,
        2.0000000000, 'EA', 'Non-overlapping proof range', evidence_id
    );

    INSERT INTO recoveries.recovery_opportunities (
        organization_id, project_id, id, baseline_id, detection_class, status,
        domain_rule_version, pricing_rule_version, notice_rule_version,
        evaluation_time, evaluation_hash, decision
    ) VALUES (
        org_id, project_id, opportunity_id, baseline_id,
        'DRAWING_QUANTITY_DELTA', 'DETECTED', 'domain.v1', 'pricing.v1', 'notice.v1',
        '2026-08-29T00:00:00Z', repeat('d', 64), '{}'::jsonb
    );

    INSERT INTO recoveries.pricing_calculations (
        organization_id, project_id, id, opportunity_id, currency,
        raw_subtotal, total_markup, tax, total,
        pricing_rule_version, rounding_rule_version, tax_rule_version, canonical_sha256
    ) VALUES (
        org_id, project_id, pricing_id, opportunity_id, 'USD',
        0.10, 0.20, 0.00, 0.30,
        'pricing.v1', 'rounding.v1', 'tax.v1', repeat('e', 64)
    );

    BEGIN
        INSERT INTO recoveries.pricing_lines (
            organization_id, project_id, pricing_calculation_id,
            line_number, class, description, amount, currency, rule_version
        ) VALUES (
            org_id, project_id, pricing_id,
            1, 'LABOR', 'Currency mismatch', 0.10, 'EUR', 'pricing.v1'
        );
        RAISE EXCEPTION 'pricing line accepted currency different from its calculation';
    EXCEPTION
        WHEN foreign_key_violation THEN NULL;
    END;

    INSERT INTO recoveries.pricing_lines (
        organization_id, project_id, pricing_calculation_id,
        line_number, class, description, amount, currency, rule_version
    ) VALUES (
        org_id, project_id, pricing_id,
        1, 'LABOR', 'Exact decimal proof', 0.10, 'USD', 'pricing.v1'
    );

    IF (0.10::numeric(24, 2) + 0.20::numeric(24, 2)) <> 0.30::numeric(24, 2) THEN
        RAISE EXCEPTION 'exact numeric addition did not reproduce 0.30';
    END IF;

    BEGIN
        INSERT INTO recoveries.fx_conversions (
            organization_id, project_id, source_currency, target_currency, rate,
            source, observed_at, evidence_id, conversion_rule_version, canonical_sha256
        ) VALUES (
            org_id, project_id, 'USD', 'USD', 1.000000000000000000,
            'PROOF', '2026-08-29T00:00:00Z', evidence_id, 'fx.v1', repeat('f', 64)
        );
        RAISE EXCEPTION 'FX record accepted identical source and target currency';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    INSERT INTO recoveries.fx_conversions (
        organization_id, project_id, source_currency, target_currency, rate,
        source, observed_at, evidence_id, conversion_rule_version, canonical_sha256
    ) VALUES (
        org_id, project_id, 'USD', 'EUR', 0.850000000000000000,
        'PROOF', '2026-08-29T00:00:00Z', evidence_id, 'fx.v1', repeat('f', 64)
    );

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'recoveries'
          AND table_name IN ('pricing_calculations', 'pricing_lines', 'fx_conversions')
          AND data_type IN ('real', 'double precision')
    ) THEN
        RAISE EXCEPTION 'IEEE-754 column found at the Step 7 database money boundary';
    END IF;
END
$proof$;

SELECT 'active_baseline_uniqueness' AS proof, 'PASS' AS result;
SELECT 'scope_overlap_prevention' AS proof, 'PASS' AS result;
SELECT 'pricing_currency_equality' AS proof, 'PASS' AS result;
SELECT 'exact_numeric_money' AS proof, 'PASS' AS result;
SELECT 'versioned_evidence_backed_fx' AS proof, 'PASS' AS result;
SELECT 'no_ieee_754_money_columns' AS proof, 'PASS' AS result;

ROLLBACK;
