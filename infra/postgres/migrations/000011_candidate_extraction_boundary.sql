BEGIN;

CREATE FUNCTION recoveries.persist_fact_candidate(
    p_organization_id uuid,
    p_project_id uuid,
    p_fact_id uuid,
    p_fact_type text,
    p_subject text,
    p_value jsonb,
    p_unit text,
    p_currency text,
    p_source_evidence_id uuid,
    p_source_location text,
    p_extraction_method text,
    p_model_or_parser_version text,
    p_candidate_confidence numeric,
    p_event_id uuid,
    p_occurred_at timestamptz,
    p_causation_id uuid,
    p_correlation_id uuid,
    p_idempotency_key text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, recoveries
SET row_security = on
AS $function$
DECLARE
    envelope jsonb;
BEGIN
    IF p_organization_id IS DISTINCT FROM nullif(
        current_setting('anarchi.current_organization_id', true), ''
    )::uuid THEN
        RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
    END IF;

    INSERT INTO recoveries.facts (
        organization_id, project_id, id, fact_type, subject, value, unit,
        currency, source_evidence_id, source_location, extraction_method,
        model_or_parser_version, candidate_confidence, verification_status
    ) VALUES (
        p_organization_id, p_project_id, p_fact_id, p_fact_type, p_subject,
        p_value, p_unit, p_currency, p_source_evidence_id, p_source_location,
        p_extraction_method, p_model_or_parser_version,
        p_candidate_confidence, 'CANDIDATE'
    );

    envelope := jsonb_build_object(
        'schema_version', '1.0',
        'event_id', p_event_id::text,
        'event_type', 'fact.candidate.created',
        'organization_id', p_organization_id::text,
        'project_id', p_project_id::text,
        'aggregate_id', p_fact_id::text,
        'occurred_at', to_char(p_occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'causation_id', CASE WHEN p_causation_id IS NULL THEN null::jsonb ELSE to_jsonb(p_causation_id::text) END,
        'correlation_id', p_correlation_id::text,
        'idempotency_key', p_idempotency_key,
        'payload', jsonb_build_object(
            'fact_type', p_fact_type,
            'source_evidence_id', p_source_evidence_id::text,
            'source_location', p_source_location,
            'extraction_method', p_extraction_method,
            'model_or_parser_version', p_model_or_parser_version,
            'candidate_confidence', p_candidate_confidence
        )
    );

    INSERT INTO recoveries.transactional_outbox (
        organization_id, project_id, event_id, subject, aggregate_id,
        correlation_id, causation_id, idempotency_key, occurred_at,
        available_at, envelope, envelope_sha256
    ) VALUES (
        p_organization_id, p_project_id, p_event_id, 'fact.candidate.created.v1',
        p_fact_id, p_correlation_id, p_causation_id, p_idempotency_key,
        p_occurred_at, p_occurred_at, envelope,
        encode(public.digest(convert_to(envelope::text, 'UTF8'), 'sha256'), 'hex')
    );

    RETURN p_fact_id;
END
$function$;

REVOKE ALL ON FUNCTION recoveries.persist_fact_candidate(
    uuid, uuid, uuid, text, text, jsonb, text, text, uuid, text, text,
    text, numeric, uuid, timestamptz, uuid, uuid, text
) FROM PUBLIC;
REVOKE ALL ON TABLE recoveries.facts, recoveries.transactional_outbox
    FROM recoveries_extraction_role;
GRANT USAGE ON SCHEMA recoveries TO recoveries_extraction_role;
GRANT EXECUTE ON FUNCTION recoveries.persist_fact_candidate(
    uuid, uuid, uuid, text, text, jsonb, text, text, uuid, text, text,
    text, numeric, uuid, timestamptz, uuid, uuid, text
) TO recoveries_extraction_role;

COMMIT;
