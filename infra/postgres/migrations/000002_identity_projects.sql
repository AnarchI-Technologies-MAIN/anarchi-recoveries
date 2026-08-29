BEGIN;

CREATE TABLE recoveries.organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    legal_name text NOT NULL CHECK (btrim(legal_name) <> ''),
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'SUSPENDED', 'TERMINATED')),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    UNIQUE (id)
);

CREATE TABLE recoveries.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name text NOT NULL CHECK (btrim(display_name) <> ''),
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'SUSPENDED', 'TERMINATED')),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);

CREATE TABLE recoveries.external_identities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES recoveries.users(id) ON DELETE RESTRICT,
    external_iss text NOT NULL CHECK (btrim(external_iss) <> ''),
    external_sub text NOT NULL CHECK (btrim(external_sub) <> ''),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    UNIQUE (external_iss, external_sub),
    UNIQUE (id, user_id)
);

CREATE TABLE recoveries.organization_memberships (
    organization_id uuid NOT NULL REFERENCES recoveries.organizations(id) ON DELETE RESTRICT,
    user_id uuid NOT NULL REFERENCES recoveries.users(id) ON DELETE RESTRICT,
    external_identity_id uuid NOT NULL,
    role text NOT NULL CHECK (role IN ('OWNER', 'ADMIN', 'PM', 'REVIEWER', 'VIEWER')),
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('INVITED', 'ACTIVE', 'SUSPENDED', 'REVOKED')),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, user_id),
    FOREIGN KEY (external_identity_id, user_id)
        REFERENCES recoveries.external_identities(id, user_id) ON DELETE RESTRICT
);

CREATE TABLE recoveries.projects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES recoveries.organizations(id) ON DELETE RESTRICT,
    project_number text NOT NULL CHECK (btrim(project_number) <> ''),
    name text NOT NULL CHECK (btrim(name) <> ''),
    timezone text NOT NULL CHECK (btrim(timezone) <> ''),
    currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('DRAFT', 'ACTIVE', 'CLOSED', 'ARCHIVED')),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    UNIQUE (organization_id, project_number),
    UNIQUE (organization_id, id)
);

COMMIT;
