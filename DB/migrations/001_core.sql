-- OPC PostgreSQL 18 foundation. Run through scripts/Initialize-Database.ps1.
-- No business accounts, passwords, files or demo tasks are seeded here.
CREATE TABLE opc.accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL CHECK (email = btrim(email) AND email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  email_normalized text GENERATED ALWAYS AS (lower(email)) STORED UNIQUE,
  display_name text NOT NULL CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 80),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('invited','active','disabled')),
  ui_locale text NOT NULL DEFAULT 'ja' CHECK (ui_locale IN ('ja','zh')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);
CREATE TABLE opc.password_credentials (
  account_id uuid PRIMARY KEY REFERENCES opc.accounts(id),
  password_hash text NOT NULL CHECK (length(password_hash) >= 40 AND password_hash LIKE '$%'),
  changed_at timestamptz NOT NULL DEFAULT now(),
  must_change boolean NOT NULL DEFAULT false
);
COMMENT ON COLUMN opc.password_credentials.password_hash IS 'Backend-generated encoded password hash, never plaintext. Identity implementation remains pending.';
CREATE TABLE opc.auth_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES opc.accounts(id),
  token_hash text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  audience text NOT NULL CHECK (audience IN ('mobile','admin')),
  device_label text,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  CHECK (expires_at > created_at),
  CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE INDEX auth_sessions_account_idx ON opc.auth_sessions(account_id, expires_at) WHERE revoked_at IS NULL;
CREATE TABLE opc.roles (
  code text PRIMARY KEY,
  name_ja text NOT NULL,
  name_zh text NOT NULL,
  description text NOT NULL
);
CREATE TABLE opc.account_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES opc.accounts(id),
  role_code text NOT NULL REFERENCES opc.roles(code),
  granted_by uuid NOT NULL REFERENCES opc.accounts(id),
  granted_at timestamptz NOT NULL DEFAULT now(),
  revoked_by uuid REFERENCES opc.accounts(id),
  revoked_at timestamptz,
  reason text NOT NULL CHECK (btrim(reason) <> ''),
  CHECK ((revoked_by IS NULL) = (revoked_at IS NULL)),
  CHECK (revoked_at IS NULL OR revoked_at >= granted_at)
);
CREATE UNIQUE INDEX account_roles_active_uq ON opc.account_roles(account_id, role_code) WHERE revoked_at IS NULL;
CREATE TABLE opc.provider_authorizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES opc.accounts(id),
  granted_by uuid NOT NULL REFERENCES opc.accounts(id),
  granted_at timestamptz NOT NULL DEFAULT now(),
  revoked_by uuid REFERENCES opc.accounts(id),
  revoked_at timestamptz,
  reason text NOT NULL CHECK (btrim(reason) <> ''),
  CHECK ((revoked_by IS NULL) = (revoked_at IS NULL)),
  CHECK (revoked_at IS NULL OR revoked_at >= granted_at)
);
CREATE UNIQUE INDEX provider_authorizations_active_uq ON opc.provider_authorizations(account_id) WHERE revoked_at IS NULL;
COMMENT ON TABLE opc.provider_authorizations IS 'Internal service authorization only. No formal OPC certification is implied.';
CREATE TABLE opc.service_types (
  code text PRIMARY KEY,
  name_ja text NOT NULL,
  name_zh text NOT NULL,
  enabled boolean NOT NULL DEFAULT false
);
CREATE TABLE opc.request_drafts (
  customer_id uuid PRIMARY KEY REFERENCES opc.accounts(id),
  description text NOT NULL DEFAULT '',
  timing_text text NOT NULL DEFAULT '',
  budget_text text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);
