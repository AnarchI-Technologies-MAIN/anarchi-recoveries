\set ON_ERROR_STOP on

BEGIN;

INSERT INTO recoveries.organizations (id, legal_name)
VALUES ('00000000-0000-4000-8000-000000001001', 'Outbox Proof Tenant');

INSERT INTO recoveries.projects (
    id, organization_id, project_number, name, timezone, currency
) VALUES (
    '00000000-0000-4000-8000-000000001002',
    '00000000-0000-4000-8000-000000001001',
    'OUTBOX-1', 'Outbox Proof Project', 'America/Chicago', 'USD'
);

SET LOCAL ROLE recoveries_runtime_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001001', true);

INSERT INTO recoveries.consumer_inbox (
    organization_id, project_id, consumer_name, event_id, subject,
    envelope_sha256, received_at, processed_at, processing_result
) VALUES (
    '00000000-0000-4000-8000-000000001001',
    '00000000-0000-4000-8000-000000001002',
    'proof-consumer', '00000000-0000-4000-8000-000000001003',
    'fact.verified.v1', repeat('a', 64),
    '2026-08-29T00:00:00Z', '2026-08-29T00:00:01Z', 'APPLIED'
);

DO $inbox_dedupe$
BEGIN
    BEGIN
        INSERT INTO recoveries.consumer_inbox (
            organization_id, project_id, consumer_name, event_id, subject,
            envelope_sha256, received_at
        ) VALUES (
            '00000000-0000-4000-8000-000000001001',
            '00000000-0000-4000-8000-000000001002',
            'proof-consumer', '00000000-0000-4000-8000-000000001003',
            'fact.verified.v1', repeat('a', 64), '2026-08-29T00:00:02Z'
        );
        RAISE EXCEPTION 'consumer inbox accepted a duplicate event';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;
END
$inbox_dedupe$;

INSERT INTO recoveries.transactional_outbox (
    organization_id, project_id, id, event_id, subject, aggregate_id,
    correlation_id, idempotency_key, occurred_at, envelope, envelope_sha256, available_at
) VALUES (
    '00000000-0000-4000-8000-000000001001',
    '00000000-0000-4000-8000-000000001002',
    '00000000-0000-4000-8000-000000001004',
    '00000000-0000-4000-8000-000000001005',
    'fact.verified.v1',
    '00000000-0000-4000-8000-000000001006',
    '00000000-0000-4000-8000-000000001007',
    'proof-success', '2026-08-29T00:00:00Z',
    jsonb_build_object(
        'schema_version', '1.0',
        'event_id', '00000000-0000-4000-8000-000000001005',
        'event_type', 'fact.verified',
        'organization_id', '00000000-0000-4000-8000-000000001001',
        'project_id', '00000000-0000-4000-8000-000000001002',
        'aggregate_id', '00000000-0000-4000-8000-000000001006',
        'occurred_at', '2026-08-29T00:00:00Z',
        'causation_id', NULL,
        'correlation_id', '00000000-0000-4000-8000-000000001007',
        'idempotency_key', 'proof-success',
        'payload', jsonb_build_object('fact_id', 'proof')
    ), repeat('b', 64), '2026-08-29T00:00:00Z'
), (
    '00000000-0000-4000-8000-000000001001',
    '00000000-0000-4000-8000-000000001002',
    '00000000-0000-4000-8000-000000001014',
    '00000000-0000-4000-8000-000000001015',
    'fact.verified.v1',
    '00000000-0000-4000-8000-000000001016',
    '00000000-0000-4000-8000-000000001017',
    'proof-dead-letter', '2026-08-29T00:00:00Z',
    jsonb_build_object(
        'schema_version', '1.0',
        'event_id', '00000000-0000-4000-8000-000000001015',
        'event_type', 'fact.verified',
        'organization_id', '00000000-0000-4000-8000-000000001001',
        'project_id', '00000000-0000-4000-8000-000000001002',
        'aggregate_id', '00000000-0000-4000-8000-000000001016',
        'occurred_at', '2026-08-29T00:00:00Z',
        'causation_id', NULL,
        'correlation_id', '00000000-0000-4000-8000-000000001017',
        'idempotency_key', 'proof-dead-letter',
        'payload', jsonb_build_object('fact_id', 'proof')
    ), repeat('c', 64), '2026-08-29T00:00:00Z'
);

RESET ROLE;
SET LOCAL ROLE recoveries_outbox_publisher_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001001', true);

