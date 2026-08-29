BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS recoveries;

CREATE TABLE recoveries.schema_migrations (
    version text PRIMARY KEY,
    sha256 text NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
    applied_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);

COMMIT;
