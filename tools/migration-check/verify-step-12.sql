\set ON_ERROR_STOP on

BEGIN;

INSERT INTO recoveries.organizations (id, legal_name)
VALUES ('00000000-0000-4000-8000-000000001201', 'Step 12 Proof');
INSERT INTO recoveries.projects (organization_id, id, project_number, name, timezone, currency)
VALUES (
    '00000000-0000-4000-8000-000000001201',
    '00000000-0000-4000-8000-000000001202',
    'STEP-12', 'Ingestion Transaction Proof', 'UTC', 'USD'
);

SET LOCAL ROLE recoveries_runtime_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001201', true);

SELECT recoveries.persist_ingested_evidence(
    '00000000-0000-4000-8000-000000001201',
    '00000000-0000-4000-8000-000000001202',
    '00000000-0000-4000-8000-000000001203',
    'file-upload', 'external-1', '1', '2026-08-29T00:00:00Z',
    's3://recoveries-proof/org/00000000-0000-4000-8000-000000001201/project/00000000-0000-4000-8000-000000001202/evidence/00000000-0000-4000-8000-000000001203/ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658/source.bin',
    'source.bin', 'application/octet-stream', 29,
    'ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658',
    '{"proof":true}',
    '00000000-0000-4000-8000-000000001204', '2026-08-29T00:00:01Z', null,
    '00000000-0000-4000-8000-000000001205', 'step-12-success'
);

DO $proof$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.evidence
        WHERE organization_id = '00000000-0000-4000-8000-000000001201'
          AND id = '00000000-0000-4000-8000-000000001203'
    ) OR NOT EXISTS (
        SELECT 1 FROM recoveries.transactional_outbox
        WHERE organization_id = '00000000-0000-4000-8000-000000001201'
          AND event_id = '00000000-0000-4000-8000-000000001204'
          AND subject = 'evidence.persisted.v1'
          AND envelope->>'aggregate_id' = '00000000-0000-4000-8000-000000001203'
    ) THEN
        RAISE EXCEPTION 'evidence and outbox were not persisted atomically';
    END IF;

    BEGIN
        PERFORM recoveries.persist_ingested_evidence(
            '00000000-0000-4000-8000-000000001201',
            '00000000-0000-4000-8000-000000001202',
            '00000000-0000-4000-8000-000000001206',
            'file-upload', 'external-2', '1', '2026-08-29T00:00:00Z',
            's3://recoveries-proof/org/00000000-0000-4000-8000-000000001201/project/00000000-0000-4000-8000-000000001202/evidence/00000000-0000-4000-8000-000000001206/ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658/source.bin',
            'source.bin', 'application/octet-stream', 29,
            'ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658',
            '{}'::jsonb,
            '00000000-0000-4000-8000-000000001207', '2026-08-29T00:00:02Z', null,
            '00000000-0000-4000-8000-000000001205', 'step-12-success'
        );
        RAISE EXCEPTION 'duplicate idempotency key was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    IF EXISTS (
        SELECT 1 FROM recoveries.evidence
        WHERE organization_id = '00000000-0000-4000-8000-000000001201'
          AND id = '00000000-0000-4000-8000-000000001206'
    ) THEN
        RAISE EXCEPTION 'failed outbox insert left partial evidence state';
    END IF;
END
$proof$;

SELECT 'evidence_and_outbox_atomic' AS proof, 'PASS' AS result;
SELECT 'outbox_failure_rolls_back_evidence' AS proof, 'PASS' AS result;

ROLLBACK;
