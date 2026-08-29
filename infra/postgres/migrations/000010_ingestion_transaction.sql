BEGIN;

CREATE FUNCTION recoveries.persist_ingested_evidence(
    p_organization_id uuid,
    p_project_id uuid,
    p_evidence_id uuid,
    p_source_system text,
    p_external_id text,
    p_source_version text,
    p_source_observed_at timestamptz,
    p_object_uri text,
    p_original_filename text,
    p_mime_type text,
    p_size_bytes bigint,
    p_sha256 text,
    p_metadata jsonb,
    p_event_id uuid,
    p_occurred_at timestamptz,
    p_causation_id uuid,
    p_correlation_id uuid,
    p_idempotency_key text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, recoveries
AS $function$
DECLARE
    envelope jsonb;
BEGIN
    IF p_organization_id IS DISTINCT FROM nullif(
        current_setting('anarchi.current_organization_id', true), ''
    )::uuid THEN
        RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
    END IF;

    INSERT INTO recoveries.evidence (
        organization_id, project_id, id, source_system, external_id,
        source_version, source_observed_at, object_uri, original_filename,
        mime_type, size_bytes, sha256, metadata
    ) VALUES (
        p_organization_id, p_project_id, p_evidence_id, p_source_system,
        p_external_id, p_source_version, p_source_observed_at, p_object_uri,
        p_original_filename, p_mime_type, p_size_bytes, p_sha256,
        coalesce(p_metadata, '{}'::jsonb)
    );

    envelope := jsonb_build_object(
        'schema_version', '1.0',
        'event_id', p_event_id::text,
        'event_type', 'evidence.persisted',
        'organization_id', p_organization_id::text,
        'project_id', p_project_id::text,
        'aggregate_id', p_evidence_id::text,
        'occurred_at', to_char(p_occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'causation_id', CASE WHEN p_causation_id IS NULL THEN null::jsonb ELSE to_jsonb(p_causation_id::text) END,
        'correlation_id', p_correlation_id::text,
        'idempotency_key', p_idempotency_key,
        'payload', jsonb_build_object(
            'object_uri', p_object_uri,
            'sha256', p_sha256,
            'size_bytes', p_size_bytes,
            'mime_type', p_mime_type
        )
    );

    INSERT INTO recoveries.transactional_outbox (
        organization_id, project_id, event_id, subject, aggregate_id,
        correlation_id, causation_id, idempotency_key, occurred_at,
        available_at, envelope, envelope_sha256
    ) VALUES (
        p_organization_id, p_project_id, p_event_id, 'evidence.persisted.v1',
        p_evidence_id, p_correlation_id, p_causation_id, p_idempotency_key,
        p_occurred_at, p_occurred_at, envelope,
        encode(public.digest(convert_to(envelope::text, 'UTF8'), 'sha256'), 'hex')
    );

    RETURN p_evidence_id;
END
$function$;

REVOKE ALL ON FUNCTION recoveries.persist_ingested_evidence(
    uuid, uuid, uuid, text, text, text, timestamptz, text, text, text,
    bigint, text, jsonb, uuid, timestamptz, uuid, uuid, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION recoveries.persist_ingested_evidence(
    uuid, uuid, uuid, text, text, text, timestamptz, text, text, text,
    bigint, text, jsonb, uuid, timestamptz, uuid, uuid, text
) TO recoveries_runtime_role;

COMMIT;
