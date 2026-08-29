\set ON_ERROR_STOP on

DELETE FROM recoveries.transactional_outbox
WHERE organization_id = '00000000-0000-4000-8000-000000001020';
DELETE FROM recoveries.projects
WHERE organization_id = '00000000-0000-4000-8000-000000001020';
DELETE FROM recoveries.organizations
WHERE id = '00000000-0000-4000-8000-000000001020';

INSERT INTO recoveries.organizations (id, legal_name)
VALUES ('00000000-0000-4000-8000-000000001020', 'Concurrency Proof Tenant');

INSERT INTO recoveries.projects (
    id, organization_id, project_number, name, timezone, currency
) VALUES (
    '00000000-0000-4000-8000-000000001021',
    '00000000-0000-4000-8000-000000001020',
    'CONCURRENT-1', 'Concurrency Proof Project', 'America/Chicago', 'USD'
);

INSERT INTO recoveries.transactional_outbox (
    organization_id, project_id, id, event_id, subject, aggregate_id,
    correlation_id, idempotency_key, occurred_at, envelope, envelope_sha256, available_at
) VALUES
    (
        '00000000-0000-4000-8000-000000001020',
        '00000000-0000-4000-8000-000000001021',
        '00000000-0000-4000-8000-000000001022',
        '00000000-0000-4000-8000-000000001023',
        'fact.verified.v1',
        '00000000-0000-4000-8000-000000001024',
        '00000000-0000-4000-8000-000000001025',
        'concurrency-proof-1', '2026-08-29T00:00:00Z',
        jsonb_build_object(
            'schema_version', '1.0',
            'event_id', '00000000-0000-4000-8000-000000001023',
            'event_type', 'fact.verified',
            'organization_id', '00000000-0000-4000-8000-000000001020',
            'project_id', '00000000-0000-4000-8000-000000001021',
            'aggregate_id', '00000000-0000-4000-8000-000000001024',
            'occurred_at', '2026-08-29T00:00:00Z',
            'causation_id', NULL,
            'correlation_id', '00000000-0000-4000-8000-000000001025',
            'idempotency_key', 'concurrency-proof-1',
            'payload', '{}'::jsonb
        ), repeat('d', 64), '2026-08-29T00:00:00Z'
    ),
    (
        '00000000-0000-4000-8000-000000001020',
        '00000000-0000-4000-8000-000000001021',
        '00000000-0000-4000-8000-000000001032',
        '00000000-0000-4000-8000-000000001033',
        'fact.verified.v1',
        '00000000-0000-4000-8000-000000001034',
        '00000000-0000-4000-8000-000000001035',
        'concurrency-proof-2', '2026-08-29T00:00:00Z',
        jsonb_build_object(
            'schema_version', '1.0',
            'event_id', '00000000-0000-4000-8000-000000001033',
            'event_type', 'fact.verified',
            'organization_id', '00000000-0000-4000-8000-000000001020',
            'project_id', '00000000-0000-4000-8000-000000001021',
            'aggregate_id', '00000000-0000-4000-8000-000000001034',
            'occurred_at', '2026-08-29T00:00:00Z',
            'causation_id', NULL,
            'correlation_id', '00000000-0000-4000-8000-000000001035',
            'idempotency_key', 'concurrency-proof-2',
            'payload', '{}'::jsonb
        ), repeat('e', 64), '2026-08-29T00:00:00Z'
    );
