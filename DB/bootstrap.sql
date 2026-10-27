-- Invoked by scripts/Initialize-Database.ps1, initially against postgres.
-- CREATE DATABASE cannot share a transaction with the marker write. If the
-- process fails between them, the unmarked database is deliberately rejected
-- on the next run; inspect it manually rather than adopting it automatically.
\set ON_ERROR_STOP on
SET search_path = pg_catalog;

SELECT current_database() = 'postgres'
   AND current_user = 'postgres'
   AND current_setting('server_version_num')::integer / 10000 = 18
   AND :'database_name' ~ '^[a-z][a-z0-9_]{0,62}$'
   AND :'database_name' NOT IN ('postgres', 'template0', 'template1', 'accounts')
   AND :'database_marker' = 'opc.local-development.v1' AS valid_bootstrap
\gset
\if :valid_bootstrap
\else
  DO $$ BEGIN RAISE EXCEPTION 'Invalid OPC bootstrap target, role, marker, or PostgreSQL version (18 required)'; END $$;
\endif

-- This session lock serializes create/check/mark among initializers connected
-- to the same maintenance database. It is released on reconnect or failure.
SELECT pg_advisory_lock(184920, 1);
SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'database_name') AS database_exists,
       EXISTS (SELECT 1 FROM pg_database
                WHERE datname = :'database_name'
                  AND shobj_description(oid, 'pg_database') = :'database_marker'
                  AND pg_get_userbyid(datdba) = current_user) AS database_owned
\gset
\if :database_exists
  \if :database_owned
    \echo Existing OPC database marker verified.
  \else
    DO $$ BEGIN RAISE EXCEPTION 'Existing database is not marked as owned by this OPC initializer; refusing to modify it'; END $$;
  \endif
\else
  SELECT format('CREATE DATABASE %I WITH OWNER postgres TEMPLATE template0 ENCODING %L LOCALE_PROVIDER builtin BUILTIN_LOCALE %L',
                :'database_name', 'UTF8', 'C.UTF-8')
  \gexec
  SELECT format('COMMENT ON DATABASE %I IS %L', :'database_name', :'database_marker')
  \gexec
\endif

\connect -reuse-previous=on :database_name
BEGIN;
SET LOCAL search_path = pg_catalog;
SELECT pg_advisory_xact_lock(184920, 2);
SELECT current_database() = :'database_name'
   AND current_user = 'postgres'
   AND EXISTS (SELECT 1 FROM pg_database
                WHERE datname = current_database()
                  AND shobj_description(oid, 'pg_database') = :'database_marker'
                  AND pg_get_userbyid(datdba) = current_user
                  AND encoding = pg_char_to_encoding('UTF8')
                  AND datlocprovider = 'b'
                  AND datlocale = 'C.UTF-8') AS valid_database
\gset
\if :valid_database
\else
  DO $$ BEGIN RAISE EXCEPTION 'OPC database identity, owner, encoding, or locale does not match; refusing to initialize it'; END $$;
\endif

ALTER DATABASE :"database_name" SET timezone TO 'UTC';
REVOKE ALL ON DATABASE :"database_name" FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA IF NOT EXISTS opc AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA opc FROM PUBLIC;
CREATE TABLE IF NOT EXISTS opc.schema_migrations (
  version text PRIMARY KEY,
  checksum text NOT NULL CHECK (checksum ~ '^[0-9a-f]{64}$'),
  applied_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON ALL TABLES IN SCHEMA opc FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA opc FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA opc FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA opc REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA opc REVOKE ALL ON SEQUENCES FROM PUBLIC;
-- Function EXECUTE is public by default; a schema-scoped default REVOKE does
-- not remove that built-in grant. migrate.sql revokes it on new routines in
-- the same transaction, without changing defaults outside schema opc.
COMMIT;
