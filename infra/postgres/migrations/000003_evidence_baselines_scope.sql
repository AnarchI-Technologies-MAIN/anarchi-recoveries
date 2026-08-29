BEGIN;

CREATE TABLE recoveries.evidence (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    source_system text NOT NULL CHECK (btrim(source_system) <> ''),
    external_id text,
    source_version text NOT NULL CHECK (btrim(source_version) <> ''),
    source_observed_at timestamptz NOT NULL,
    object_uri text NOT NULL CHECK (btrim(object_uri) <> ''),
    original_filename text NOT NULL CHECK (btrim(original_filename) <> ''),
    mime_type text NOT NULL CHECK (btrim(mime_type) <> ''),
    size_bytes bigint NOT NULL CHECK (size_bytes >= 0),
    sha256 text NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
    previous_version_id uuid,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    UNIQUE (organization_id, project_id, sha256),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES recoveries.projects(organization_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, previous_version_id)
        REFERENCES recoveries.evidence(organization_id, id) ON DELETE RESTRICT,
    CHECK (previous_version_id IS NULL OR previous_version_id <> id)
);

CREATE TABLE recoveries.contract_baselines (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    version integer NOT NULL CHECK (version > 0),
    status text NOT NULL CHECK (status IN ('DRAFT', 'ACTIVE', 'SUPERSEDED')),
    compiled_at timestamptz,
    compiled_by uuid REFERENCES recoveries.users(id) ON DELETE RESTRICT,
    canonical_sha256 text CHECK (canonical_sha256 IS NULL OR canonical_sha256 ~ '^[a-f0-9]{64}$'),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    UNIQUE (organization_id, project_id, version),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES recoveries.projects(organization_id, id) ON DELETE RESTRICT,
    CHECK ((status = 'DRAFT') OR (compiled_at IS NOT NULL AND canonical_sha256 IS NOT NULL))
);

CREATE TABLE recoveries.baseline_evidence (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    baseline_id uuid NOT NULL,
    evidence_id uuid NOT NULL,
    purpose text NOT NULL CHECK (btrim(purpose) <> ''),
    PRIMARY KEY (organization_id, baseline_id, evidence_id),
    FOREIGN KEY (organization_id, project_id, baseline_id)
        REFERENCES recoveries.contract_baselines(organization_id, project_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, project_id, evidence_id)
        REFERENCES recoveries.evidence(organization_id, project_id, id) ON DELETE RESTRICT
);

CREATE TABLE recoveries.scope_items (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    stable_key text NOT NULL CHECK (btrim(stable_key) <> ''),
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, id),
    UNIQUE (organization_id, project_id, id),
    UNIQUE (organization_id, project_id, stable_key),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES recoveries.projects(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE recoveries.scope_item_versions (
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    scope_item_id uuid NOT NULL,
    valid_from_baseline_version integer NOT NULL CHECK (valid_from_baseline_version > 0),
    valid_to_baseline_version integer,
    quantity numeric(30, 10),
    unit text,
    description text NOT NULL CHECK (btrim(description) <> ''),
    source_evidence_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
    PRIMARY KEY (organization_id, scope_item_id, valid_from_baseline_version),
    FOREIGN KEY (organization_id, project_id, scope_item_id)
        REFERENCES recoveries.scope_items(organization_id, project_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, project_id, source_evidence_id)
        REFERENCES recoveries.evidence(organization_id, project_id, id) ON DELETE RESTRICT,
    CHECK (valid_to_baseline_version IS NULL OR valid_to_baseline_version >= valid_from_baseline_version),
    CHECK ((quantity IS NULL AND unit IS NULL) OR (quantity IS NOT NULL AND unit IS NOT NULL))
);

COMMIT;
