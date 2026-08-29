\set ON_ERROR_STOP on

BEGIN;

DO $catalog_proof$
DECLARE
    tenant_table_count integer;
    forced_rls_count integer;
    unsafe_fk_count integer;
    wrong_owner_count integer;
BEGIN
    SELECT count(*)
    INTO tenant_table_count
    FROM information_schema.columns
    WHERE table_schema = 'recoveries'
      AND column_name = 'organization_id';

    SELECT count(*)
    INTO forced_rls_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'recoveries'
      AND c.relkind = 'r'
      AND (c.relname = 'organizations' OR EXISTS (
          SELECT 1
          FROM information_schema.columns cols
          WHERE cols.table_schema = n.nspname
            AND cols.table_name = c.relname
            AND cols.column_name = 'organization_id'
      ))
      AND c.relrowsecurity
      AND c.relforcerowsecurity;

    IF forced_rls_count <> tenant_table_count + 1 THEN
        RAISE EXCEPTION 'forced RLS mismatch: expected %, observed %',
            tenant_table_count + 1, forced_rls_count;
    END IF;

    SELECT count(*)
    INTO unsafe_fk_count
    FROM pg_constraint fk
    JOIN pg_class child ON child.oid = fk.conrelid
    JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
    JOIN pg_class parent ON parent.oid = fk.confrelid
    JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
    WHERE fk.contype = 'f'
      AND child_ns.nspname = 'recoveries'
      AND parent_ns.nspname = 'recoveries'
      AND EXISTS (
          SELECT 1 FROM pg_attribute
          WHERE attrelid = child.oid AND attname = 'organization_id' AND NOT attisdropped
      )
      AND EXISTS (
          SELECT 1 FROM pg_attribute
          WHERE attrelid = parent.oid AND attname = 'organization_id' AND NOT attisdropped
      )
      AND NOT EXISTS (
          SELECT 1
          FROM unnest(fk.conkey) AS key(attnum)
          JOIN pg_attribute attr ON attr.attrelid = child.oid AND attr.attnum = key.attnum
          WHERE attr.attname = 'organization_id'
      );

    IF unsafe_fk_count <> 0 THEN
        RAISE EXCEPTION 'tenant-aware composite FK audit found % unsafe constraints', unsafe_fk_count;
    END IF;

    SELECT count(*)
    INTO wrong_owner_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_roles owner_role ON owner_role.oid = c.relowner
    WHERE n.nspname = 'recoveries'
      AND c.relkind IN ('r', 'p', 'S')
      AND owner_role.rolname <> 'recoveries_migration_role';

    IF wrong_owner_count <> 0 THEN
        RAISE EXCEPTION '% Recoveries relations are not owned by the migration role', wrong_owner_count;
    END IF;

    IF (
        SELECT owner_role.rolname
        FROM pg_namespace n
        JOIN pg_roles owner_role ON owner_role.oid = n.nspowner
        WHERE n.nspname = 'recoveries'
    ) <> 'recoveries_migration_role' THEN
        RAISE EXCEPTION 'Recoveries schema is not owned by the migration role';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'recoveries_runtime_role'
          AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls OR rolcanlogin)
    ) THEN
        RAISE EXCEPTION 'runtime role has a forbidden capability';
    END IF;

    IF has_table_privilege('recoveries_runtime_role', 'recoveries.users', 'SELECT')
       OR has_table_privilege('recoveries_runtime_role', 'recoveries.external_identities', 'SELECT')
       OR has_table_privilege('recoveries_runtime_role', 'recoveries.schema_migrations', 'SELECT') THEN
        RAISE EXCEPTION 'runtime role can read a global identity or migration-ledger table';
    END IF;
END
$catalog_proof$;

INSERT INTO recoveries.organizations (id, legal_name) VALUES
    ('00000000-0000-4000-8000-000000000801', 'Tenant A'),
    ('00000000-0000-4000-8000-000000000802', 'Tenant B');

INSERT INTO recoveries.projects (
    id, organization_id, project_number, name, timezone, currency
) VALUES
    ('00000000-0000-4000-8000-000000000811', '00000000-0000-4000-8000-000000000801',
     'A-1', 'Tenant A Project', 'America/Chicago', 'USD'),
    ('00000000-0000-4000-8000-000000000812', '00000000-0000-4000-8000-000000000802',
     'B-1', 'Tenant B Project', 'America/Chicago', 'USD');

SET LOCAL ROLE recoveries_runtime_role;

DO $unset_context$
BEGIN
    IF (SELECT count(*) FROM recoveries.projects) <> 0 THEN
        RAISE EXCEPTION 'runtime role observed tenant rows without organization context';
    END IF;

    BEGIN
        INSERT INTO recoveries.projects (
            id, organization_id, project_number, name, timezone, currency
        ) VALUES (
            '00000000-0000-4000-8000-000000000813',
            '00000000-0000-4000-8000-000000000801',
            'A-UNSET', 'Unset Context Project', 'America/Chicago', 'USD'
        );
        RAISE EXCEPTION 'runtime insert succeeded without organization context';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
    END;
END
$unset_context$;

SELECT set_config('anarchi.current_organization_id', '00000000-0000-4000-8000-000000000801', true);

DO $tenant_a_context$
BEGIN
    IF (SELECT count(*) FROM recoveries.projects) <> 1 THEN
        RAISE EXCEPTION 'tenant A context did not observe exactly one project';
    END IF;

    IF EXISTS (
        SELECT 1 FROM recoveries.projects
        WHERE organization_id = '00000000-0000-4000-8000-000000000802'
    ) THEN
        RAISE EXCEPTION 'tenant A context observed tenant B project';
    END IF;

    BEGIN
        INSERT INTO recoveries.projects (
            id, organization_id, project_number, name, timezone, currency
        ) VALUES (
            '00000000-0000-4000-8000-000000000814',
            '00000000-0000-4000-8000-000000000802',
            'B-CROSS', 'Cross Tenant Project', 'America/Chicago', 'USD'
        );
        RAISE EXCEPTION 'tenant A context inserted a tenant B row';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
    END;
END
$tenant_a_context$;

RESET ROLE;

DO $composite_fk_proof$
BEGIN
    BEGIN
        INSERT INTO recoveries.evidence (
            organization_id, project_id, id, source_system, source_version,
            source_observed_at, object_uri, original_filename, mime_type, size_bytes, sha256
        ) VALUES (
            '00000000-0000-4000-8000-000000000801',
            '00000000-0000-4000-8000-000000000812',
            '00000000-0000-4000-8000-000000000815',
            'PROOF', 'v1', '2026-08-29T00:00:00Z',
            's3://proof/org/00000000-0000-4000-8000-000000000801/project/00000000-0000-4000-8000-000000000812/evidence/00000000-0000-4000-8000-000000000815/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/cross.txt',
            'cross.txt', 'text/plain', 1, repeat('a', 64)
        );
        RAISE EXCEPTION 'cross-tenant composite foreign key accepted mismatched project authority';
    EXCEPTION
        WHEN foreign_key_violation THEN NULL;
    END;
END
$composite_fk_proof$;

SELECT 'forced_rls_all_tenant_tables' AS proof, 'PASS' AS result;
SELECT 'unset_context_fails_closed' AS proof, 'PASS' AS result;
SELECT 'tenant_a_cannot_read_or_write_tenant_b' AS proof, 'PASS' AS result;
SELECT 'runtime_role_non_bypass' AS proof, 'PASS' AS result;
SELECT 'migration_owner_separation' AS proof, 'PASS' AS result;
SELECT 'tenant_composite_fk_audit' AS proof, 'PASS' AS result;

ROLLBACK;
