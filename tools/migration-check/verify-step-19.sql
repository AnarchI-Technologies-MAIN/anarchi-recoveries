\set ON_ERROR_STOP on

BEGIN;

INSERT INTO recoveries.organizations (id, legal_name)
VALUES ('00000000-0000-4000-8000-000000001901', 'Step 19 Proof');
INSERT INTO recoveries.projects (
    organization_id, id, project_number, name, timezone, currency
) VALUES (
    '00000000-0000-4000-8000-000000001901',
    '00000000-0000-4000-8000-000000001902',
    'STEP-19', 'Payment Billing Proof', 'UTC', 'USD'
);
INSERT INTO recoveries.contract_baselines (
    organization_id, project_id, id, version, status, compiled_at,
    canonical_sha256
) VALUES (
    '00000000-0000-4000-8000-000000001901',
    '00000000-0000-4000-8000-000000001902',
    '00000000-0000-4000-8000-000000001903', 1, 'ACTIVE',
    '2026-08-29T00:00:00Z', repeat('a', 64)
);
INSERT INTO recoveries.recovery_opportunities (
    organization_id, project_id, id, baseline_id, detection_class, status,
    domain_rule_version, pricing_rule_version, notice_rule_version,
    evaluation_time, evaluation_hash, decision
) VALUES (
    '00000000-0000-4000-8000-000000001901',
    '00000000-0000-4000-8000-000000001902',
    '00000000-0000-4000-8000-000000001904',
    '00000000-0000-4000-8000-000000001903', 'DRAWING_QUANTITY_DELTA',
    'DETECTED', 'domain.v1', 'pricing.v1', 'notice.v1',
    '2026-08-29T00:00:00Z', repeat('b', 64), '{}'::jsonb
);
INSERT INTO recoveries.recovery_opportunities (
    organization_id, project_id, id, baseline_id, detection_class, status,
    domain_rule_version, pricing_rule_version, notice_rule_version,
    evaluation_time, evaluation_hash, decision
) VALUES (
    '00000000-0000-4000-8000-000000001901',
    '00000000-0000-4000-8000-000000001902',
    '00000000-0000-4000-8000-000000001914',
    '00000000-0000-4000-8000-000000001903', 'DRAWING_QUANTITY_DELTA',
    'DETECTED', 'domain.v1', 'pricing.v1', 'notice.v1',
    '2026-08-29T00:00:00Z', repeat('c', 64), '{}'::jsonb
);

SET LOCAL ROLE recoveries_billing_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001901', true);

SELECT recoveries.persist_observed_payment(
    '00000000-0000-4000-8000-000000001901',
    '00000000-0000-4000-8000-000000001902',
    '00000000-0000-4000-8000-000000001905', 'quickbooks-online', 'QBO-PAY-1',
    '2026-08-29T00:00:01Z', 5000.00, 'USD', '{}'::jsonb,
    '00000000-0000-4000-8000-000000001906', '2026-08-29T00:00:01Z', NULL,
    '00000000-0000-4000-8000-000000001907', 'step-19-payment-1'
);

SELECT recoveries.persist_observed_payment(
    '00000000-0000-4000-8000-000000001901',
    '00000000-0000-4000-8000-000000001902',
    '00000000-0000-4000-8000-000000001905', 'quickbooks-online', 'QBO-PAY-1',
    '2026-08-29T00:00:01Z', 5000.00, 'USD', '{}'::jsonb,
    '00000000-0000-4000-8000-000000001906', '2026-08-29T00:00:01Z', NULL,
    '00000000-0000-4000-8000-000000001907', 'step-19-payment-1'
);

WITH result AS (
    SELECT jsonb_build_object(
        'attribution_rule_version', 'SUCCESS_FEE_V1',
        'currency', 'USD',
        'supported_value', '10000.00',
        'prior_recognized_supported_value', '0.00',
        'attributable_supported_uplift', '10000.00',
        'attributable_cash_received', '4000.00',
        'success_fee_rate_percent', '15.00',
        'success_fee_base', '4000.00',
        'success_fee', '600.00',
        'money_scale', 2,
        'rounding_mode', 'MIDPOINT_AWAY_FROM_ZERO'
    ) AS value
), record AS (
    SELECT jsonb_build_object(
        'canonicalization', 'ANARCHI-JCS-COMPATIBLE-V1',
        'result', value,
        'attribution_hash', encode(public.digest(convert_to(value::text, 'UTF8'), 'sha256'), 'hex')
    ) AS value
    FROM result
)
SELECT recoveries.persist_attribution_and_fee(
    '00000000-0000-4000-8000-000000001901',
    '00000000-0000-4000-8000-000000001902',
    '00000000-0000-4000-8000-000000001905',
    '00000000-0000-4000-8000-000000001904',
    '00000000-0000-4000-8000-000000001908', 4000.00, 'USD',
    value ->> 'attribution_hash', (value -> 'result')::text, value,
    '00000000-0000-4000-8000-000000001909',
    '00000000-0000-4000-8000-000000001910',
    '00000000-0000-4000-8000-000000001911',
    '00000000-0000-4000-8000-000000001912',
    '2026-08-29T00:00:02Z', NULL,
    '00000000-0000-4000-8000-000000001907',
    'step-19-attribution-1', 'step-19-fee-1'
)
FROM record;

SET CONSTRAINTS recoveries.allocation_ceiling_trigger IMMEDIATE;

