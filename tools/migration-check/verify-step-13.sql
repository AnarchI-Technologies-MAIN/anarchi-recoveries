\set ON_ERROR_STOP on

BEGIN;

INSERT INTO recoveries.organizations (id, legal_name)
VALUES ('00000000-0000-4000-8000-000000001301', 'Step 13 Proof');
INSERT INTO recoveries.projects (organization_id, id, project_number, name, timezone, currency)
VALUES (
    '00000000-0000-4000-8000-000000001301',
    '00000000-0000-4000-8000-000000001302',
    'STEP-13', 'Candidate Extraction Proof', 'UTC', 'USD'
);
INSERT INTO recoveries.evidence (
    organization_id, project_id, id, source_system, source_version,
    source_observed_at, object_uri, original_filename, mime_type, size_bytes, sha256
) VALUES (
    '00000000-0000-4000-8000-000000001301',
    '00000000-0000-4000-8000-000000001302',
    '00000000-0000-4000-8000-000000001303',
    'proof', '1', '2026-08-29T00:00:00Z',
    's3://recoveries-proof/org/00000000-0000-4000-8000-000000001301/project/00000000-0000-4000-8000-000000001302/evidence/00000000-0000-4000-8000-000000001303/ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658/source.bin',
    'source.bin', 'application/octet-stream', 29,
    'ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658'
);

SET LOCAL ROLE recoveries_extraction_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001301', true);
SELECT recoveries.persist_fact_candidate(
    '00000000-0000-4000-8000-000000001301',
    '00000000-0000-4000-8000-000000001302',
    '00000000-0000-4000-8000-000000001304',
    'DRAWING_QUANTITY', 'panel P1', '{"quantity":"12.0000000000"}',
    'EA', null,
    '00000000-0000-4000-8000-000000001303', 'page=2,bbox=10,20,30,40',
    'MODEL', 'proof-model@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    0.87500,
    '00000000-0000-4000-8000-000000001305', '2026-08-29T00:00:01Z', null,
    '00000000-0000-4000-8000-000000001306', 'step-13-candidate-1'
);

DO $authority_proof$
BEGIN
    BEGIN
        INSERT INTO recoveries.facts (
            organization_id, project_id, fact_type, subject, value,
            source_evidence_id, source_location, extraction_method,
            model_or_parser_version, verification_status
        ) VALUES (
            '00000000-0000-4000-8000-000000001301',
            '00000000-0000-4000-8000-000000001302',
            'FORGED_VERIFIED', 'forged', '{}'::jsonb,
            '00000000-0000-4000-8000-000000001303', 'forged', 'MODEL',
            'forged', 'VERIFIED'
        );
        RAISE EXCEPTION 'extraction role directly inserted a fact';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    BEGIN
        PERFORM recoveries.persist_fact_candidate(
            '00000000-0000-4000-8000-000000001399',
            '00000000-0000-4000-8000-000000001302',
            '00000000-0000-4000-8000-000000001307',
            'FORGED', 'forged', '{}'::jsonb, null, null,
            '00000000-0000-4000-8000-000000001303', 'forged', 'MODEL', 'forged',
            1.0, '00000000-0000-4000-8000-000000001308',
            '2026-08-29T00:00:02Z', null,
            '00000000-0000-4000-8000-000000001306', 'step-13-forged'
        );
        RAISE EXCEPTION 'extraction role crossed organization context';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END
$authority_proof$;

RESET ROLE;

DO $result_proof$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.facts
        WHERE organization_id = '00000000-0000-4000-8000-000000001301'
          AND id = '00000000-0000-4000-8000-000000001304'
          AND verification_status = 'CANDIDATE'
          AND verified_by IS NULL AND verified_at IS NULL
    ) THEN
        RAISE EXCEPTION 'candidate fact was not persisted as candidate-only';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.transactional_outbox
        WHERE organization_id = '00000000-0000-4000-8000-000000001301'
          AND event_id = '00000000-0000-4000-8000-000000001305'
          AND subject = 'fact.candidate.created.v1'
    ) THEN
        RAISE EXCEPTION 'candidate event was not persisted';
    END IF;
END
$result_proof$;

SELECT 'candidate_only_persistence' AS proof, 'PASS' AS result;
SELECT 'extraction_role_cannot_verify' AS proof, 'PASS' AS result;
SELECT 'extraction_cross_tenant_denied' AS proof, 'PASS' AS result;
SELECT 'candidate_event_atomic' AS proof, 'PASS' AS result;

ROLLBACK;
