BEGIN;

CREATE TABLE recoveries.baseline_facts (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    baseline_id uuid NOT NULL,
    fact_id uuid NOT NULL,
    purpose text NOT NULL CHECK (btrim(purpose) <> ''),
    PRIMARY KEY (organization_id, baseline_id, fact_id),
    FOREIGN KEY (organization_id, project_id, baseline_id)
        REFERENCES recoveries.contract_baselines(organization_id, project_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, project_id, fact_id)
        REFERENCES recoveries.facts(organization_id, project_id, id) ON DELETE RESTRICT
);

CREATE POLICY tenant_isolation ON recoveries.baseline_facts
    USING (organization_id = nullif(current_setting('anarchi.current_organization_id', true), '')::uuid)
    WITH CHECK (organization_id = nullif(current_setting('anarchi.current_organization_id', true), '')::uuid);
ALTER TABLE recoveries.baseline_facts ENABLE ROW LEVEL SECURITY;
ALTER TABLE recoveries.baseline_facts FORCE ROW LEVEL SECURITY;
ALTER TABLE recoveries.baseline_facts OWNER TO recoveries_migration_role;

CREATE FUNCTION recoveries.guard_baseline_immutability() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, recoveries
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'baseline versions cannot be deleted' USING ERRCODE = '55000';
    END IF;
    IF OLD.status = 'DRAFT' THEN
        IF NEW.organization_id <> OLD.organization_id OR NEW.project_id <> OLD.project_id
           OR NEW.id <> OLD.id OR NEW.version <> OLD.version THEN
            RAISE EXCEPTION 'baseline identity is immutable' USING ERRCODE = '55000';
        END IF;
        IF NEW.status <> 'DRAFT'
           AND current_setting('anarchi.baseline_activation_authorized', true) <> 'true' THEN
            RAISE EXCEPTION 'baseline activation requires compiler function' USING ERRCODE = '42501';
        END IF;
        RETURN NEW;
    END IF;
    IF OLD.status = 'ACTIVE' AND NEW.status = 'SUPERSEDED'
       AND current_setting('anarchi.baseline_activation_authorized', true) = 'true'
       AND NEW.organization_id = OLD.organization_id AND NEW.project_id = OLD.project_id
       AND NEW.id = OLD.id AND NEW.version = OLD.version
       AND NEW.compiled_at = OLD.compiled_at AND NEW.compiled_by = OLD.compiled_by
       AND NEW.canonical_sha256 = OLD.canonical_sha256 THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'compiled baseline is immutable' USING ERRCODE = '55000';
END
$function$;

CREATE TRIGGER contract_baseline_immutability
BEFORE UPDATE OR DELETE ON recoveries.contract_baselines
FOR EACH ROW EXECUTE FUNCTION recoveries.guard_baseline_immutability();

CREATE FUNCTION recoveries.guard_compiled_baseline_link() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, recoveries
AS $function$
DECLARE
    target_baseline uuid;
    target_org uuid;
    target_status text;
BEGIN
    target_baseline := coalesce(NEW.baseline_id, OLD.baseline_id);
    target_org := coalesce(NEW.organization_id, OLD.organization_id);
    SELECT status INTO target_status
    FROM recoveries.contract_baselines
    WHERE organization_id = target_org AND id = target_baseline;
    IF target_status IS DISTINCT FROM 'DRAFT' THEN
        RAISE EXCEPTION 'compiled baseline links are immutable' USING ERRCODE = '55000';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END
$function$;

CREATE TRIGGER baseline_fact_link_guard
BEFORE INSERT OR UPDATE OR DELETE ON recoveries.baseline_facts
FOR EACH ROW EXECUTE FUNCTION recoveries.guard_compiled_baseline_link();
CREATE TRIGGER baseline_evidence_link_guard
BEFORE INSERT OR UPDATE OR DELETE ON recoveries.baseline_evidence
FOR EACH ROW EXECUTE FUNCTION recoveries.guard_compiled_baseline_link();

CREATE FUNCTION recoveries.guard_scope_version_immutability() RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION 'scope history is append-only' USING ERRCODE = '55000';
END
$function$;
CREATE TRIGGER scope_version_append_only
BEFORE UPDATE OR DELETE ON recoveries.scope_item_versions
FOR EACH ROW EXECUTE FUNCTION recoveries.guard_scope_version_immutability();

