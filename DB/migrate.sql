-- One invocation per immutable migration file. No migration may contain its
-- own transaction commands: the SQL and ledger row must commit together.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = pg_catalog, opc;
SET LOCAL timezone = 'UTC';
SELECT pg_advisory_xact_lock(184920, 2);

SELECT current_database() = :'database_name'
   AND current_user = 'postgres'
   AND :'database_marker' = 'opc.local-development.v1'
   AND :'migration_version' ~ '^[0-9]{3}_[a-z][a-z0-9_]*$'
   AND :'migration_checksum' ~ '^[0-9a-f]{64}$'
   AND :'migration_version' = ANY(string_to_array(:'migration_manifest', ','))
   AND EXISTS (SELECT 1 FROM pg_database
                WHERE datname = current_database()
                  AND shobj_description(oid, 'pg_database') = :'database_marker'
                  AND pg_get_userbyid(datdba) = current_user) AS valid_migration_target
\gset
\if :valid_migration_target
\else
  DO $$ BEGIN RAISE EXCEPTION 'Migration target, ownership marker, version, or checksum is invalid'; END $$;
\endif

SELECT EXISTS (SELECT 1 FROM opc.schema_migrations
                WHERE version <> ALL(string_to_array(:'migration_manifest', ','))) AS unknown_migration,
       EXISTS (SELECT 1 FROM opc.schema_migrations
                WHERE version = :'migration_version') AS already_applied,
       EXISTS (SELECT 1 FROM opc.schema_migrations
                WHERE version = :'migration_version'
                  AND checksum <> :'migration_checksum') AS checksum_changed
\gset
\if :unknown_migration
  DO $$ BEGIN RAISE EXCEPTION 'Database contains a migration absent from this checkout; refusing to run an incomplete or older migration set'; END $$;
\endif
\if :checksum_changed
  \echo Checksum mismatch for :migration_version
  DO $$ BEGIN RAISE EXCEPTION 'Applied migration bytes have changed; restore the original file and use a new migration for changes'; END $$;
\endif

\if :check_only
  \echo Validated :migration_version
\else
  \if :already_applied
    \echo Already applied, unchanged: :migration_version
  \else
    SELECT EXISTS (SELECT 1 FROM opc.schema_migrations
                    WHERE version > :'migration_version') AS out_of_order
    \gset
    \if :out_of_order
      DO $$ BEGIN RAISE EXCEPTION 'A later migration is already applied; refusing to fill a gap in migration history'; END $$;
    \endif
    \echo Applying :migration_version
    \i :migration_file
    REVOKE ALL ON ALL TABLES IN SCHEMA opc FROM PUBLIC;
    REVOKE ALL ON ALL SEQUENCES IN SCHEMA opc FROM PUBLIC;
    REVOKE ALL ON ALL FUNCTIONS IN SCHEMA opc FROM PUBLIC;
    INSERT INTO opc.schema_migrations (version, checksum)
    VALUES (:'migration_version', :'migration_checksum');
  \endif
\endif
COMMIT;
