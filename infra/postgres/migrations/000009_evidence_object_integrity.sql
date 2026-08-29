BEGIN;

CREATE FUNCTION recoveries.evidence_object_key(
    p_organization_id uuid,
    p_project_id uuid,
    p_evidence_id uuid,
    p_sha256 text,
    p_original_filename text
) RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $function$
    SELECT format(
        'org/%s/project/%s/evidence/%s/%s/%s',
        p_organization_id,
        p_project_id,
        p_evidence_id,
        p_sha256,
        p_original_filename
    )
$function$;

ALTER TABLE recoveries.evidence
    ADD CONSTRAINT evidence_original_filename_is_basename
        CHECK (
            original_filename = btrim(original_filename)
            AND original_filename <> ''
            AND original_filename !~ '[/\\]'
            AND original_filename NOT IN ('.', '..')
        ),
    ADD CONSTRAINT evidence_object_uri_matches_identity
        CHECK (
            object_uri ~ '^s3://[^/]+/org/'
            AND object_uri LIKE '%/' || recoveries.evidence_object_key(
                organization_id,
                project_id,
                id,
                sha256,
                original_filename
            )
        );

REVOKE ALL ON FUNCTION recoveries.evidence_object_key(uuid, uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION recoveries.evidence_object_key(uuid, uuid, uuid, text, text)
    TO recoveries_runtime_role, recoveries_migration_role;

COMMIT;
