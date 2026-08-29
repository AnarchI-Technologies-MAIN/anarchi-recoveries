\set ON_ERROR_STOP on

DO $proof$
DECLARE
    missing_tables text[];
BEGIN
    SELECT array_agg(required.table_name ORDER BY required.table_name)
    INTO missing_tables
    FROM (
        VALUES
            ('organizations'), ('users'), ('external_identities'),
            ('organization_memberships'), ('projects'), ('evidence'),
            ('contract_baselines'), ('baseline_evidence'), ('scope_items'),
            ('scope_item_versions'), ('facts'), ('project_events'),
            ('recovery_opportunities'), ('opportunity_facts'),
            ('opportunity_evidence'), ('pricing_calculations'), ('pricing_lines')
    ) AS required(table_name)
    WHERE to_regclass('recoveries.' || required.table_name) IS NULL;

    IF missing_tables IS NOT NULL THEN
        RAISE EXCEPTION 'missing required tables: %', missing_tables;
    END IF;
END
$proof$;

SELECT 'foundation_tables' AS proof, 'PASS' AS result, count(*) AS observed
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'recoveries' AND c.relkind = 'r';

SELECT 'migration_digests' AS proof, 'PASS' AS result, count(*) AS observed
FROM recoveries.schema_migrations;
