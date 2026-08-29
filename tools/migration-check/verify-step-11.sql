\set ON_ERROR_STOP on

BEGIN;

INSERT INTO recoveries.organizations (id, legal_name)
VALUES ('00000000-0000-4000-8000-000000001101', 'Step 11 Proof');

INSERT INTO recoveries.projects (
    organization_id, id, project_number, name, timezone, currency
)
VALUES (
    '00000000-0000-4000-8000-000000001101',
    '00000000-0000-4000-8000-000000001102',
    'STEP-11', 'Evidence Integrity Proof', 'UTC', 'USD'
);

INSERT INTO recoveries.evidence (
    organization_id, project_id, id, source_system, source_version,
    source_observed_at, object_uri, original_filename, mime_type,
    size_bytes, sha256
) VALUES (
    '00000000-0000-4000-8000-000000001101',
    '00000000-0000-4000-8000-000000001102',
    '00000000-0000-4000-8000-000000001103',
    'local-proof', '1', '2026-08-29T00:00:00Z',
    's3://recoveries-proof/org/00000000-0000-4000-8000-000000001101/project/00000000-0000-4000-8000-000000001102/evidence/00000000-0000-4000-8000-000000001103/ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658/source.bin',
    'source.bin', 'application/octet-stream', 29,
    'ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658'
);

DO $proof$
BEGIN
    BEGIN
        INSERT INTO recoveries.evidence (
            organization_id, project_id, id, source_system, source_version,
            source_observed_at, object_uri, original_filename, mime_type,
            size_bytes, sha256
        ) VALUES (
            '00000000-0000-4000-8000-000000001101', '00000000-0000-4000-8000-000000001102',
            '00000000-0000-4000-8000-000000001104', 'local-proof', '1', '2026-08-29T00:00:00Z',
            's3://recoveries-proof/org/00000000-0000-4000-8000-000000001101/project/00000000-0000-4000-8000-000000001102/evidence/00000000-0000-4000-8000-000000001104/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/source.bin',
            'source.bin', 'application/octet-stream', 29,
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        );
        RAISE EXCEPTION 'mismatched object identity was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO recoveries.evidence (
            organization_id, project_id, id, source_system, source_version,
            source_observed_at, object_uri, original_filename, mime_type,
            size_bytes, sha256
        ) VALUES (
            '00000000-0000-4000-8000-000000001101', '00000000-0000-4000-8000-000000001102',
            '00000000-0000-4000-8000-000000001105', 'local-proof', '1', '2026-08-29T00:00:00Z',
            's3://recoveries-proof/irrelevant', '../source.bin', 'application/octet-stream', 29,
            'ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658'
        );
        RAISE EXCEPTION 'unsafe filename was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END
$proof$;

SELECT 'evidence_object_identity_binding' AS proof, 'PASS' AS result;
SELECT 'unsafe_filename_rejected' AS proof, 'PASS' AS result;

ROLLBACK;
