\set ON_ERROR_STOP on

BEGIN;

INSERT INTO recoveries.organizations (id, legal_name)
VALUES ('00000000-0000-4000-8000-000000001501', 'Step 15 Proof');
INSERT INTO recoveries.projects (
    organization_id, id, project_number, name, timezone, currency
) VALUES (
    '00000000-0000-4000-8000-000000001501',
    '00000000-0000-4000-8000-000000001502',
    'STEP-15', 'Evaluation Persistence Proof', 'UTC', 'USD'
);
INSERT INTO recoveries.contract_baselines (
    organization_id, project_id, id, version, status, compiled_at,
    compiled_by, canonical_sha256
) VALUES (
    '00000000-0000-4000-8000-000000001501',
    '00000000-0000-4000-8000-000000001502',
    '00000000-0000-4000-8000-000000001503', 1, 'ACTIVE',
    '2026-08-29T00:00:00Z', NULL,
    repeat('a', 64)
);

SET LOCAL ROLE recoveries_evaluation_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001501', true);

WITH decision AS (
    SELECT '{"decision":"NO_OPPORTUNITY","result":"NO_VERIFIED_DRAWING_DELTA"}'::jsonb AS value
), record AS (
    SELECT jsonb_build_object(
        'canonicalization', 'ANARCHI-JCS-COMPATIBLE-V1',
        'decision', value,
        'evaluation_hash', encode(public.digest(convert_to(value::text, 'UTF8'), 'sha256'), 'hex')
    ) AS value
    FROM decision
)
SELECT recoveries.persist_recovery_evaluation(
    '00000000-0000-4000-8000-000000001501',
    '00000000-0000-4000-8000-000000001502',
    '00000000-0000-4000-8000-000000001503',
    '00000000-0000-4000-8000-000000001504',
    NULL, NULL, '2026-08-29T00:00:02Z',
    value ->> 'evaluation_hash',
    (value -> 'decision')::text,
    value,
    '00000000-0000-4000-8000-000000001505',
    '2026-08-29T00:00:02Z', NULL,
    '00000000-0000-4000-8000-000000001506',
    'step-15-no-opportunity'
)
FROM record;

WITH decision AS (
    SELECT '{"decision":"NO_OPPORTUNITY","result":"NO_VERIFIED_DRAWING_DELTA"}'::jsonb AS value
), record AS (
    SELECT jsonb_build_object(
        'canonicalization', 'ANARCHI-JCS-COMPATIBLE-V1',
        'decision', value,
        'evaluation_hash', encode(public.digest(convert_to(value::text, 'UTF8'), 'sha256'), 'hex')
    ) AS value
    FROM decision
)
SELECT recoveries.persist_recovery_evaluation(
    '00000000-0000-4000-8000-000000001501',
    '00000000-0000-4000-8000-000000001502',
    '00000000-0000-4000-8000-000000001503',
    '00000000-0000-4000-8000-000000001504',
    NULL, NULL, '2026-08-29T00:00:02Z',
    value ->> 'evaluation_hash',
    (value -> 'decision')::text,
    value,
    '00000000-0000-4000-8000-000000001505',
    '2026-08-29T00:00:02Z', NULL,
    '00000000-0000-4000-8000-000000001506',
    'step-15-no-opportunity'
)
FROM record;

WITH decision AS (
    SELECT jsonb_build_object(
        'decision', 'OPPORTUNITY',
        'result', jsonb_build_object(
            'organization_id', '00000000-0000-4000-8000-000000001501',
            'project_id', '00000000-0000-4000-8000-000000001502',
            'baseline_id', '00000000-0000-4000-8000-000000001503',
            'evaluation_time', '2026-08-29T00:00:03Z',
            'domain_rule_version', 'domain.v1',
            'notice_rule_version', 'notice.v1',
            'passed_conditions', jsonb_build_array('quantity_delta_positive'),
            'failed_conditions', '[]'::jsonb,
            'missing_conditions', '[]'::jsonb,
            'facts_used', '[]'::jsonb,
            'pricing', jsonb_build_object(
                'currency', 'USD', 'lines', '[]'::jsonb,
                'raw_subtotal', '0.00', 'total_markup', '0.00',
                'tax', '0.00', 'total', '0.00',
                'pricing_rule_version', 'pricing.v1'
            )
        )
    ) AS value
), record AS (
    SELECT jsonb_build_object(
        'canonicalization', 'ANARCHI-JCS-COMPATIBLE-V1',
        'decision', value,
        'evaluation_hash', encode(public.digest(convert_to(value::text, 'UTF8'), 'sha256'), 'hex')
    ) AS value
    FROM decision
)
SELECT recoveries.persist_recovery_evaluation(
    '00000000-0000-4000-8000-000000001501',
    '00000000-0000-4000-8000-000000001502',
    '00000000-0000-4000-8000-000000001503',
    '00000000-0000-4000-8000-000000001507',
    '00000000-0000-4000-8000-000000001508',
    'DRAWING_QUANTITY_DELTA', '2026-08-29T00:00:03Z',
    value ->> 'evaluation_hash',
    (value -> 'decision')::text,
    value,
    '00000000-0000-4000-8000-000000001509',
    '2026-08-29T00:00:03Z', NULL,
    '00000000-0000-4000-8000-000000001506',
    'step-15-opportunity'
)
FROM record;