CREATE SEQUENCE opc.request_number_seq START 1001;
CREATE TABLE opc.requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  public_code text NOT NULL UNIQUE DEFAULT ('REQ-' || lpad(nextval('opc.request_number_seq')::text, 8, '0')),
  customer_id uuid NOT NULL REFERENCES opc.accounts(id),
  service_code text NOT NULL DEFAULT 'development' REFERENCES opc.service_types(code),
  intake_status text NOT NULL DEFAULT 'submitted' CHECK (intake_status IN ('submitted','needs_info','in_review','withdrawn','closed')),
  current_request_version integer NOT NULL DEFAULT 1 CHECK (current_request_version > 0),
  current_scope_version integer CHECK (current_scope_version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0)
);
CREATE INDEX requests_customer_idx ON opc.requests(customer_id, created_at DESC);
CREATE INDEX requests_review_queue_idx ON opc.requests(intake_status, updated_at);
CREATE TABLE opc.request_versions (
  request_id uuid NOT NULL REFERENCES opc.requests(id),
  version integer NOT NULL CHECK (version > 0),
  original_description text NOT NULL CHECK (char_length(btrim(original_description)) BETWEEN 10 AND 4000),
  timing_text text NOT NULL CHECK (btrim(timing_text) <> ''),
  budget_text text NOT NULL CHECK (btrim(budget_text) <> ''),
  submitted_by uuid NOT NULL REFERENCES opc.accounts(id),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (request_id, version)
);
CREATE TABLE opc.scope_versions (
  request_id uuid NOT NULL REFERENCES opc.requests(id),
  version integer NOT NULL CHECK (version > 0),
  request_version integer NOT NULL,
  title text NOT NULL CHECK (btrim(title) <> ''),
  public_summary text NOT NULL CHECK (btrim(public_summary) <> ''),
  category text NOT NULL CHECK (btrim(category) <> ''),
  goal text NOT NULL DEFAULT '',
  included_scope text NOT NULL DEFAULT '',
  excluded_scope text NOT NULL DEFAULT '',
  deliverables jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(deliverables) = 'array'),
  acceptance_criteria jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(acceptance_criteria) = 'array'),
  duration_text text NOT NULL DEFAULT '',
  revision_terms text NOT NULL DEFAULT '',
  authored_by uuid NOT NULL REFERENCES opc.accounts(id),
  authored_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (request_id, version),
  FOREIGN KEY (request_id, request_version) REFERENCES opc.request_versions(request_id, version)
);
ALTER TABLE opc.requests ADD CONSTRAINT requests_current_original_fk
  FOREIGN KEY (id, current_request_version) REFERENCES opc.request_versions(request_id, version) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE opc.requests ADD CONSTRAINT requests_current_scope_fk
  FOREIGN KEY (id, current_scope_version) REFERENCES opc.scope_versions(request_id, version) DEFERRABLE INITIALLY DEFERRED;
