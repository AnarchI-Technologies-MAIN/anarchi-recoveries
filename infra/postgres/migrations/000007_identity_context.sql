BEGIN;

CREATE TYPE recoveries.identity_context AS (
    user_id uuid,
    organization_id uuid,
    membership_role text
);

CREATE FUNCTION recoveries.establish_identity_context(
    p_external_iss text,
    p_external_sub text,
    p_requested_organization_id uuid
) RETURNS recoveries.identity_context
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, recoveries
AS $function$
DECLARE
    resolved_user_id uuid;
    resolved_role text;
    context recoveries.identity_context;
BEGIN
    IF p_external_iss IS NULL OR btrim(p_external_iss) = ''
       OR p_external_sub IS NULL OR btrim(p_external_sub) = ''
       OR p_requested_organization_id IS NULL THEN
        RAISE EXCEPTION 'verified issuer, subject, and requested internal organization are required'
            USING ERRCODE = '28000';
    END IF;

    SELECT identity.user_id
    INTO STRICT resolved_user_id
    FROM recoveries.external_identities AS identity
    WHERE identity.external_iss = p_external_iss
      AND identity.external_sub = p_external_sub;

    PERFORM set_config(
        'anarchi.current_organization_id',
        p_requested_organization_id::text,
        true
    );

    SELECT membership.role
    INTO STRICT resolved_role
    FROM recoveries.organization_memberships AS membership
    WHERE membership.organization_id = p_requested_organization_id
      AND membership.user_id = resolved_user_id
      AND membership.status = 'ACTIVE';

    PERFORM set_config('anarchi.current_user_id', resolved_user_id::text, true);

    context.user_id := resolved_user_id;
    context.organization_id := p_requested_organization_id;
    context.membership_role := resolved_role;
    RETURN context;
EXCEPTION
    WHEN no_data_found THEN
        RAISE EXCEPTION 'verified external identity has no active membership in requested organization'
            USING ERRCODE = '28000';
    WHEN too_many_rows THEN
        RAISE EXCEPTION 'identity mapping is ambiguous'
            USING ERRCODE = '28000';
END
$function$;

REVOKE ALL ON FUNCTION recoveries.establish_identity_context(text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION recoveries.establish_identity_context(text, text, uuid)
    TO recoveries_runtime_role;

COMMIT;