CREATE FUNCTION recoveries.activate_reviewed_baseline(
    p_organization_id uuid,
    p_project_id uuid,
    p_baseline_id uuid,
    p_compiled_at timestamptz,
    p_canonical_sha256 text,
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
    actor_id uuid;
    envelope jsonb;
BEGIN
    IF p_organization_id IS DISTINCT FROM nullif(current_setting('anarchi.current_organization_id', true), '')::uuid THEN
        RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
    END IF;
    actor_id := nullif(current_setting('anarchi.current_user_id', true), '')::uuid;
    IF actor_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM recoveries.organization_memberships
        WHERE organization_id = p_organization_id AND user_id = actor_id AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'active reviewer membership required' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.contract_baselines
        WHERE organization_id = p_organization_id AND project_id = p_project_id
          AND id = p_baseline_id AND status = 'DRAFT'
    ) THEN
        RAISE EXCEPTION 'target baseline must be DRAFT' USING ERRCODE = '55000';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.baseline_evidence
        WHERE organization_id = p_organization_id AND project_id = p_project_id
          AND baseline_id = p_baseline_id
    ) OR NOT EXISTS (
        SELECT 1 FROM recoveries.baseline_facts bf
        JOIN recoveries.facts f
          ON f.organization_id = bf.organization_id AND f.project_id = bf.project_id AND f.id = bf.fact_id
        WHERE bf.organization_id = p_organization_id AND bf.project_id = p_project_id
          AND bf.baseline_id = p_baseline_id AND f.verification_status = 'VERIFIED'
    ) OR EXISTS (
        SELECT 1 FROM recoveries.baseline_facts bf
        JOIN recoveries.facts f
          ON f.organization_id = bf.organization_id AND f.project_id = bf.project_id AND f.id = bf.fact_id
        WHERE bf.organization_id = p_organization_id AND bf.project_id = p_project_id
          AND bf.baseline_id = p_baseline_id AND f.verification_status <> 'VERIFIED'
    ) THEN
        RAISE EXCEPTION 'baseline requires evidence and only verified facts' USING ERRCODE = '23514';
    END IF;

    PERFORM set_config('anarchi.baseline_activation_authorized', 'true', true);
    UPDATE recoveries.contract_baselines SET status = 'SUPERSEDED'
    WHERE organization_id = p_organization_id AND project_id = p_project_id AND status = 'ACTIVE';
    UPDATE recoveries.contract_baselines
    SET status = 'ACTIVE', compiled_at = p_compiled_at, compiled_by = actor_id,
        canonical_sha256 = p_canonical_sha256
    WHERE organization_id = p_organization_id AND project_id = p_project_id AND id = p_baseline_id;

    envelope := jsonb_build_object(
        'schema_version', '1.0', 'event_id', p_event_id::text,
        'event_type', 'baseline.activated', 'organization_id', p_organization_id::text,
        'project_id', p_project_id::text, 'aggregate_id', p_baseline_id::text,
        'occurred_at', to_char(p_occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'causation_id', CASE WHEN p_causation_id IS NULL THEN null::jsonb ELSE to_jsonb(p_causation_id::text) END,
        'correlation_id', p_correlation_id::text, 'idempotency_key', p_idempotency_key,
        'payload', jsonb_build_object('canonical_sha256', p_canonical_sha256)
    );
    INSERT INTO recoveries.transactional_outbox (
        organization_id, project_id, event_id, subject, aggregate_id, correlation_id,
        causation_id, idempotency_key, occurred_at, available_at, envelope, envelope_sha256
    ) VALUES (
        p_organization_id, p_project_id, p_event_id, 'baseline.activated.v1', p_baseline_id,
        p_correlation_id, p_causation_id, p_idempotency_key, p_occurred_at, p_occurred_at,
        envelope, encode(public.digest(convert_to(envelope::text, 'UTF8'), 'sha256'), 'hex')
    );
    RETURN p_baseline_id;
END
$function$;

REVOKE UPDATE, DELETE ON recoveries.contract_baselines FROM recoveries_runtime_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON recoveries.baseline_facts TO recoveries_runtime_role;
REVOKE ALL ON FUNCTION recoveries.activate_reviewed_baseline(
    uuid, uuid, uuid, timestamptz, text, uuid, timestamptz, uuid, uuid, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION recoveries.activate_reviewed_baseline(
    uuid, uuid, uuid, timestamptz, text, uuid, timestamptz, uuid, uuid, text
) TO recoveries_runtime_role;

COMMIT;