RESET ROLE;
SET LOCAL ROLE recoveries_runtime_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001501', true);

DO $runtime_authority_proof$
BEGIN
    BEGIN
        INSERT INTO recoveries.recovery_opportunities (
            organization_id, project_id, baseline_id, detection_class, status,
            domain_rule_version, pricing_rule_version, notice_rule_version,
            evaluation_time, evaluation_hash, decision
        ) VALUES (
            '00000000-0000-4000-8000-000000001501',
            '00000000-0000-4000-8000-000000001502',
            '00000000-0000-4000-8000-000000001503',
            'DRAWING_QUANTITY_DELTA', 'DETECTED', 'forged', 'forged', 'forged',
            '2026-08-29T00:00:04Z', repeat('f', 64), '{}'::jsonb
        );
        RAISE EXCEPTION 'runtime directly inserted an opportunity';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END
$runtime_authority_proof$;

RESET ROLE;
SET LOCAL ROLE recoveries_migration_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001501', true);

DO $result_proof$
DECLARE
    audit_count integer;
    outbox_count integer;
    opportunity_count integer;
BEGIN
    SELECT count(*) INTO audit_count
    FROM recoveries.audit_events
    WHERE organization_id = '00000000-0000-4000-8000-000000001501'
      AND event_type = 'recovery.evaluated';
    SELECT count(*) INTO outbox_count
    FROM recoveries.transactional_outbox
    WHERE organization_id = '00000000-0000-4000-8000-000000001501'
      AND subject = 'recovery.evaluated.v1';
    SELECT count(*) INTO opportunity_count
    FROM recoveries.recovery_opportunities
    WHERE organization_id = '00000000-0000-4000-8000-000000001501';
    IF audit_count <> 2 OR outbox_count <> 2 OR opportunity_count <> 1 THEN
        RAISE EXCEPTION 'evaluation persistence counts are wrong: %, %, %',
            audit_count, outbox_count, opportunity_count;
    END IF;
    IF EXISTS (
        SELECT 1 FROM recoveries.audit_events
        WHERE organization_id = '00000000-0000-4000-8000-000000001501'
          AND (details ->> 'evaluation_hash') !~ '^[a-f0-9]{64}$'
    ) OR EXISTS (
        SELECT 1 FROM recoveries.transactional_outbox
        WHERE organization_id = '00000000-0000-4000-8000-000000001501'
          AND envelope_sha256 <> encode(public.digest(convert_to(envelope::text, 'UTF8'), 'sha256'), 'hex')
    ) THEN
        RAISE EXCEPTION 'evaluation receipts are not hash-consistent';
    END IF;
END
$result_proof$;

DO $fail_closed_proof$
DECLARE
    rejected boolean := false;
BEGIN
    BEGIN
        PERFORM recoveries.persist_recovery_evaluation(
            '00000000-0000-4000-8000-000000001501',
            '00000000-0000-4000-8000-000000001502',
            '00000000-0000-4000-8000-000000001503',
            '00000000-0000-4000-8000-000000001510',
            NULL, NULL, '2026-08-29T00:00:05Z', repeat('0', 64),
            '{"decision":"NO_OPPORTUNITY","result":"NO_VERIFIED_DRAWING_DELTA"}',
            jsonb_build_object(
                'canonicalization', 'ANARCHI-JCS-COMPATIBLE-V1',
                'decision', '{"decision":"NO_OPPORTUNITY","result":"NO_VERIFIED_DRAWING_DELTA"}'::jsonb,
                'evaluation_hash', repeat('0', 64)
            ),
            '00000000-0000-4000-8000-000000001511',
            '2026-08-29T00:00:05Z', NULL,
            '00000000-0000-4000-8000-000000001506', 'step-15-invalid-hash'
        );
    EXCEPTION WHEN OTHERS THEN
        rejected := true;
    END;
    IF NOT rejected THEN
        RAISE EXCEPTION 'invalid evaluation hash was accepted';
    END IF;
END
$fail_closed_proof$;

SELECT 'no_opportunity_audit_receipt' AS proof, 'PASS' AS result;
SELECT 'opportunity_domain_row_and_audit_receipt' AS proof, 'PASS' AS result;
SELECT 'evaluation_outbox_hash_replay' AS proof, 'PASS' AS result;
SELECT 'runtime_direct_opportunity_denied' AS proof, 'PASS' AS result;
SELECT 'invalid_evaluation_hash_fails_closed' AS proof, 'PASS' AS result;

ROLLBACK;