RESET ROLE;
SET LOCAL ROLE recoveries_runtime_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001901', true);

DO $runtime_authority_proof$
DECLARE
    rejected boolean := false;
BEGIN
    BEGIN
        INSERT INTO recoveries.payments (
            organization_id, project_id, source_system, observed_at, amount, currency
        ) VALUES (
            '00000000-0000-4000-8000-000000001901',
            '00000000-0000-4000-8000-000000001902', 'forged',
            '2026-08-29T00:00:03Z', 1.00, 'USD'
        );
    EXCEPTION WHEN insufficient_privilege THEN
        rejected := true;
    END;
    IF NOT rejected THEN
        RAISE EXCEPTION 'runtime directly inserted a payment';
    END IF;
END
$runtime_authority_proof$;

RESET ROLE;
SET LOCAL ROLE recoveries_migration_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001901', true);

DO $allocation_ceiling_proof$
DECLARE
    rejected boolean := false;
BEGIN
    BEGIN
        INSERT INTO recoveries.recovery_payment_allocations (
            organization_id, project_id, id, payment_id, opportunity_id,
            allocated_amount, currency
        ) VALUES (
            '00000000-0000-4000-8000-000000001901',
            '00000000-0000-4000-8000-000000001902',
            '00000000-0000-4000-8000-000000001913',
            '00000000-0000-4000-8000-000000001905',
            '00000000-0000-4000-8000-000000001914', 2000.00, 'USD'
        );
        SET CONSTRAINTS recoveries.allocation_ceiling_trigger IMMEDIATE;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN
        RAISE EXCEPTION 'allocation ceiling violation was accepted';
    END IF;
END
$allocation_ceiling_proof$;

DO $payment_reduction_proof$
DECLARE
    rejected boolean := false;
BEGIN
    BEGIN
        UPDATE recoveries.payments
        SET amount = 3000.00
        WHERE organization_id = '00000000-0000-4000-8000-000000001901'
          AND id = '00000000-0000-4000-8000-000000001905';
        SET CONSTRAINTS recoveries.payment_amount_ceiling_trigger IMMEDIATE;
    EXCEPTION WHEN check_violation THEN
        rejected := true;
    END;
    IF NOT rejected THEN
        RAISE EXCEPTION 'payment reduction below allocated amount was accepted';
    END IF;
END
$payment_reduction_proof$;

DO $result_proof$
DECLARE
    payment_count integer;
    allocation_count integer;
    accrual_count integer;
    payment_events integer;
    attribution_events integer;
    fee_events integer;
BEGIN
    SELECT count(*) INTO payment_count FROM recoveries.payments
    WHERE organization_id = '00000000-0000-4000-8000-000000001901';
    SELECT count(*) INTO allocation_count FROM recoveries.recovery_payment_allocations
    WHERE organization_id = '00000000-0000-4000-8000-000000001901';
    SELECT count(*) INTO accrual_count FROM recoveries.success_fee_accruals
    WHERE organization_id = '00000000-0000-4000-8000-000000001901';
    SELECT count(*) INTO payment_events FROM recoveries.transactional_outbox
    WHERE organization_id = '00000000-0000-4000-8000-000000001901'
      AND subject = 'payment.observed.v1';
    SELECT count(*) INTO attribution_events FROM recoveries.transactional_outbox
    WHERE organization_id = '00000000-0000-4000-8000-000000001901'
      AND subject = 'attribution.reconciled.v1';
    SELECT count(*) INTO fee_events FROM recoveries.transactional_outbox
    WHERE organization_id = '00000000-0000-4000-8000-000000001901'
      AND subject = 'billing.success_fee.accrued.v1';
    IF payment_count <> 1 OR allocation_count <> 1 OR accrual_count <> 1
       OR payment_events <> 1 OR attribution_events <> 1 OR fee_events <> 1 THEN
        RAISE EXCEPTION 'billing persistence counts are wrong: %, %, %, %, %, %',
            payment_count, allocation_count, accrual_count,
            payment_events, attribution_events, fee_events;
    END IF;
    IF EXISTS (
        SELECT 1 FROM recoveries.success_fee_accruals
        WHERE organization_id = '00000000-0000-4000-8000-000000001901'
          AND (fee_amount <> 600.00 OR fee_base <> 4000.00 OR currency <> 'USD')
    ) OR EXISTS (
        SELECT 1 FROM recoveries.transactional_outbox
        WHERE organization_id = '00000000-0000-4000-8000-000000001901'
          AND envelope_sha256 <> encode(public.digest(convert_to(envelope::text, 'UTF8'), 'sha256'), 'hex')
    ) THEN
        RAISE EXCEPTION 'fee or event hash is not deterministic';
    END IF;
END
$result_proof$;

SELECT 'payment_observed_atomic' AS proof, 'PASS' AS result;
SELECT 'attribution_allocation_and_fee_atomic' AS proof, 'PASS' AS result;
SELECT 'payment_event_replay_idempotent' AS proof, 'PASS' AS result;
SELECT 'runtime_payment_write_denied' AS proof, 'PASS' AS result;
SELECT 'allocation_ceiling_deferred_trigger' AS proof, 'PASS' AS result;
SELECT 'payment_reduction_revalidated' AS proof, 'PASS' AS result;
SELECT 'success_fee_exact_partial_cash' AS proof, 'PASS' AS result;

ROLLBACK;
