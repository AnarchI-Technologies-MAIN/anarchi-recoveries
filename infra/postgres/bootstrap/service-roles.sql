\set ON_ERROR_STOP on

DO $roles$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'recoveries_outbox_publisher_role') THEN
        CREATE ROLE recoveries_outbox_publisher_role
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'recoveries_extraction_role') THEN
        CREATE ROLE recoveries_extraction_role
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'recoveries_migration_role') THEN
        GRANT recoveries_outbox_publisher_role TO recoveries_migration_role;
        GRANT recoveries_extraction_role TO recoveries_migration_role;
    END IF;
END
$roles$;