DO $lease_and_cas_proof$
DECLARE
    first_claim recoveries.transactional_outbox;
    reclaimed recoveries.transactional_outbox;
    dead_claim recoveries.transactional_outbox;
    retry_claim recoveries.transactional_outbox;
    result boolean;
    failure_state text;
BEGIN
    SELECT * INTO STRICT first_claim
    FROM recoveries.claim_outbox('worker-a', 1, '2026-08-29T00:00:00Z', interval '30 seconds');

    IF first_claim.publish_attempts <> 0 THEN
        RAISE EXCEPTION 'claim incremented publish attempts before broker I/O';
    END IF;

    IF EXISTS (
        SELECT 1 FROM recoveries.claim_outbox(
            'worker-b', 1, '2026-08-29T00:00:20Z', interval '30 seconds'
        )
        WHERE id = first_claim.id
    ) THEN
        RAISE EXCEPTION 'unexpired lease was reclaimed';
    END IF;

    SELECT * INTO STRICT reclaimed
    FROM recoveries.claim_outbox('worker-b', 1, '2026-08-29T00:00:31Z', interval '30 seconds');

    IF reclaimed.id <> first_claim.id OR reclaimed.claim_token = first_claim.claim_token THEN
        RAISE EXCEPTION 'stale lease did not issue a new claim token';
    END IF;

    SELECT recoveries.mark_outbox_published(
        first_claim.organization_id, first_claim.id, first_claim.claim_token,
        '2026-08-29T00:00:32Z'
    ) INTO result;
    IF result THEN
        RAISE EXCEPTION 'stale claim token overwrote the current owner';
    END IF;

    SELECT recoveries.mark_outbox_published(
        reclaimed.organization_id, reclaimed.id, reclaimed.claim_token,
        '2026-08-29T00:00:32Z'
    ) INTO result;
    IF NOT result THEN
        RAISE EXCEPTION 'current claim token failed to publish';
    END IF;

    SELECT * INTO STRICT dead_claim
    FROM recoveries.claim_outbox('worker-a', 1, '2026-08-29T00:01:00Z', interval '30 seconds');

    SELECT recoveries.record_outbox_publish_failure(
        dead_claim.organization_id, dead_claim.id, dead_claim.claim_token,
        'broker unavailable', '2026-08-29T00:01:10Z', 2, '2026-08-29T00:01:01Z'
    ) INTO failure_state;
    IF failure_state <> 'PENDING' THEN
        RAISE EXCEPTION 'first actual failure did not schedule a retry';
    END IF;

    SELECT * INTO STRICT retry_claim
    FROM recoveries.claim_outbox('worker-b', 1, '2026-08-29T00:01:10Z', interval '30 seconds');

    SELECT recoveries.record_outbox_publish_failure(
        retry_claim.organization_id, retry_claim.id, retry_claim.claim_token,
        'broker still unavailable', '2026-08-29T00:01:20Z', 2, '2026-08-29T00:01:11Z'
    ) INTO failure_state;
    IF failure_state <> 'DEAD_LETTER' THEN
        RAISE EXCEPTION 'retry threshold did not produce explicit dead-letter state';
    END IF;

    IF (SELECT publish_attempts FROM recoveries.transactional_outbox WHERE id = reclaimed.id) <> 1
       OR (SELECT publish_attempts FROM recoveries.transactional_outbox WHERE id = retry_claim.id) <> 2 THEN
        RAISE EXCEPTION 'publish attempt count does not equal actual broker outcomes';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM recoveries.audit_events
        WHERE aggregate_id = retry_claim.id
          AND event_type = 'OUTBOX_DEAD_LETTERED'
    ) THEN
        RAISE EXCEPTION 'dead-letter transition emitted no audit event';
    END IF;
END
$lease_and_cas_proof$;

RESET ROLE;

SELECT 'durable_inbox_dedupe' AS proof, 'PASS' AS result;
SELECT 'claim_without_attempt_increment' AS proof, 'PASS' AS result;
SELECT 'stale_lease_recovery' AS proof, 'PASS' AS result;
SELECT 'stale_token_cas_rejected' AS proof, 'PASS' AS result;
SELECT 'actual_publish_attempt_accounting' AS proof, 'PASS' AS result;
SELECT 'explicit_dead_letter_with_audit' AS proof, 'PASS' AS result;

ROLLBACK;
