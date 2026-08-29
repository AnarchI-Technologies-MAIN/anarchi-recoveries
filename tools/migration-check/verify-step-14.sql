\set ON_ERROR_STOP on

BEGIN;

INSERT INTO recoveries.organizations (id, legal_name)
VALUES ('00000000-0000-4000-8000-000000001401', 'Step 14 Proof');
INSERT INTO recoveries.users (id, display_name)
VALUES ('00000000-0000-4000-8000-000000001402', 'Baseline Reviewer');
INSERT INTO recoveries.external_identities (id, user_id, external_iss, external_sub)
VALUES (
    '00000000-0000-4000-8000-000000001403',
    '00000000-0000-4000-8000-000000001402',
    'http://127.0.0.1:58080', 'step-14-reviewer'
);
INSERT INTO recoveries.organization_memberships (
    organization_id, user_id, external_identity_id, role, status
) VALUES (
    '00000000-0000-4000-8000-000000001401',
    '00000000-0000-4000-8000-000000001402',
    '00000000-0000-4000-8000-000000001403', 'REVIEWER', 'ACTIVE'
);
INSERT INTO recoveries.projects (organization_id, id, project_number, name, timezone, currency)
VALUES (
    '00000000-0000-4000-8000-000000001401',
    '00000000-0000-4000-8000-000000001404',
    'STEP-14', 'Baseline Compiler Proof', 'UTC', 'USD'
);
INSERT INTO recoveries.evidence (
    organization_id, project_id, id, source_system, source_version,
    source_observed_at, object_uri, original_filename, mime_type, size_bytes, sha256
) VALUES (
    '00000000-0000-4000-8000-000000001401',
    '00000000-0000-4000-8000-000000001404',
    '00000000-0000-4000-8000-000000001405',
    'proof', '1', '2026-08-29T00:00:00Z',
    's3://recoveries-proof/org/00000000-0000-4000-8000-000000001401/project/00000000-0000-4000-8000-000000001404/evidence/00000000-0000-4000-8000-000000001405/ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658/source.bin',
    'source.bin', 'application/octet-stream', 29,
    'ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658'
);
INSERT INTO recoveries.facts (
    organization_id, project_id, id, fact_type, subject, value, unit,
    source_evidence_id, source_location, extraction_method,
    model_or_parser_version, candidate_confidence, verification_status,
    verified_by, verified_at
) VALUES (
    '00000000-0000-4000-8000-000000001401',
    '00000000-0000-4000-8000-000000001404',
    '00000000-0000-4000-8000-000000001406',
    'DRAWING_QUANTITY', 'panel P1', '{"quantity":"12.0000000000"}', 'EA',
    '00000000-0000-4000-8000-000000001405', 'page=2,bbox=10,20,30,40',
    'MODEL', 'proof-model@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    0.87500, 'VERIFIED', '00000000-0000-4000-8000-000000001402',
    '2026-08-29T00:00:01Z'
);
INSERT INTO recoveries.contract_baselines (
    organization_id, project_id, id, version, status
) VALUES (
    '00000000-0000-4000-8000-000000001401',
    '00000000-0000-4000-8000-000000001404',
    '00000000-0000-4000-8000-000000001407', 1, 'DRAFT'
);
INSERT INTO recoveries.baseline_evidence (
    organization_id, project_id, baseline_id, evidence_id, purpose
) VALUES (
    '00000000-0000-4000-8000-000000001401',
    '00000000-0000-4000-8000-000000001404',
    '00000000-0000-4000-8000-000000001407',
    '00000000-0000-4000-8000-000000001405', 'authoritative contract package'
);
INSERT INTO recoveries.baseline_facts (
    organization_id, project_id, baseline_id, fact_id, purpose
) VALUES (
    '00000000-0000-4000-8000-000000001401',
    '00000000-0000-4000-8000-000000001404',
    '00000000-0000-4000-8000-000000001407',
    '00000000-0000-4000-8000-000000001406', 'reviewed scope quantity'
);

SET LOCAL ROLE recoveries_runtime_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001401', true);
SELECT set_config('anarchi.current_user_id', '00000000-0000-4000-8000-000000001402', true);
SELECT recoveries.activate_reviewed_baseline(
    '00000000-0000-4000-8000-000000001401',
    '00000000-0000-4000-8000-000000001404',
    '00000000-0000-4000-8000-000000001407',
    '2026-08-29T00:00:02Z',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    '00000000-0000-4000-8000-000000001408', '2026-08-29T00:00:02Z', null,
    '00000000-0000-4000-8000-000000001409', 'step-14-baseline-1'
);

DO $runtime_bypass_proof$
BEGIN
    BEGIN
        UPDATE recoveries.contract_baselines SET canonical_sha256 = repeat('c', 64)
        WHERE organization_id = '00000000-0000-4000-8000-000000001401'
          AND id = '00000000-0000-4000-8000-000000001407';
        RAISE EXCEPTION 'runtime directly mutated compiled baseline';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END
$runtime_bypass_proof$;

RESET ROLE;
SET LOCAL ROLE recoveries_migration_role;
SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000001401', true);

DO $immutability_proof$
BEGIN
    BEGIN
        UPDATE recoveries.contract_baselines SET canonical_sha256 = repeat('c', 64)
        WHERE organization_id = '00000000-0000-4000-8000-000000001401'
          AND id = '00000000-0000-4000-8000-000000001407';
        RAISE EXCEPTION 'compiled baseline was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        DELETE FROM recoveries.baseline_facts
        WHERE organization_id = '00000000-0000-4000-8000-000000001401'
          AND baseline_id = '00000000-0000-4000-8000-000000001407';
        RAISE EXCEPTION 'compiled baseline fact link was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
END
$immutability_proof$;

RESET ROLE;

DO $result_proof$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.contract_baselines
        WHERE organization_id = '00000000-0000-4000-8000-000000001401'
          AND id = '00000000-0000-4000-8000-000000001407'
          AND status = 'ACTIVE'
          AND compiled_by = '00000000-0000-4000-8000-000000001402'
    ) OR NOT EXISTS (
        SELECT 1 FROM recoveries.transactional_outbox
        WHERE organization_id = '00000000-0000-4000-8000-000000001401'
          AND event_id = '00000000-0000-4000-8000-000000001408'
          AND subject = 'baseline.activated.v1'
    ) THEN
        RAISE EXCEPTION 'baseline activation or event missing';
    END IF;
END
$result_proof$;

SELECT 'reviewed_baseline_activation' AS proof, 'PASS' AS result;
SELECT 'compiled_baseline_immutable' AS proof, 'PASS' AS result;
SELECT 'compiled_links_immutable' AS proof, 'PASS' AS result;
SELECT 'runtime_direct_update_denied' AS proof, 'PASS' AS result;
SELECT 'baseline_activation_event_atomic' AS proof, 'PASS' AS result;

ROLLBACK;
