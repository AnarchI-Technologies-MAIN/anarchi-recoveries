BEGIN;

CREATE TABLE recoveries.consumer_inbox (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    consumer_name text NOT NULL CHECK (btrim(consumer_name) <> ''),
    event_id uuid NOT NULL,
    subject text NOT NULL CHECK (subject IN (
        'ingest.received.v1', 'evidence.persisted.v1',
        'evidence.normalize.requested.v1', 'evidence.normalized.v1',
        'extraction.requested.v1', 'extraction.completed.v1',
        'fact.candidate.created.v1', 'fact.verified.v1',
        'baseline.activated.v1', 'recovery.evaluate.requested.v1',
        'recovery.evaluated.v1', 'opportunity.updated.v1',
        'action.requested.v1', 'action.authorized.v1', 'action.executed.v1',
        'payment.observed.v1', 'attribution.reconciled.v1',
        'billing.success_fee.accrued.v1'
    )),
    envelope_sha256 text NOT NULL CHECK (envelope_sha256 ~ '^[a-f0-9]{64}$'),
    received_at timestamptz NOT NULL,
    processed_at timestamptz,
    processing_result text CHECK (processing_result IN ('APPLIED', 'IGNORED')),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, consumer_name, event_id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES recoveries.projects(organization_id, id) ON DELETE RESTRICT,
    CHECK (
        (processed_at IS NULL AND processing_result IS NULL)
        OR (processed_at IS NOT NULL AND processing_result IS NOT NULL)
    )
);

CREATE TABLE recoveries.transactional_outbox (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    event_id uuid NOT NULL,
    subject text NOT NULL CHECK (subject IN (
        'ingest.received.v1', 'evidence.persisted.v1',
        'evidence.normalize.requested.v1', 'evidence.normalized.v1',
        'extraction.requested.v1', 'extraction.completed.v1',
        'fact.candidate.created.v1', 'fact.verified.v1',
        'baseline.activated.v1', 'recovery.evaluate.requested.v1',
        'recovery.evaluated.v1', 'opportunity.updated.v1',
        'action.requested.v1', 'action.authorized.v1', 'action.executed.v1',
        'payment.observed.v1', 'attribution.reconciled.v1',
        'billing.success_fee.accrued.v1'
    )),
    aggregate_id uuid NOT NULL,
    correlation_id uuid NOT NULL,
    causation_id uuid,
    idempotency_key text NOT NULL CHECK (btrim(idempotency_key) <> ''),
    occurred_at timestamptz NOT NULL,
    envelope jsonb NOT NULL CHECK (jsonb_typeof(envelope) = 'object'),
    envelope_sha256 text NOT NULL CHECK (envelope_sha256 ~ '^[a-f0-9]{64}$'),
    status text NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'CLAIMED', 'PUBLISHED', 'DEAD_LETTER')),
    available_at timestamptz NOT NULL,
    claim_token uuid,
    claimed_by text,
    lease_expires_at timestamptz,
    publish_attempts integer NOT NULL DEFAULT 0 CHECK (publish_attempts >= 0),
    last_error text,
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    UNIQUE (organization_id, event_id),
    UNIQUE (organization_id, idempotency_key),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES recoveries.projects(organization_id, id) ON DELETE RESTRICT,
    CHECK (envelope ->> 'schema_version' = '1.0'),
    CHECK ((envelope ->> 'event_id')::uuid = event_id),
    CHECK (envelope ->> 'event_type' = left(subject, length(subject) - 3)),
    CHECK ((envelope ->> 'organization_id')::uuid = organization_id),
    CHECK ((envelope ->> 'project_id')::uuid = project_id),
    CHECK ((envelope ->> 'aggregate_id')::uuid = aggregate_id),
    CHECK ((envelope ->> 'correlation_id')::uuid = correlation_id),
    CHECK ((envelope ->> 'occurred_at')::timestamptz = occurred_at),
    CHECK (
        (causation_id IS NULL AND envelope -> 'causation_id' = 'null'::jsonb)
        OR (causation_id IS NOT NULL AND (envelope ->> 'causation_id')::uuid = causation_id)
    ),
    CHECK (envelope ->> 'idempotency_key' = idempotency_key),
    CHECK (jsonb_typeof(envelope -> 'payload') = 'object'),
    CHECK (
        (status = 'PENDING' AND claim_token IS NULL AND claimed_by IS NULL
            AND lease_expires_at IS NULL AND published_at IS NULL)
        OR (status = 'CLAIMED' AND claim_token IS NOT NULL AND claimed_by IS NOT NULL
            AND lease_expires_at IS NOT NULL AND published_at IS NULL)
        OR (status = 'PUBLISHED' AND claim_token IS NULL AND claimed_by IS NULL
            AND lease_expires_at IS NULL AND published_at IS NOT NULL)
        OR (status = 'DEAD_LETTER' AND claim_token IS NULL AND claimed_by IS NULL
            AND lease_expires_at IS NULL AND published_at IS NULL AND last_error IS NOT NULL)
    )
);

