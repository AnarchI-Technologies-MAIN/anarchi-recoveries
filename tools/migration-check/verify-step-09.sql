\set ON_ERROR_STOP on

BEGIN;

INSERT INTO recoveries.organizations (id, legal_name) VALUES
    ('00000000-0000-4000-8000-000000000901', 'Identity Tenant A'),
    ('00000000-0000-4000-8000-000000000902', 'Identity Tenant B');

INSERT INTO recoveries.users (id, display_name) VALUES
    ('00000000-0000-4000-8000-000000000903', 'Identity Proof User');

INSERT INTO recoveries.external_identities (
    id, user_id, external_iss, external_sub
) VALUES (
    '00000000-0000-4000-8000-000000000904',
    '00000000-0000-4000-8000-000000000903',
    'https://identity.example.test',
    'external-user-1'
);

INSERT INTO recoveries.organization_memberships (
    organization_id, user_id, external_identity_id, role, status
) VALUES (
    '00000000-0000-4000-8000-000000000901',
    '00000000-0000-4000-8000-000000000903',
    '00000000-0000-4000-8000-000000000904',
    'PM',
    'ACTIVE'
);

SET LOCAL ROLE recoveries_runtime_role;

DO $identity_proof$
DECLARE
    context recoveries.identity_context;
BEGIN
    SELECT * INTO STRICT context
    FROM recoveries.establish_identity_context(
        'https://identity.example.test',
        'external-user-1',
        '00000000-0000-4000-8000-000000000901'
    );

    IF context.user_id <> '00000000-0000-4000-8000-000000000903'
       OR context.organization_id <> '00000000-0000-4000-8000-000000000901'
       OR context.membership_role <> 'PM' THEN
        RAISE EXCEPTION 'resolved internal identity context is incorrect';
    END IF;

    IF current_setting('anarchi.current_organization_id', true)
       <> '00000000-0000-4000-8000-000000000901'
       OR current_setting('anarchi.current_user_id', true)
       <> '00000000-0000-4000-8000-000000000903' THEN
        RAISE EXCEPTION 'identity function did not establish internal RLS context';
    END IF;

    BEGIN
        PERFORM recoveries.establish_identity_context(
            'https://identity.example.test',
            'external-user-1',
            '00000000-0000-4000-8000-000000000902'
        );
        RAISE EXCEPTION 'external identity selected an organization without active membership';
    EXCEPTION
        WHEN invalid_authorization_specification THEN NULL;
    END;

    BEGIN
        PERFORM recoveries.establish_identity_context(
            'https://attacker.example',
            'external-user-1',
            '00000000-0000-4000-8000-000000000901'
        );
        RAISE EXCEPTION 'unknown issuer selected an internal identity';
    EXCEPTION
        WHEN invalid_authorization_specification THEN NULL;
    END;
END
$identity_proof$;

RESET ROLE;

DO $ownership_proof$
BEGIN
    IF (
        SELECT owner_role.rolname
        FROM pg_proc function
        JOIN pg_namespace namespace ON namespace.oid = function.pronamespace
        JOIN pg_roles owner_role ON owner_role.oid = function.proowner
        WHERE namespace.nspname = 'recoveries'
          AND function.proname = 'establish_identity_context'
    ) <> 'recoveries_migration_role' THEN
        RAISE EXCEPTION 'identity context function is not owned by migration role';
    END IF;
END
$ownership_proof$;

SELECT 'verified_pair_resolves_internal_user' AS proof, 'PASS' AS result;
SELECT 'active_membership_selects_internal_org' AS proof, 'PASS' AS result;
SELECT 'external_org_not_tenant_authority' AS proof, 'PASS' AS result;
SELECT 'identity_function_owner_boundary' AS proof, 'PASS' AS result;

ROLLBACK;
