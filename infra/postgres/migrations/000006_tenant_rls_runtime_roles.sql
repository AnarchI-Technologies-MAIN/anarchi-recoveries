BEGIN;

DO $roles$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'recoveries_migration_role') THEN
        CREATE ROLE recoveries_migration_role
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'recoveries_runtime_role') THEN
        CREATE ROLE recoveries_runtime_role
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
    END IF;

    EXECUTE format('GRANT recoveries_migration_role TO %I', session_user);
    GRANT recoveries_runtime_role TO recoveries_migration_role;
END
$roles$;

CREATE POLICY organization_tenant_isolation ON recoveries.organizations
    USING (id = nullif(current_setting('anarchi.current_organization_id', true), '')::uuid)
    WITH CHECK (id = nullif(current_setting('anarchi.current_organization_id', true), '')::uuid);

ALTER TABLE recoveries.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE recoveries.organizations FORCE ROW LEVEL SECURITY;

DO $tenant_policies$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'organization_memberships',
        'projects',
        'evidence',
        'contract_baselines',
        'baseline_evidence',
        'scope_items',
        'scope_item_versions',
        'facts',
        'project_events',
        'recovery_opportunities',
        'opportunity_facts',
        'opportunity_evidence',
        'pricing_calculations',
        'pricing_lines',
        'fx_conversions'
    ] LOOP
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON recoveries.%I '
            'USING (organization_id = nullif(current_setting(''anarchi.current_organization_id'', true), '''')::uuid) '
            'WITH CHECK (organization_id = nullif(current_setting(''anarchi.current_organization_id'', true), '''')::uuid)',
            table_name
        );
        EXECUTE format('ALTER TABLE recoveries.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('ALTER TABLE recoveries.%I FORCE ROW LEVEL SECURITY', table_name);
    END LOOP;
END
$tenant_policies$;

REVOKE ALL ON SCHEMA recoveries FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA recoveries FROM PUBLIC;
GRANT USAGE ON SCHEMA recoveries TO recoveries_runtime_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
    recoveries.organizations,
    recoveries.organization_memberships,
    recoveries.projects,
    recoveries.evidence,
    recoveries.contract_baselines,
    recoveries.baseline_evidence,
    recoveries.scope_items,
    recoveries.scope_item_versions,
    recoveries.facts,
    recoveries.project_events,
    recoveries.recovery_opportunities,
    recoveries.opportunity_facts,
    recoveries.opportunity_evidence,
    recoveries.pricing_calculations,
    recoveries.pricing_lines,
    recoveries.fx_conversions
TO recoveries_runtime_role;

ALTER SCHEMA recoveries OWNER TO recoveries_migration_role;

DO $ownership$
DECLARE
    relation record;
BEGIN
    FOR relation IN
        SELECT c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'recoveries'
          AND c.relkind IN ('r', 'p', 'S')
        ORDER BY c.relname
    LOOP
        EXECUTE format('ALTER TABLE recoveries.%I OWNER TO recoveries_migration_role', relation.relname);
    END LOOP;
END
$ownership$;

ALTER DEFAULT PRIVILEGES FOR ROLE recoveries_migration_role IN SCHEMA recoveries
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE recoveries_migration_role IN SCHEMA recoveries
    REVOKE ALL ON SEQUENCES FROM PUBLIC;

COMMIT;
