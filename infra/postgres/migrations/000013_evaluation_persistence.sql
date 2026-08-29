BEGIN;

CREATE FUNCTION recoveries.persist_recovery_evaluation(
    p_organization_id uuid,
    p_project_id uuid,
    p_baseline_id uuid,
    p_evaluation_id uuid,
    p_opportunity_id uuid,
    p_detection_class text,
    p_evaluation_time timestamptz,
    p_evaluation_hash text,
    p_canonical_decision text,
    p_record jsonb,
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
    decision_tag text;
    decision_result jsonb;
    aggregate_id uuid;
    event_envelope jsonb;
BEGIN
    IF p_organization_id IS NULL OR p_project_id IS NULL OR p_baseline_id IS NULL
       OR p_evaluation_id IS NULL OR p_evaluation_time IS NULL
       OR p_evaluation_hash IS NULL OR p_event_id IS NULL
       OR p_occurred_at IS NULL OR p_correlation_id IS NULL
       OR p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'evaluation identity and timing are required' USING ERRCODE = '22023';
    END IF;
    IF p_organization_id IS DISTINCT FROM nullif(
        current_setting('anarchi.current_organization_id', true), ''
    )::uuid THEN
        RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
    END IF;
    IF p_evaluation_hash !~ '^[a-f0-9]{64}$' THEN
        RAISE EXCEPTION 'evaluation hash must be lowercase sha256' USING ERRCODE = '22023';
    END IF;
    IF p_record IS NULL OR jsonb_typeof(p_record) IS DISTINCT FROM 'object'
       OR p_record ->> 'canonicalization' <> 'ANARCHI-JCS-COMPATIBLE-V1'
       OR p_record ->> 'evaluation_hash' IS DISTINCT FROM p_evaluation_hash
       OR jsonb_typeof(p_record -> 'decision') IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'evaluation record is not a canonical core record' USING ERRCODE = '22023';
    END IF;
    IF p_canonical_decision IS NULL OR btrim(p_canonical_decision) = ''
       OR (p_record -> 'decision')::text IS DISTINCT FROM p_canonical_decision
       OR encode(public.digest(convert_to(p_canonical_decision, 'UTF8'), 'sha256'), 'hex')
          IS DISTINCT FROM p_evaluation_hash THEN
        RAISE EXCEPTION 'evaluation decision hash mismatch' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM recoveries.contract_baselines
        WHERE organization_id = p_organization_id
          AND project_id = p_project_id
          AND id = p_baseline_id
          AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'evaluation requires an active baseline' USING ERRCODE = '55000';
    END IF;

    decision_tag := p_record -> 'decision' ->> 'decision';
    decision_result := p_record -> 'decision' -> 'result';
    IF decision_tag = 'OPPORTUNITY' THEN
        IF p_opportunity_id IS NULL OR p_detection_class IS NULL
           OR p_detection_class NOT IN (
                'DRAWING_QUANTITY_DELTA', 'RFI_DIRECTIVE_SCOPE_CHANGE',
                'TM_UNCONVERTED', 'ATTACHED_COST_RECORDS'
           )
           OR jsonb_typeof(decision_result) IS DISTINCT FROM 'object'
           OR (decision_result ->> 'organization_id')::uuid IS DISTINCT FROM p_organization_id
           OR (decision_result ->> 'project_id')::uuid IS DISTINCT FROM p_project_id
           OR (decision_result ->> 'baseline_id')::uuid IS DISTINCT FROM p_baseline_id
           OR (decision_result ->> 'evaluation_time')::timestamptz IS DISTINCT FROM p_evaluation_time
           OR btrim(coalesce(decision_result ->> 'domain_rule_version', '')) = ''
           OR btrim(coalesce(decision_result ->> 'notice_rule_version', '')) = ''
           OR jsonb_typeof(decision_result -> 'pricing') IS DISTINCT FROM 'object'
           OR btrim(coalesce(decision_result -> 'pricing' ->> 'pricing_rule_version', '')) = '' THEN
            RAISE EXCEPTION 'opportunity evaluation result is incomplete or crosses its boundary'
                USING ERRCODE = '22023';
        END IF;
        INSERT INTO recoveries.recovery_opportunities (
            organization_id, project_id, id, baseline_id, detection_class, status,
            domain_rule_version, pricing_rule_version, notice_rule_version,
            evaluation_time, evaluation_hash, decision
        ) VALUES (
            p_organization_id, p_project_id, p_opportunity_id, p_baseline_id,
            p_detection_class, 'DETECTED', decision_result ->> 'domain_rule_version',
            decision_result -> 'pricing' ->> 'pricing_rule_version',
            decision_result ->> 'notice_rule_version', p_evaluation_time,
            p_evaluation_hash, p_record -> 'decision'
        ) ON CONFLICT (organization_id, id) DO NOTHING;
        IF NOT EXISTS (
            SELECT 1 FROM recoveries.recovery_opportunities
            WHERE organization_id = p_organization_id
              AND id = p_opportunity_id
              AND project_id = p_project_id
              AND baseline_id = p_baseline_id
              AND evaluation_hash = p_evaluation_hash
              AND decision = p_record -> 'decision'
        ) THEN
            RAISE EXCEPTION 'opportunity evaluation replay conflicts with existing receipt'
                USING ERRCODE = '23505';
        END IF;
        aggregate_id := p_opportunity_id;
    ELSIF decision_tag = 'NO_OPPORTUNITY' THEN
        IF p_opportunity_id IS NOT NULL OR p_detection_class IS NOT NULL
           OR decision_result IS NULL
           OR decision_result #>> '{}' NOT IN (
                'NO_VERIFIED_DRAWING_DELTA', 'ITEM_MAPPING_UNVERIFIED',
                'NON_POSITIVE_QUANTITY_DELTA', 'ALLOWANCE_REMAINING',
                'EXISTING_CHANGE_ORDER_COVERAGE',
                'DIRECTION_OR_PERFORMED_WORK_UNVERIFIED'
           ) THEN
            RAISE EXCEPTION 'no-opportunity evaluation result is invalid' USING ERRCODE = '22023';
        END IF;
        aggregate_id := p_baseline_id;
    ELSE
        RAISE EXCEPTION 'unsupported evaluation decision' USING ERRCODE = '22023';
    END IF;

    INSERT INTO recoveries.audit_events (
        organization_id, project_id, id, event_type, actor_type, actor_id,
        aggregate_type, aggregate_id, details, occurred_at
    ) VALUES (
        p_organization_id, p_project_id, p_evaluation_id, 'recovery.evaluated',
        'SERVICE', 'normalization-worker', 'RECOVERY_EVALUATION', aggregate_id,
        jsonb_build_object(
            'canonicalization', p_record ->> 'canonicalization',
            'canonical_decision', p_canonical_decision,
            'evaluation_hash', p_evaluation_hash,
            'evaluation_time', p_evaluation_time,
            'opportunity_id', p_opportunity_id,
            'record', p_record
        ), p_occurred_at
    ) ON CONFLICT (organization_id, id) DO NOTHING;
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.audit_events
        WHERE organization_id = p_organization_id
          AND id = p_evaluation_id
          AND project_id = p_project_id
          AND details ->> 'evaluation_hash' = p_evaluation_hash
          AND details -> 'record' = p_record
    ) THEN
        RAISE EXCEPTION 'evaluation audit replay conflicts with existing receipt'
            USING ERRCODE = '23505';
    END IF;

    event_envelope := jsonb_build_object(
        'schema_version', '1.0',
        'event_id', p_event_id::text,
        'event_type', 'recovery.evaluated',
        'organization_id', p_organization_id::text,
        'project_id', p_project_id::text,
        'aggregate_id', aggregate_id::text,
        'occurred_at', to_char(p_occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'causation_id', CASE WHEN p_causation_id IS NULL THEN null::jsonb ELSE to_jsonb(p_causation_id::text) END,
        'correlation_id', p_correlation_id::text,
        'idempotency_key', p_idempotency_key,
        'payload', jsonb_build_object(
            'evaluation_id', p_evaluation_id::text,
            'baseline_id', p_baseline_id::text,
            'opportunity_id', CASE WHEN p_opportunity_id IS NULL THEN null::jsonb ELSE to_jsonb(p_opportunity_id::text) END,
            'decision', decision_tag,
            'evaluation_hash', p_evaluation_hash
        )
    );
    INSERT INTO recoveries.transactional_outbox (
        organization_id, project_id, event_id, subject, aggregate_id,
        correlation_id, causation_id, idempotency_key, occurred_at,
        available_at, envelope, envelope_sha256
    ) VALUES (
        p_organization_id, p_project_id, p_event_id, 'recovery.evaluated.v1',
        aggregate_id, p_correlation_id, p_causation_id, p_idempotency_key,
        p_occurred_at, p_occurred_at, event_envelope,
        encode(public.digest(convert_to(event_envelope::text, 'UTF8'), 'sha256'), 'hex')
    ) ON CONFLICT (organization_id, event_id) DO NOTHING;
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.transactional_outbox
        WHERE organization_id = p_organization_id
          AND event_id = p_event_id
          AND recoveries.transactional_outbox.envelope = event_envelope
          AND recoveries.transactional_outbox.envelope_sha256 = encode(
              public.digest(convert_to(event_envelope::text, 'UTF8'), 'sha256'), 'hex'
          )
    ) THEN
        RAISE EXCEPTION 'evaluation event replay conflicts with existing receipt'
            USING ERRCODE = '23505';
    END IF;
    RETURN p_evaluation_id;
END
$function$;

REVOKE ALL ON FUNCTION recoveries.persist_recovery_evaluation(
    uuid, uuid, uuid, uuid, uuid, text, timestamptz, text, text, jsonb,
    uuid, timestamptz, uuid, uuid, text
) FROM PUBLIC;
GRANT USAGE ON SCHEMA recoveries TO recoveries_evaluation_role;
GRANT EXECUTE ON FUNCTION recoveries.persist_recovery_evaluation(
    uuid, uuid, uuid, uuid, uuid, text, timestamptz, text, text, jsonb,
    uuid, timestamptz, uuid, uuid, text
) TO recoveries_evaluation_role;

REVOKE INSERT, UPDATE, DELETE ON recoveries.recovery_opportunities
    FROM recoveries_runtime_role;

COMMIT;