CREATE TABLE opc.clarifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL,
  request_version integer NOT NULL,
  question text NOT NULL CHECK (btrim(question) <> ''),
  asked_by uuid NOT NULL REFERENCES opc.accounts(id),
  asked_at timestamptz NOT NULL DEFAULT now(),
  answer text,
  answered_by uuid REFERENCES opc.accounts(id),
  answered_at timestamptz,
  FOREIGN KEY (request_id, request_version) REFERENCES opc.request_versions(request_id, version),
  CHECK ((answer IS NULL AND answered_by IS NULL AND answered_at IS NULL) OR
    (answer IS NOT NULL AND btrim(answer) <> '' AND answered_by IS NOT NULL AND answered_at IS NOT NULL AND answered_at >= asked_at))
);
CREATE INDEX clarifications_request_idx ON opc.clarifications(request_id, asked_at);
CREATE TABLE opc.review_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL,
  scope_version integer NOT NULL,
  kind text NOT NULL CHECK (kind IN ('compliance','technical')),
  decision text NOT NULL CHECK (decision IN ('approved','needs_info','rejected')),
  reviewer_id uuid NOT NULL REFERENCES opc.accounts(id),
  reason text NOT NULL CHECK (btrim(reason) <> ''),
  decided_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, scope_version, kind),
  FOREIGN KEY (request_id, scope_version) REFERENCES opc.scope_versions(request_id, version)
);
CREATE TABLE opc.publications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL,
  scope_version integer NOT NULL,
  compliance_review_id uuid NOT NULL REFERENCES opc.review_decisions(id),
  technical_review_id uuid NOT NULL REFERENCES opc.review_decisions(id),
  published_by uuid NOT NULL REFERENCES opc.accounts(id),
  published_at timestamptz NOT NULL DEFAULT now(),
  withdrawn_by uuid REFERENCES opc.accounts(id),
  withdrawn_at timestamptz,
  withdrawal_reason text,
  UNIQUE (id, request_id, scope_version),
  FOREIGN KEY (request_id, scope_version) REFERENCES opc.scope_versions(request_id, version),
  CHECK ((withdrawn_at IS NULL AND withdrawn_by IS NULL AND withdrawal_reason IS NULL) OR
    (withdrawn_at IS NOT NULL AND withdrawn_by IS NOT NULL AND withdrawal_reason IS NOT NULL AND btrim(withdrawal_reason) <> '' AND withdrawn_at >= published_at))
);
CREATE UNIQUE INDEX publications_active_uq ON opc.publications(request_id) WHERE withdrawn_at IS NULL;
CREATE TABLE opc.files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES opc.accounts(id),
  original_name text NOT NULL CHECK (btrim(original_name) <> '' AND original_name !~ '[/\\]'),
  media_type text NOT NULL CHECK (btrim(media_type) <> ''),
  kind text NOT NULL CHECK (kind IN ('image','video','document','spreadsheet','presentation','pdf','text','other')),
  storage_key text NOT NULL UNIQUE CHECK (btrim(storage_key) <> '' AND storage_key !~ '^[a-zA-Z]+://'),
  size_bytes bigint NOT NULL CHECK (size_bytes >= 0),
  sha256 text CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  upload_status text NOT NULL DEFAULT 'pending' CHECK (upload_status IN ('pending','ready','failed','deleted')),
  scan_status text NOT NULL DEFAULT 'pending' CHECK (scan_status IN ('pending','clean','rejected','failed')),
  duration_ms bigint CHECK (duration_ms >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
  CHECK (upload_status <> 'ready' OR (size_bytes > 0 AND sha256 IS NOT NULL))
);
COMMENT ON COLUMN opc.files.storage_key IS 'Private opaque storage identifier, never a public or signed URL. Storage provider remains undecided.';
CREATE INDEX files_owner_idx ON opc.files(owner_id, created_at DESC);
CREATE TABLE opc.draft_files (
  customer_id uuid NOT NULL REFERENCES opc.request_drafts(customer_id),
  file_id uuid NOT NULL REFERENCES opc.files(id),
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  PRIMARY KEY (customer_id, file_id)
);
CREATE TABLE opc.request_files (
  request_id uuid NOT NULL,
  request_version integer NOT NULL,
  file_id uuid NOT NULL REFERENCES opc.files(id),
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  PRIMARY KEY (request_id, request_version, file_id),
  FOREIGN KEY (request_id, request_version) REFERENCES opc.request_versions(request_id, version)
);
COMMENT ON TABLE opc.request_files IS 'Private original customer material. No implicit publication or hall visibility.';
CREATE TABLE opc.scope_files (
  request_id uuid NOT NULL,
  scope_version integer NOT NULL,
  file_id uuid NOT NULL REFERENCES opc.files(id),
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  PRIMARY KEY (request_id, scope_version, file_id),
  FOREIGN KEY (request_id, scope_version) REFERENCES opc.scope_versions(request_id, version)
);
COMMENT ON TABLE opc.scope_files IS 'Explicit review package of intended hall references, frozen when the first review is recorded.';
CREATE TABLE opc.publication_files (
  publication_id uuid NOT NULL,
  request_id uuid NOT NULL,
  scope_version integer NOT NULL,
  file_id uuid NOT NULL,
  PRIMARY KEY (publication_id, file_id),
  FOREIGN KEY (publication_id, request_id, scope_version) REFERENCES opc.publications(id, request_id, scope_version),
  FOREIGN KEY (request_id, scope_version, file_id) REFERENCES opc.scope_files(request_id, scope_version, file_id)
);
CREATE TABLE opc.file_previews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  file_id uuid NOT NULL REFERENCES opc.files(id),
  format text NOT NULL CHECK (format IN ('thumbnail','image_pages','video','table','text')),
  converter_version text NOT NULL CHECK (btrim(converter_version) <> ''),
  state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','processing','ready','failed','unsupported')),
  private_storage_key text,
  metadata jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(metadata) = 'object'),
  error_code text,
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
  UNIQUE (file_id, format, converter_version),
  CHECK (state <> 'ready' OR (private_storage_key IS NOT NULL AND btrim(private_storage_key) <> ''))
);
CREATE TABLE opc.engagements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES opc.requests(id),
  status text NOT NULL DEFAULT 'pending_confirmation' CHECK (status IN ('pending_confirmation','executing','internal_review','awaiting_acceptance','revision','completed','cancelled')),
  created_by uuid NOT NULL REFERENCES opc.accounts(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  row_version bigint NOT NULL DEFAULT 1 CHECK (row_version > 0),
  UNIQUE (id, request_id),
  CHECK ((status IN ('completed','cancelled')) = (closed_at IS NOT NULL)),
  CHECK (closed_at IS NULL OR closed_at >= created_at)
);
CREATE UNIQUE INDEX engagements_active_uq ON opc.engagements(request_id) WHERE closed_at IS NULL;
CREATE TABLE opc.assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  engagement_id uuid NOT NULL REFERENCES opc.engagements(id),
  version integer NOT NULL CHECK (version > 0),
  provider_id uuid NOT NULL REFERENCES opc.accounts(id),
  recorded_by uuid NOT NULL REFERENCES opc.accounts(id),
  reason text NOT NULL CHECK (btrim(reason) <> ''),
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  ended_by uuid REFERENCES opc.accounts(id),
  end_reason text,
  UNIQUE (engagement_id, version),
  UNIQUE (id, engagement_id),
  CHECK ((ended_at IS NULL AND ended_by IS NULL AND end_reason IS NULL) OR
    (ended_at IS NOT NULL AND ended_by IS NOT NULL AND end_reason IS NOT NULL AND btrim(end_reason) <> '' AND ended_at >= started_at))
);
CREATE UNIQUE INDEX assignments_active_uq ON opc.assignments(engagement_id) WHERE ended_at IS NULL;
CREATE INDEX assignments_provider_idx ON opc.assignments(provider_id) WHERE ended_at IS NULL;
COMMENT ON TABLE opc.assignments IS 'Historical principal-provider relationship, independent of the still-undecided acquisition mechanism.';
CREATE TABLE opc.agreement_versions (
  engagement_id uuid NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  request_id uuid NOT NULL,
  scope_version integer NOT NULL,
  terms text NOT NULL CHECK (btrim(terms) <> ''),
  quoted_amount numeric(14,0) CHECK (quoted_amount >= 0),
  currency text NOT NULL DEFAULT 'JPY' CHECK (currency = 'JPY'),
  due_at timestamptz,
  authored_by uuid NOT NULL REFERENCES opc.accounts(id),
  authored_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (engagement_id, version),
  FOREIGN KEY (engagement_id, request_id) REFERENCES opc.engagements(id, request_id),
  FOREIGN KEY (request_id, scope_version) REFERENCES opc.scope_versions(request_id, version)
);
COMMENT ON COLUMN opc.agreement_versions.quoted_amount IS 'Optional quote only; never implies payment, escrow, commission or internal remuneration.';
CREATE TABLE opc.agreement_confirmations (
  engagement_id uuid NOT NULL,
  agreement_version integer NOT NULL,
  party text NOT NULL CHECK (party IN ('customer','provider')),
  confirmed_by uuid NOT NULL REFERENCES opc.accounts(id),
  confirmed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (engagement_id, agreement_version, party),
  FOREIGN KEY (engagement_id, agreement_version) REFERENCES opc.agreement_versions(engagement_id, version)
);
CREATE TABLE opc.deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  engagement_id uuid NOT NULL REFERENCES opc.engagements(id),
  version integer NOT NULL CHECK (version > 0),
  assignment_id uuid NOT NULL,
  agreement_version integer NOT NULL,
  submitted_by uuid NOT NULL REFERENCES opc.accounts(id),
  note text NOT NULL CHECK (btrim(note) <> ''),
  source_file_id uuid REFERENCES opc.files(id),
  repository_url text,
  source_commit text,
  source_archive_ref text,
  guide_text text NOT NULL CHECK (btrim(guide_text) <> ''),
  test_report_text text NOT NULL CHECK (btrim(test_report_text) <> ''),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (engagement_id, version),
  UNIQUE (id, engagement_id),
  FOREIGN KEY (assignment_id, engagement_id) REFERENCES opc.assignments(id, engagement_id),
  FOREIGN KEY (engagement_id, agreement_version) REFERENCES opc.agreement_versions(engagement_id, version),
  CHECK ((source_file_id IS NOT NULL AND repository_url IS NULL AND source_commit IS NULL) OR
    (source_file_id IS NULL AND repository_url IS NOT NULL AND repository_url ~ '^https://' AND source_commit IS NOT NULL AND source_commit ~ '^[0-9a-f]{40}([0-9a-f]{24})?$' AND source_archive_ref IS NOT NULL AND btrim(source_archive_ref) <> ''))
);
COMMENT ON TABLE opc.deliveries IS 'Immutable delivery evidence. A syntactically fixed commit does not prove repository access or successful tests.';
CREATE TABLE opc.delivery_files (
  delivery_id uuid NOT NULL REFERENCES opc.deliveries(id),
  file_id uuid NOT NULL REFERENCES opc.files(id),
  purpose text NOT NULL CHECK (purpose IN ('source','guide','tests','demo','other')),
  PRIMARY KEY (delivery_id, file_id)
);
CREATE TABLE opc.delivery_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL UNIQUE REFERENCES opc.deliveries(id),
  reviewer_id uuid NOT NULL REFERENCES opc.accounts(id),
  decision text NOT NULL CHECK (decision IN ('approved','changes_requested','rejected')),
  evidence text NOT NULL CHECK (btrim(evidence) <> ''),
  reviewed_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE opc.delivery_publications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL UNIQUE REFERENCES opc.deliveries(id),
  review_id uuid NOT NULL REFERENCES opc.delivery_reviews(id),
  published_by uuid NOT NULL REFERENCES opc.accounts(id),
  published_at timestamptz NOT NULL DEFAULT now(),
  withdrawn_by uuid REFERENCES opc.accounts(id),
  withdrawn_at timestamptz,
  withdrawal_reason text,
  CHECK ((withdrawn_at IS NULL AND withdrawn_by IS NULL AND withdrawal_reason IS NULL) OR
    (withdrawn_at IS NOT NULL AND withdrawn_by IS NOT NULL AND withdrawal_reason IS NOT NULL AND btrim(withdrawal_reason) <> '' AND withdrawn_at >= published_at))
);
CREATE TABLE opc.acceptance_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL UNIQUE REFERENCES opc.deliveries(id),
  customer_id uuid NOT NULL REFERENCES opc.accounts(id),
  decision text NOT NULL CHECK (decision IN ('accepted','revision_requested')),
  feedback text NOT NULL DEFAULT '',
  decided_at timestamptz NOT NULL DEFAULT now(),
  CHECK (decision <> 'revision_requested' OR btrim(feedback) <> '')
);
CREATE TABLE opc.conversation_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES opc.requests(id),
  kind text NOT NULL CHECK (kind IN ('consultation','customer_project','internal')),
  initiator_id uuid REFERENCES opc.accounts(id),
  engagement_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (engagement_id, request_id) REFERENCES opc.engagements(id, request_id),
  CHECK ((kind = 'consultation' AND initiator_id IS NOT NULL AND engagement_id IS NULL) OR
    (kind = 'customer_project' AND engagement_id IS NOT NULL AND initiator_id IS NULL) OR
    (kind = 'internal' AND initiator_id IS NULL))
);
CREATE UNIQUE INDEX consultations_initiator_uq ON opc.conversation_threads(request_id, initiator_id) WHERE kind = 'consultation';
CREATE UNIQUE INDEX project_thread_uq ON opc.conversation_threads(engagement_id) WHERE kind = 'customer_project';
CREATE TABLE opc.thread_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES opc.conversation_threads(id),
  account_id uuid NOT NULL REFERENCES opc.accounts(id),
  added_by uuid NOT NULL REFERENCES opc.accounts(id),
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz,
  CHECK (left_at IS NULL OR left_at >= joined_at)
);
CREATE UNIQUE INDEX thread_participants_active_uq ON opc.thread_participants(thread_id, account_id) WHERE left_at IS NULL;
CREATE INDEX thread_participants_account_idx ON opc.thread_participants(account_id) WHERE left_at IS NULL;
CREATE TABLE opc.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES opc.conversation_threads(id),
  author_id uuid NOT NULL REFERENCES opc.accounts(id),
  body text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 4000),
  client_message_id uuid NOT NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (author_id, client_message_id)
);
CREATE INDEX messages_thread_idx ON opc.messages(thread_id, sent_at, id);
CREATE TABLE opc.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL REFERENCES opc.accounts(id),
  request_id uuid REFERENCES opc.requests(id),
  event_key text NOT NULL,
  template_key text NOT NULL,
  parameters jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(parameters) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  UNIQUE (recipient_id, event_key),
  CHECK (read_at IS NULL OR read_at >= created_at)
);
CREATE INDEX notifications_unread_idx ON opc.notifications(recipient_id, created_at DESC) WHERE read_at IS NULL;
CREATE TABLE opc.outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic text NOT NULL,
  aggregate_id uuid NOT NULL,
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','sent','failed')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  available_at timestamptz NOT NULL DEFAULT now(),
  locked_until timestamptz,
  completed_at timestamptz,
  last_error_code text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX outbox_pending_idx ON opc.outbox_events(available_at, id) WHERE status IN ('pending','failed');
CREATE TABLE opc.idempotency_keys (
  actor_id uuid NOT NULL REFERENCES opc.accounts(id),
  operation text NOT NULL,
  key text NOT NULL CHECK (length(key) BETWEEN 1 AND 200),
  request_hash text NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  result jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (actor_id, operation, key),
  CHECK (expires_at > created_at)
);
CREATE INDEX idempotency_expiry_idx ON opc.idempotency_keys(expires_at);
CREATE TABLE opc.audit_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  database_actor name NOT NULL DEFAULT session_user,
  application_actor_id uuid REFERENCES opc.accounts(id),
  correlation_id text,
  table_name text NOT NULL,
  operation text NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE','BUSINESS')),
  entity_key jsonb NOT NULL CHECK (jsonb_typeof(entity_key) = 'object'),
  changed_fields text[] NOT NULL DEFAULT '{}',
  details jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(details) = 'object')
);
CREATE INDEX audit_entity_idx ON opc.audit_events(table_name, occurred_at DESC);
COMMENT ON TABLE opc.audit_events IS 'Append-only structural audit; excludes passwords, token hashes and message/file contents. Application actor is not authenticated by this table.';