CREATE INDEX transactional_outbox_claimable
    ON recoveries.transactional_outbox (organization_id, available_at, id)
    WHERE status IN ('PENDING', 'CLAIMED');

CREATE TABLE recoveries.audit_events (
    organization_id uuid NOT NULL,
    project_id uuid,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    event_type text NOT NULL CHECK (btrim(event_type) <> ''),
    actor_type text NOT NULL CHECK (actor_type IN ('USER', 'SERVICE', 'SYSTEM')),
    actor_id text NOT NULL CHECK (btrim(actor_id) <> ''),
    aggregate_type text NOT NULL CHECK (btrim(aggregate_type) <> ''),
    aggregate_id uuid NOT NULL,
    details jsonb NOT NULL CHECK (jsonb_typeof(details) = 'object'),
    occurred_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES recoveries.projects(organization_id, id) ON DELETE RESTRICT
);

CREATE POLICY tenant_isolation ON recoveries.consumer_inbox
    USING (organization_id = nullif(current_setting('anarchi.current_organization_id', true), '')::uuid)
    WITH CHECK (organization_id = nullif(current_setting('anarchi.current_organization_id', true), '')::uuid);
CREATE POLICY tenant_isolation ON recoveries.transactional_outbox
    USING (organization_id = nullif(current_setting('anarchi.current_organization_id', true), '')::uuid)
    WITH CHECK (organization_id = nullif(current_setting('anarchi.current_organization_id', true), '')::uuid);
CREATE POLICY tenant_isolation ON recoveries.audit_events
    USING (organization_id = nullif(current_setting('anarchi.current_organization_id', true), '')::uuid)
    WITH CHECK (organization_id = nullif(current_setting('anarchi.current_organization_id', true), '')::uuid);

ALTER TABLE recoveries.consumer_inbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE recoveries.consumer_inbox FORCE ROW LEVEL SECURITY;
ALTER TABLE recoveries.transactional_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE recoveries.transactional_outbox FORCE ROW LEVEL SECURITY;
ALTER TABLE recoveries.audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE recoveries.audit_events FORCE ROW LEVEL SECURITY;

CREATE FUNCTION recoveries.claim_outbox(
    p_claimed_by text,
    p_batch_size integer,
    p_now timestamptz,
    p_lease interval
) RETURNS SETOF recoveries.transactional_outbox
LANGUAGE plpgsql
AS $function$
BEGIN
    IF btrim(p_claimed_by) = '' OR p_batch_size < 1 OR p_batch_size > 1000
       OR p_lease <= interval '0 seconds' THEN
        RAISE EXCEPTION 'invalid outbox claim parameters';
    END IF;

    RETURN QUERY
    WITH candidates AS (
        SELECT candidate.organization_id, candidate.id
        FROM recoveries.transactional_outbox AS candidate
        WHERE (
            (candidate.status = 'PENDING' AND candidate.available_at <= p_now)
            OR (candidate.status = 'CLAIMED' AND candidate.lease_expires_at <= p_now)
        )
        ORDER BY candidate.available_at, candidate.id
        FOR UPDATE SKIP LOCKED
        LIMIT p_batch_size
    )
    UPDATE recoveries.transactional_outbox AS outbox
    SET status = 'CLAIMED',
        claim_token = gen_random_uuid(),
        claimed_by = p_claimed_by,
        lease_expires_at = p_now + p_lease,
        updated_at = p_now
    FROM candidates
    WHERE outbox.organization_id = candidates.organization_id
      AND outbox.id = candidates.id
    RETURNING outbox.*;
END
$function$;

