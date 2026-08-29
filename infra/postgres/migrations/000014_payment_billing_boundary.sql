BEGIN;

CREATE TABLE recoveries.payments (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    source_system text NOT NULL CHECK (btrim(source_system) <> ''),
    external_id text,
    observed_at timestamptz NOT NULL,
    amount numeric(30, 10) NOT NULL CHECK (amount > 0),
    currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    UNIQUE (organization_id, project_id, source_system, external_id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES recoveries.projects(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE recoveries.recovery_payment_allocations (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    payment_id uuid NOT NULL,
    opportunity_id uuid NOT NULL,
    allocated_amount numeric(30, 10) NOT NULL CHECK (allocated_amount >= 0),
    currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    UNIQUE (organization_id, project_id, payment_id, opportunity_id),
    FOREIGN KEY (organization_id, project_id, payment_id)
        REFERENCES recoveries.payments(organization_id, project_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, project_id, opportunity_id)
        REFERENCES recoveries.recovery_opportunities(organization_id, project_id, id) ON DELETE RESTRICT
);

CREATE TABLE recoveries.success_fee_accruals (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    allocation_id uuid NOT NULL,
    payment_id uuid NOT NULL,
    opportunity_id uuid NOT NULL,
    attribution_rule_version text NOT NULL CHECK (btrim(attribution_rule_version) <> ''),
    fee_rate_percent numeric(20, 10) NOT NULL CHECK (fee_rate_percent >= 0 AND fee_rate_percent <= 100),
    fee_base numeric(30, 10) NOT NULL CHECK (fee_base >= 0),
    fee_amount numeric(30, 10) NOT NULL CHECK (fee_amount >= 0),
    currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    accrued_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    UNIQUE (organization_id, project_id, allocation_id),
    FOREIGN KEY (organization_id, project_id, allocation_id)
        REFERENCES recoveries.recovery_payment_allocations(organization_id, project_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, project_id, payment_id)
        REFERENCES recoveries.payments(organization_id, project_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, project_id, opportunity_id)
        REFERENCES recoveries.recovery_opportunities(organization_id, project_id, id) ON DELETE RESTRICT
);

DO $tenant_policies$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'payments', 'recovery_payment_allocations', 'success_fee_accruals'
    ] LOOP
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON recoveries.%I '
            'USING (organization_id = nullif(current_setting(''anarchi.current_organization_id'', true), '''')::uuid) '
            'WITH CHECK (organization_id = nullif(current_setting(''anarchi.current_organization_id'', true), '''')::uuid)',
            table_name
        );
        EXECUTE format('ALTER TABLE recoveries.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('ALTER TABLE recoveries.%I FORCE ROW LEVEL SECURITY', table_name);
        EXECUTE format('ALTER TABLE recoveries.%I OWNER TO recoveries_migration_role', table_name);
    END LOOP;
END
$tenant_policies$;

CREATE FUNCTION recoveries.enforce_payment_allocation_ceiling() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, recoveries
SET row_security = on
AS $function$
DECLARE
    target_organization_id uuid;
    target_project_id uuid;
    target_payment_id uuid;
    payment_amount numeric;
    payment_currency text;
    allocated_total numeric;
BEGIN
    IF TG_TABLE_NAME = 'recovery_payment_allocations' THEN
        IF TG_OP = 'DELETE' THEN
            target_organization_id := OLD.organization_id;
            target_project_id := OLD.project_id;
            target_payment_id := OLD.payment_id;
        ELSE
            target_organization_id := NEW.organization_id;
            target_project_id := NEW.project_id;
            target_payment_id := NEW.payment_id;
        END IF;
        SELECT amount, currency
        INTO payment_amount, payment_currency
        FROM recoveries.payments
        WHERE organization_id = target_organization_id
          AND project_id = target_project_id
          AND id = target_payment_id
        FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'allocation payment parent is missing' USING ERRCODE = '23503';
        END IF;
        IF TG_OP <> 'DELETE' AND NEW.currency IS DISTINCT FROM payment_currency THEN
            RAISE EXCEPTION 'allocation currency must match payment currency' USING ERRCODE = '23514';
        END IF;
        SELECT coalesce(sum(allocated_amount), 0)
        INTO allocated_total
        FROM recoveries.recovery_payment_allocations
        WHERE organization_id = target_organization_id
          AND project_id = target_project_id
          AND payment_id = target_payment_id;
        IF allocated_total > payment_amount THEN
            RAISE EXCEPTION 'attributable allocations exceed payment amount' USING ERRCODE = '23514';
        END IF;
    ELSIF TG_TABLE_NAME = 'payments' THEN
        target_organization_id := NEW.organization_id;
        target_project_id := NEW.project_id;
        target_payment_id := NEW.id;
        payment_amount := NEW.amount;
        payment_currency := NEW.currency;
        PERFORM 1
        FROM recoveries.payments
        WHERE organization_id = target_organization_id
          AND project_id = target_project_id
          AND id = target_payment_id
        FOR UPDATE;
        SELECT coalesce(sum(allocated_amount), 0)
        INTO allocated_total
        FROM recoveries.recovery_payment_allocations
        WHERE organization_id = target_organization_id
          AND project_id = target_project_id
          AND payment_id = target_payment_id;
        IF allocated_total > payment_amount THEN
            RAISE EXCEPTION 'payment reduction would exceed allocated amount' USING ERRCODE = '23514';
        END IF;
        IF EXISTS (
            SELECT 1 FROM recoveries.recovery_payment_allocations
            WHERE organization_id = target_organization_id
              AND project_id = target_project_id
              AND payment_id = target_payment_id
              AND currency IS DISTINCT FROM payment_currency
        ) THEN
            RAISE EXCEPTION 'payment currency conflicts with allocation currency' USING ERRCODE = '23514';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END
$function$;

CREATE FUNCTION recoveries.guard_allocation_identity() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, recoveries
AS $function$
BEGIN
    IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR NEW.project_id IS DISTINCT FROM OLD.project_id
       OR NEW.id IS DISTINCT FROM OLD.id
       OR NEW.payment_id IS DISTINCT FROM OLD.payment_id
       OR NEW.opportunity_id IS DISTINCT FROM OLD.opportunity_id
       OR NEW.currency IS DISTINCT FROM OLD.currency THEN
        RAISE EXCEPTION 'allocation identity is immutable' USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END
$function$;

CREATE CONSTRAINT TRIGGER allocation_ceiling_trigger
AFTER INSERT OR UPDATE OR DELETE ON recoveries.recovery_payment_allocations
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION recoveries.enforce_payment_allocation_ceiling();

CREATE CONSTRAINT TRIGGER payment_amount_ceiling_trigger
AFTER UPDATE OF amount, currency ON recoveries.payments
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION recoveries.enforce_payment_allocation_ceiling();

CREATE TRIGGER allocation_identity_guard
BEFORE UPDATE ON recoveries.recovery_payment_allocations
FOR EACH ROW EXECUTE FUNCTION recoveries.guard_allocation_identity();

CREATE FUNCTION recoveries.persist_observed_payment(
    p_organization_id uuid,
    p_project_id uuid,
    p_payment_id uuid,
    p_source_system text,
    p_external_id text,
    p_observed_at timestamptz,
    p_amount numeric,
    p_currency text,
    p_metadata jsonb,
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
    event_envelope jsonb;
BEGIN
    IF p_organization_id IS DISTINCT FROM nullif(
        current_setting('anarchi.current_organization_id', true), ''
    )::uuid THEN
        RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
    END IF;
    IF p_payment_id IS NULL OR p_observed_at IS NULL OR p_amount <= 0
       OR p_currency !~ '^[A-Z]{3}$' OR p_event_id IS NULL
       OR p_occurred_at IS NULL OR p_correlation_id IS NULL
       OR p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'payment observation is incomplete' USING ERRCODE = '22023';
    END IF;
    INSERT INTO recoveries.payments (
        organization_id, project_id, id, source_system, external_id,
        observed_at, amount, currency, metadata
    ) VALUES (
        p_organization_id, p_project_id, p_payment_id, p_source_system,
        p_external_id, p_observed_at, p_amount, p_currency,
        coalesce(p_metadata, '{}'::jsonb)
    ) ON CONFLICT (organization_id, id) DO NOTHING;
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.payments
        WHERE organization_id = p_organization_id
          AND project_id = p_project_id
          AND id = p_payment_id
          AND amount = p_amount
          AND currency = p_currency
          AND source_system = p_source_system
    ) THEN
        RAISE EXCEPTION 'payment replay conflicts with existing observation' USING ERRCODE = '23505';
    END IF;
    event_envelope := jsonb_build_object(
        'schema_version', '1.0', 'event_id', p_event_id::text,
        'event_type', 'payment.observed', 'organization_id', p_organization_id::text,
        'project_id', p_project_id::text, 'aggregate_id', p_payment_id::text,
        'occurred_at', to_char(p_occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'causation_id', CASE WHEN p_causation_id IS NULL THEN null::jsonb ELSE to_jsonb(p_causation_id::text) END,
        'correlation_id', p_correlation_id::text, 'idempotency_key', p_idempotency_key,
        'payload', jsonb_build_object(
            'source_system', p_source_system, 'external_id', p_external_id,
            'amount', p_amount, 'currency', p_currency, 'observed_at', p_observed_at
        )
    );
    INSERT INTO recoveries.transactional_outbox (
        organization_id, project_id, event_id, subject, aggregate_id,
        correlation_id, causation_id, idempotency_key, occurred_at,
        available_at, envelope, envelope_sha256
    ) VALUES (
        p_organization_id, p_project_id, p_event_id, 'payment.observed.v1',
        p_payment_id, p_correlation_id, p_causation_id, p_idempotency_key,
        p_occurred_at, p_occurred_at, event_envelope,
        encode(public.digest(convert_to(event_envelope::text, 'UTF8'), 'sha256'), 'hex')
    ) ON CONFLICT (organization_id, event_id) DO NOTHING;
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.transactional_outbox
        WHERE organization_id = p_organization_id
          AND event_id = p_event_id
          AND envelope = event_envelope
    ) THEN
        RAISE EXCEPTION 'payment event replay conflicts with existing event' USING ERRCODE = '23505';
    END IF;
    RETURN p_payment_id;
END
$function$;

CREATE FUNCTION recoveries.persist_attribution_and_fee(
    p_organization_id uuid,
    p_project_id uuid,
    p_payment_id uuid,
    p_opportunity_id uuid,
    p_allocation_id uuid,
    p_allocation_amount numeric,
    p_currency text,
    p_attribution_hash text,
    p_canonical_result text,
    p_attribution_record jsonb,
    p_attribution_audit_id uuid,
    p_attribution_event_id uuid,
    p_fee_accrual_id uuid,
    p_fee_event_id uuid,
    p_occurred_at timestamptz,
    p_causation_id uuid,
    p_correlation_id uuid,
    p_attribution_idempotency_key text,
    p_fee_idempotency_key text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, recoveries
SET row_security = on
AS $function$
DECLARE
    result jsonb;
    record_currency text;
    fee_rate numeric;
    fee_base numeric;
    accrual_fee_amount numeric;
    record_cash numeric;
    event_envelope jsonb;
    payment_amount numeric;
    payment_currency text;
BEGIN
    IF p_organization_id IS DISTINCT FROM nullif(
        current_setting('anarchi.current_organization_id', true), ''
    )::uuid THEN
        RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
    END IF;
    IF p_allocation_id IS NULL OR p_allocation_amount <= 0
       OR p_currency !~ '^[A-Z]{3}$' OR p_attribution_hash !~ '^[a-f0-9]{64}$'
       OR p_canonical_result IS NULL OR btrim(p_canonical_result) = ''
       OR p_attribution_record IS NULL
       OR p_attribution_audit_id IS NULL OR p_attribution_event_id IS NULL
       OR p_occurred_at IS NULL OR p_correlation_id IS NULL
       OR p_attribution_idempotency_key IS NULL OR btrim(p_attribution_idempotency_key) = '' THEN
        RAISE EXCEPTION 'attribution persistence identity is incomplete' USING ERRCODE = '22023';
    END IF;
    IF p_attribution_record ->> 'canonicalization' <> 'ANARCHI-JCS-COMPATIBLE-V1'
       OR p_attribution_record ->> 'attribution_hash' IS DISTINCT FROM p_attribution_hash
       OR jsonb_typeof(p_attribution_record -> 'result') IS DISTINCT FROM 'object'
       OR (p_attribution_record -> 'result')::text IS DISTINCT FROM p_canonical_result
       OR encode(public.digest(convert_to(p_canonical_result, 'UTF8'), 'sha256'), 'hex')
          IS DISTINCT FROM p_attribution_hash THEN
        RAISE EXCEPTION 'attribution record hash mismatch' USING ERRCODE = '22023';
    END IF;
    SELECT amount, currency INTO payment_amount, payment_currency
    FROM recoveries.payments
    WHERE organization_id = p_organization_id
      AND project_id = p_project_id
      AND id = p_payment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'payment parent is missing' USING ERRCODE = '23503';
    END IF;
    IF payment_currency IS DISTINCT FROM p_currency OR p_allocation_amount > payment_amount THEN
        RAISE EXCEPTION 'allocation exceeds payment or crosses currency boundary' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.recovery_opportunities
        WHERE organization_id = p_organization_id
          AND project_id = p_project_id
          AND id = p_opportunity_id
    ) THEN
        RAISE EXCEPTION 'opportunity parent is missing' USING ERRCODE = '23503';
    END IF;
    result := p_attribution_record -> 'result';
    record_currency := result ->> 'currency';
    fee_rate := (result ->> 'success_fee_rate_percent')::numeric;
    fee_base := (result ->> 'success_fee_base')::numeric;
    accrual_fee_amount := (result ->> 'success_fee')::numeric;
    record_cash := (result ->> 'attributable_cash_received')::numeric;
    IF record_currency IS DISTINCT FROM p_currency
       OR (result ->> 'money_scale')::integer <> 2
       OR result ->> 'rounding_mode' <> 'MIDPOINT_AWAY_FROM_ZERO'
       OR fee_rate < 0 OR fee_rate > 100
       OR fee_base < 0 OR accrual_fee_amount < 0
       OR fee_base IS DISTINCT FROM p_allocation_amount
       OR record_cash < fee_base
       OR accrual_fee_amount IS DISTINCT FROM round(fee_base * fee_rate / 100, 2) THEN
        RAISE EXCEPTION 'attribution result does not match allocation and fee rules' USING ERRCODE = '23514';
    END IF;

    INSERT INTO recoveries.recovery_payment_allocations (
        organization_id, project_id, id, payment_id, opportunity_id,
        allocated_amount, currency
    ) VALUES (
        p_organization_id, p_project_id, p_allocation_id, p_payment_id,
        p_opportunity_id, p_allocation_amount, p_currency
    ) ON CONFLICT (organization_id, id) DO NOTHING;
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.recovery_payment_allocations
        WHERE organization_id = p_organization_id
          AND project_id = p_project_id
          AND id = p_allocation_id
          AND payment_id = p_payment_id
          AND opportunity_id = p_opportunity_id
          AND allocated_amount = p_allocation_amount
          AND currency = p_currency
    ) THEN
        RAISE EXCEPTION 'allocation replay conflicts with existing allocation' USING ERRCODE = '23505';
    END IF;
    INSERT INTO recoveries.audit_events (
        organization_id, project_id, id, event_type, actor_type, actor_id,
        aggregate_type, aggregate_id, details, occurred_at
    ) VALUES (
        p_organization_id, p_project_id, p_attribution_audit_id, 'attribution.reconciled',
        'SERVICE', 'billing-worker', 'RECOVERY_OPPORTUNITY', p_opportunity_id,
        jsonb_build_object(
            'payment_id', p_payment_id, 'allocation_id', p_allocation_id,
            'allocated_amount', p_allocation_amount, 'currency', p_currency,
            'attribution_hash', p_attribution_hash,
            'canonical_result', p_canonical_result,
            'attribution_record', p_attribution_record
        ), p_occurred_at
    ) ON CONFLICT (organization_id, id) DO NOTHING;
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.audit_events
        WHERE organization_id = p_organization_id
          AND id = p_attribution_audit_id
          AND details ->> 'attribution_hash' = p_attribution_hash
    ) THEN
        RAISE EXCEPTION 'attribution audit replay conflicts with existing receipt' USING ERRCODE = '23505';
    END IF;
    event_envelope := jsonb_build_object(
        'schema_version', '1.0', 'event_id', p_attribution_event_id::text,
        'event_type', 'attribution.reconciled', 'organization_id', p_organization_id::text,
        'project_id', p_project_id::text, 'aggregate_id', p_opportunity_id::text,
        'occurred_at', to_char(p_occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'causation_id', CASE WHEN p_causation_id IS NULL THEN null::jsonb ELSE to_jsonb(p_causation_id::text) END,
        'correlation_id', p_correlation_id::text, 'idempotency_key', p_attribution_idempotency_key,
        'payload', jsonb_build_object(
            'payment_id', p_payment_id, 'allocation_id', p_allocation_id,
            'allocated_amount', p_allocation_amount, 'currency', p_currency,
            'attribution_hash', p_attribution_hash
        )
    );
    INSERT INTO recoveries.transactional_outbox (
        organization_id, project_id, event_id, subject, aggregate_id,
        correlation_id, causation_id, idempotency_key, occurred_at,
        available_at, envelope, envelope_sha256
    ) VALUES (
        p_organization_id, p_project_id, p_attribution_event_id, 'attribution.reconciled.v1',
        p_opportunity_id, p_correlation_id, p_causation_id, p_attribution_idempotency_key,
        p_occurred_at, p_occurred_at, event_envelope,
        encode(public.digest(convert_to(event_envelope::text, 'UTF8'), 'sha256'), 'hex')
    ) ON CONFLICT (organization_id, event_id) DO NOTHING;
    IF NOT EXISTS (
        SELECT 1 FROM recoveries.transactional_outbox
        WHERE organization_id = p_organization_id
          AND event_id = p_attribution_event_id
          AND envelope = event_envelope
    ) THEN
        RAISE EXCEPTION 'attribution event replay conflicts with existing event' USING ERRCODE = '23505';
    END IF;

    IF accrual_fee_amount > 0 THEN
        IF p_fee_accrual_id IS NULL OR p_fee_event_id IS NULL
           OR p_fee_idempotency_key IS NULL OR btrim(p_fee_idempotency_key) = '' THEN
            RAISE EXCEPTION 'fee event identity is required for a positive fee' USING ERRCODE = '22023';
        END IF;
        INSERT INTO recoveries.success_fee_accruals (
            organization_id, project_id, id, allocation_id, payment_id,
            opportunity_id, attribution_rule_version, fee_rate_percent,
            fee_base, fee_amount, currency, accrued_at
        ) VALUES (
            p_organization_id, p_project_id, p_fee_accrual_id, p_allocation_id,
            p_payment_id, p_opportunity_id, result ->> 'attribution_rule_version',
            fee_rate, fee_base, accrual_fee_amount, p_currency, p_occurred_at
        ) ON CONFLICT (organization_id, id) DO NOTHING;
        IF NOT EXISTS (
            SELECT 1 FROM recoveries.success_fee_accruals AS existing_accrual
            WHERE organization_id = p_organization_id
              AND project_id = p_project_id
              AND id = p_fee_accrual_id
              AND allocation_id = p_allocation_id
              AND existing_accrual.fee_amount = accrual_fee_amount
        ) THEN
            RAISE EXCEPTION 'fee accrual replay conflicts with existing accrual' USING ERRCODE = '23505';
        END IF;
        INSERT INTO recoveries.audit_events (
            organization_id, project_id, id, event_type, actor_type, actor_id,
            aggregate_type, aggregate_id, details, occurred_at
        ) VALUES (
            p_organization_id, p_project_id, p_fee_event_id, 'billing.success_fee.accrued',
            'SERVICE', 'billing-worker', 'SUCCESS_FEE_ACCRUAL', p_fee_accrual_id,
            jsonb_build_object(
                'allocation_id', p_allocation_id, 'payment_id', p_payment_id,
                'opportunity_id', p_opportunity_id, 'fee_base', fee_base,
                'fee_amount', accrual_fee_amount, 'fee_rate_percent', fee_rate,
                'currency', p_currency, 'attribution_hash', p_attribution_hash
            ), p_occurred_at
        ) ON CONFLICT (organization_id, id) DO NOTHING;
        event_envelope := jsonb_build_object(
            'schema_version', '1.0', 'event_id', p_fee_event_id::text,
            'event_type', 'billing.success_fee.accrued', 'organization_id', p_organization_id::text,
            'project_id', p_project_id::text, 'aggregate_id', p_opportunity_id::text,
            'occurred_at', to_char(p_occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
            'causation_id', CASE WHEN p_causation_id IS NULL THEN null::jsonb ELSE to_jsonb(p_causation_id::text) END,
            'correlation_id', p_correlation_id::text, 'idempotency_key', p_fee_idempotency_key,
            'payload', jsonb_build_object(
                'accrual_id', p_fee_accrual_id, 'allocation_id', p_allocation_id,
                'fee_base', fee_base, 'fee_amount', accrual_fee_amount,
                'currency', p_currency, 'attribution_hash', p_attribution_hash
            )
        );
        INSERT INTO recoveries.transactional_outbox (
            organization_id, project_id, event_id, subject, aggregate_id,
            correlation_id, causation_id, idempotency_key, occurred_at,
            available_at, envelope, envelope_sha256
        ) VALUES (
            p_organization_id, p_project_id, p_fee_event_id, 'billing.success_fee.accrued.v1',
            p_opportunity_id, p_correlation_id, p_causation_id, p_fee_idempotency_key,
            p_occurred_at, p_occurred_at, event_envelope,
            encode(public.digest(convert_to(event_envelope::text, 'UTF8'), 'sha256'), 'hex')
        ) ON CONFLICT (organization_id, event_id) DO NOTHING;
        IF NOT EXISTS (
            SELECT 1 FROM recoveries.transactional_outbox
            WHERE organization_id = p_organization_id
              AND event_id = p_fee_event_id
              AND envelope = event_envelope
        ) THEN
            RAISE EXCEPTION 'fee event replay conflicts with existing event' USING ERRCODE = '23505';
        END IF;
    END IF;
    RETURN p_allocation_id;
END
$function$;

REVOKE INSERT, UPDATE, DELETE ON recoveries.payments,
    recoveries.recovery_payment_allocations, recoveries.success_fee_accruals
    FROM recoveries_runtime_role;
GRANT USAGE ON SCHEMA recoveries TO recoveries_billing_role;
REVOKE ALL ON FUNCTION recoveries.persist_observed_payment(
    uuid, uuid, uuid, text, text, timestamptz, numeric, text, jsonb,
    uuid, timestamptz, uuid, uuid, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION recoveries.persist_observed_payment(
    uuid, uuid, uuid, text, text, timestamptz, numeric, text, jsonb,
    uuid, timestamptz, uuid, uuid, text
) TO recoveries_billing_role;
REVOKE ALL ON FUNCTION recoveries.persist_attribution_and_fee(
    uuid, uuid, uuid, uuid, uuid, numeric, text, text, text, jsonb,
    uuid, uuid, uuid, uuid, timestamptz, uuid, uuid, text, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION recoveries.persist_attribution_and_fee(
    uuid, uuid, uuid, uuid, uuid, numeric, text, text, text, jsonb,
    uuid, uuid, uuid, uuid, timestamptz, uuid, uuid, text, text
) TO recoveries_billing_role;
GRANT SELECT ON recoveries.payments,
    recoveries.recovery_payment_allocations, recoveries.success_fee_accruals
    TO recoveries_runtime_role;

COMMIT;