CREATE FUNCTION recoveries.mark_outbox_published(
    p_organization_id uuid,
    p_outbox_id uuid,
    p_claim_token uuid,
    p_published_at timestamptz
) RETURNS boolean
LANGUAGE sql
AS $function$
    WITH published AS (
        UPDATE recoveries.transactional_outbox
        SET status = 'PUBLISHED',
            claim_token = NULL,
            claimed_by = NULL,
            lease_expires_at = NULL,
            publish_attempts = publish_attempts + 1,
            published_at = p_published_at,
            last_error = NULL,
            updated_at = p_published_at
        WHERE organization_id = p_organization_id
          AND id = p_outbox_id
          AND status = 'CLAIMED'
          AND claim_token = p_claim_token
        RETURNING 1
    )
    SELECT EXISTS (SELECT 1 FROM published);
$function$;

CREATE FUNCTION recoveries.record_outbox_publish_failure(
    p_organization_id uuid,
    p_outbox_id uuid,
    p_claim_token uuid,
    p_error text,
    p_retry_at timestamptz,
    p_max_attempts integer,
    p_failed_at timestamptz
) RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
    next_status text;
BEGIN
    IF btrim(p_error) = '' OR p_max_attempts < 1 OR p_retry_at < p_failed_at THEN
        RAISE EXCEPTION 'invalid outbox failure parameters';
    END IF;

    UPDATE recoveries.transactional_outbox
    SET publish_attempts = publish_attempts + 1,
        status = CASE
            WHEN publish_attempts + 1 >= p_max_attempts THEN 'DEAD_LETTER'
            ELSE 'PENDING'
        END,
        available_at = p_retry_at,
        claim_token = NULL,
        claimed_by = NULL,
        lease_expires_at = NULL,
        last_error = p_error,
        updated_at = p_failed_at
    WHERE organization_id = p_organization_id
      AND id = p_outbox_id
      AND status = 'CLAIMED'
      AND claim_token = p_claim_token
    RETURNING status INTO next_status;

    RETURN next_status;
END
$function$;

CREATE FUNCTION recoveries.audit_outbox_dead_letter() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, recoveries
AS $function$
BEGIN
    IF NEW.status = 'DEAD_LETTER' AND OLD.status <> 'DEAD_LETTER' THEN
        INSERT INTO recoveries.audit_events (
            organization_id, project_id, event_type, actor_type, actor_id,
            aggregate_type, aggregate_id, details, occurred_at
        ) VALUES (
            NEW.organization_id, NEW.project_id, 'OUTBOX_DEAD_LETTERED',
            'SERVICE', COALESCE(OLD.claimed_by, 'unknown-publisher'),
            'TRANSACTIONAL_OUTBOX', NEW.id,
            jsonb_build_object(
                'event_id', NEW.event_id,
                'subject', NEW.subject,
                'publish_attempts', NEW.publish_attempts,
                'last_error', NEW.last_error
            ),
            NEW.updated_at
        );
    END IF;
    RETURN NEW;
END
$function$;

CREATE TRIGGER transactional_outbox_dead_letter_audit
AFTER UPDATE OF status ON recoveries.transactional_outbox
FOR EACH ROW EXECUTE FUNCTION recoveries.audit_outbox_dead_letter();

REVOKE ALL ON FUNCTION recoveries.claim_outbox(text, integer, timestamptz, interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION recoveries.mark_outbox_published(uuid, uuid, uuid, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION recoveries.record_outbox_publish_failure(uuid, uuid, uuid, text, timestamptz, integer, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION recoveries.audit_outbox_dead_letter() FROM PUBLIC;

GRANT SELECT, INSERT, UPDATE ON recoveries.consumer_inbox TO recoveries_runtime_role;
GRANT SELECT, INSERT ON recoveries.transactional_outbox TO recoveries_runtime_role;
GRANT SELECT ON recoveries.audit_events TO recoveries_runtime_role;

GRANT USAGE ON SCHEMA recoveries TO recoveries_outbox_publisher_role;
GRANT SELECT, UPDATE ON recoveries.transactional_outbox TO recoveries_outbox_publisher_role;
GRANT SELECT ON recoveries.audit_events TO recoveries_outbox_publisher_role;
GRANT EXECUTE ON FUNCTION recoveries.claim_outbox(text, integer, timestamptz, interval)
    TO recoveries_outbox_publisher_role;
GRANT EXECUTE ON FUNCTION recoveries.mark_outbox_published(uuid, uuid, uuid, timestamptz)
    TO recoveries_outbox_publisher_role;
GRANT EXECUTE ON FUNCTION recoveries.record_outbox_publish_failure(uuid, uuid, uuid, text, timestamptz, integer, timestamptz)
    TO recoveries_outbox_publisher_role;

COMMIT;
