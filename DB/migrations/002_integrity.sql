-- These constraints protect stored evidence. They are not an API authorization layer.
CREATE FUNCTION opc.prevent_history_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% is append-only; create a new version or an explicit closure', TG_TABLE_NAME USING ERRCODE = '55000';
END $$;

CREATE FUNCTION opc.touch_row() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := clock_timestamp();
  NEW.row_version := OLD.row_version + 1;
  RETURN NEW;
END $$;

-- Only one-way closure fields may change on historical grant/publication rows.
CREATE FUNCTION opc.close_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION '% cannot be deleted', TG_TABLE_NAME USING ERRCODE = '55000';
  END IF;
  IF (to_jsonb(NEW) - string_to_array(TG_ARGV[0], ',')) IS DISTINCT FROM
     (to_jsonb(OLD) - string_to_array(TG_ARGV[0], ',')) OR
     to_jsonb(OLD)->>TG_ARGV[1] IS NOT NULL OR to_jsonb(NEW)->>TG_ARGV[1] IS NULL THEN
    RAISE EXCEPTION '% permits a single explicit closure only', TG_TABLE_NAME USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END $$;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['request_versions','scope_versions','review_decisions',
    'agreement_versions','agreement_confirmations','deliveries','delivery_reviews',
    'acceptance_decisions','messages','audit_events','conversation_threads'] LOOP
    EXECUTE format('CREATE TRIGGER immutable_history BEFORE UPDATE OR DELETE ON opc.%I FOR EACH ROW EXECUTE FUNCTION opc.prevent_history_change()', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['accounts','requests','request_drafts','files','file_previews','engagements'] LOOP
    EXECUTE format('CREATE TRIGGER z_touch BEFORE UPDATE ON opc.%I FOR EACH ROW EXECUTE FUNCTION opc.touch_row()', t);
  END LOOP;
END $$;
CREATE TRIGGER close_history BEFORE UPDATE OR DELETE ON opc.account_roles FOR EACH ROW EXECUTE FUNCTION opc.close_history('revoked_by,revoked_at','revoked_at');
CREATE TRIGGER close_history BEFORE UPDATE OR DELETE ON opc.provider_authorizations FOR EACH ROW EXECUTE FUNCTION opc.close_history('revoked_by,revoked_at','revoked_at');
CREATE TRIGGER close_history BEFORE UPDATE OR DELETE ON opc.publications FOR EACH ROW EXECUTE FUNCTION opc.close_history('withdrawn_by,withdrawn_at,withdrawal_reason','withdrawn_at');
CREATE TRIGGER close_history BEFORE UPDATE OR DELETE ON opc.delivery_publications FOR EACH ROW EXECUTE FUNCTION opc.close_history('withdrawn_by,withdrawn_at,withdrawal_reason','withdrawn_at');
CREATE TRIGGER close_history BEFORE UPDATE OR DELETE ON opc.assignments FOR EACH ROW EXECUTE FUNCTION opc.close_history('ended_by,ended_at,end_reason','ended_at');
CREATE TRIGGER close_history BEFORE UPDATE OR DELETE ON opc.thread_participants FOR EACH ROW EXECUTE FUNCTION opc.close_history('left_at','left_at');

CREATE FUNCTION opc.guard_request() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NOT EXISTS (SELECT 1 FROM opc.service_types WHERE code = NEW.service_code AND enabled) THEN
    RAISE EXCEPTION 'Service is not enabled' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'UPDATE' AND ((NEW.id,NEW.customer_id,NEW.service_code,NEW.public_code,NEW.created_at) IS DISTINCT FROM
    (OLD.id,OLD.customer_id,OLD.service_code,OLD.public_code,OLD.created_at) OR
    NEW.current_request_version < OLD.current_request_version OR
    (OLD.current_scope_version IS NOT NULL AND NEW.current_scope_version IS NULL AND NEW.current_request_version=OLD.current_request_version) OR
    (NEW.current_scope_version IS NOT NULL AND NEW.current_scope_version < OLD.current_scope_version)) THEN
    RAISE EXCEPTION 'Request identity and version history cannot be replaced or rewound' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_request BEFORE INSERT OR UPDATE ON opc.requests FOR EACH ROW EXECUTE FUNCTION opc.guard_request();

CREATE FUNCTION opc.check_current_scope() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM opc.requests r JOIN opc.scope_versions s ON s.request_id=r.id AND s.version=r.current_scope_version
    WHERE r.id=NEW.id AND (s.request_version <> r.current_request_version OR
      s.version <> (SELECT max(version) FROM opc.scope_versions WHERE request_id=r.id))) THEN
    RAISE EXCEPTION 'Current scope must describe the current original request' USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER current_scope_matches_original AFTER INSERT OR UPDATE ON opc.requests
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION opc.check_current_scope();

CREATE FUNCTION opc.guard_original_files() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION 'Original attachment evidence cannot change' USING ERRCODE='55000';
  END IF;
  PERFORM 1 FROM opc.request_versions WHERE request_id=NEW.request_id AND version=NEW.request_version FOR UPDATE;
  IF EXISTS (SELECT 1 FROM opc.scope_versions WHERE request_id=NEW.request_id AND request_version=NEW.request_version) THEN
    RAISE EXCEPTION 'Original attachments are frozen when technical preparation begins' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_original_files BEFORE INSERT OR UPDATE OR DELETE ON opc.request_files FOR EACH ROW EXECUTE FUNCTION opc.guard_original_files();
CREATE FUNCTION opc.lock_original_package() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM opc.request_versions WHERE request_id=NEW.request_id AND version=NEW.request_version FOR UPDATE;
  RETURN NEW;
END $$;
CREATE TRIGGER lock_original_package BEFORE INSERT ON opc.scope_versions FOR EACH ROW EXECUTE FUNCTION opc.lock_original_package();

CREATE FUNCTION opc.guard_clarification() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'Clarification history cannot be deleted' USING ERRCODE='55000';
  END IF;
  IF TG_OP='UPDATE' AND (OLD.answer IS NOT NULL OR NEW.answer IS NULL OR
    (to_jsonb(NEW)-ARRAY['answer','answered_by','answered_at']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['answer','answered_by','answered_at'])) THEN
    RAISE EXCEPTION 'A clarification permits one answer only' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_clarification BEFORE UPDATE OR DELETE ON opc.clarifications FOR EACH ROW EXECUTE FUNCTION opc.guard_clarification();

CREATE FUNCTION opc.guard_scope_files() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r uuid; v integer;
BEGIN
  IF TG_OP='UPDATE' THEN
    RAISE EXCEPTION 'Remove and re-add unreviewed scope references instead of updating keys' USING ERRCODE='55000';
  END IF;
  IF TG_OP='DELETE' THEN r:=OLD.request_id; v:=OLD.scope_version; ELSE r:=NEW.request_id; v:=NEW.scope_version; END IF;
  PERFORM 1 FROM opc.scope_versions WHERE request_id=r AND version=v FOR UPDATE;
  IF EXISTS (SELECT 1 FROM opc.review_decisions WHERE request_id=r AND scope_version=v) THEN
    RAISE EXCEPTION 'Reviewed reference package is immutable; create a new scope version' USING ERRCODE='55000';
  END IF;
  IF TG_OP='INSERT' AND NOT EXISTS (SELECT 1 FROM opc.files WHERE id=NEW.file_id AND upload_status='ready' AND scan_status='clean') THEN
    RAISE EXCEPTION 'A reference must be uploaded and cleared before review' USING ERRCODE='23514';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_scope_files BEFORE INSERT OR UPDATE OR DELETE ON opc.scope_files FOR EACH ROW EXECUTE FUNCTION opc.guard_scope_files();
CREATE FUNCTION opc.lock_review_package() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM opc.scope_versions WHERE request_id=NEW.request_id AND version=NEW.scope_version FOR UPDATE;
  RETURN NEW;
END $$;
CREATE TRIGGER lock_review_package BEFORE INSERT ON opc.review_decisions FOR EACH ROW EXECUTE FUNCTION opc.lock_review_package();

CREATE FUNCTION opc.guard_publication() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM opc.requests WHERE id=NEW.request_id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM opc.requests r JOIN opc.scope_versions s ON s.request_id=r.id AND s.version=r.current_scope_version
      WHERE r.id=NEW.request_id AND s.version=NEW.scope_version AND s.request_version=r.current_request_version
        AND r.intake_status IN ('submitted','in_review')) OR
    NOT EXISTS (SELECT 1 FROM opc.review_decisions WHERE id=NEW.compliance_review_id AND request_id=NEW.request_id
      AND scope_version=NEW.scope_version AND kind='compliance' AND decision='approved') OR
    NOT EXISTS (SELECT 1 FROM opc.review_decisions WHERE id=NEW.technical_review_id AND request_id=NEW.request_id
      AND scope_version=NEW.scope_version AND kind='technical' AND decision='approved') OR
    EXISTS (SELECT 1 FROM opc.scope_files s JOIN opc.files f ON f.id=s.file_id WHERE s.request_id=NEW.request_id
      AND s.scope_version=NEW.scope_version AND (f.upload_status<>'ready' OR f.scan_status<>'clean')) THEN
    RAISE EXCEPTION 'Publication requires both approved reviews of the current exact scope version' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_publication BEFORE INSERT ON opc.publications FOR EACH ROW EXECUTE FUNCTION opc.guard_publication();
CREATE TRIGGER publication_files_immutable BEFORE UPDATE OR DELETE ON opc.publication_files FOR EACH ROW EXECUTE FUNCTION opc.prevent_history_change();

CREATE FUNCTION opc.guard_file_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.id,NEW.owner_id,NEW.original_name,NEW.media_type,NEW.kind,NEW.storage_key,NEW.created_at) IS DISTINCT FROM
     (OLD.id,OLD.owner_id,OLD.original_name,OLD.media_type,OLD.kind,OLD.storage_key,OLD.created_at) OR
     ((OLD.upload_status <> 'pending' OR OLD.sha256 IS NOT NULL) AND
      (NEW.size_bytes,NEW.sha256,NEW.duration_ms) IS DISTINCT FROM (OLD.size_bytes,OLD.sha256,OLD.duration_ms)) THEN
    RAISE EXCEPTION 'File content identity is immutable; store replacement content under a new file ID' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_file_identity BEFORE UPDATE ON opc.files FOR EACH ROW EXECUTE FUNCTION opc.guard_file_identity();

-- Public projection excludes original customer text, private attachments, identities and storage keys.
-- The future API must still enforce the intended audience; no PUBLIC SELECT grant is made.
CREATE VIEW opc.hall_requests WITH (security_barrier=true) AS
  SELECT r.id AS request_id,r.public_code,r.service_code,s.version AS scope_version,
    s.title,s.public_summary,s.category,s.goal,s.included_scope,s.excluded_scope,
    s.deliverables,s.acceptance_criteria,s.duration_text,s.revision_terms,p.id AS publication_id,p.published_at
  FROM opc.requests r JOIN opc.scope_versions s ON s.request_id=r.id AND s.version=r.current_scope_version
  JOIN opc.publications p ON p.request_id=r.id AND p.scope_version=s.version AND p.withdrawn_at IS NULL
  JOIN opc.review_decisions c ON c.id=p.compliance_review_id AND c.request_id=r.id AND c.scope_version=s.version AND c.kind='compliance' AND c.decision='approved'
  JOIN opc.review_decisions t ON t.id=p.technical_review_id AND t.request_id=r.id AND t.scope_version=s.version AND t.kind='technical' AND t.decision='approved'
  WHERE r.intake_status IN ('submitted','in_review') AND s.request_version=r.current_request_version
    AND NOT EXISTS (SELECT 1 FROM opc.engagements e WHERE e.request_id=r.id AND e.closed_at IS NULL);
CREATE VIEW opc.hall_reference_files WITH (security_barrier=true) AS
  SELECT h.request_id,h.scope_version,h.publication_id,f.id AS file_id,f.original_name,f.kind,f.media_type,f.size_bytes,f.duration_ms,s.sort_order
  FROM opc.hall_requests h JOIN opc.publication_files p ON p.publication_id=h.publication_id
  JOIN opc.scope_files s ON s.request_id=p.request_id AND s.scope_version=p.scope_version AND s.file_id=p.file_id
  JOIN opc.files f ON f.id=p.file_id WHERE f.upload_status='ready' AND f.scan_status='clean';

CREATE FUNCTION opc.guard_engagement() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    PERFORM 1 FROM opc.requests WHERE id=NEW.request_id FOR UPDATE;
    IF NEW.status <> 'pending_confirmation' OR NOT EXISTS(SELECT 1 FROM opc.hall_requests WHERE request_id=NEW.request_id) THEN
      RAISE EXCEPTION 'A new cooperation record requires an available reviewed publication' USING ERRCODE='23514';
    END IF;
  ELSE
    IF (NEW.id,NEW.request_id,NEW.created_by,NEW.created_at) IS DISTINCT FROM (OLD.id,OLD.request_id,OLD.created_by,OLD.created_at)
      OR OLD.closed_at IS NOT NULL THEN
      RAISE EXCEPTION 'Cooperation identity and closed history cannot change' USING ERRCODE='55000';
    END IF;
    IF NEW.status='completed' AND NOT EXISTS (SELECT 1 FROM opc.deliveries d JOIN opc.acceptance_decisions a ON a.delivery_id=d.id
      WHERE d.engagement_id=NEW.id AND a.decision='accepted' AND NOT EXISTS (SELECT 1 FROM opc.deliveries n WHERE n.engagement_id=NEW.id AND n.version>d.version)) THEN
      RAISE EXCEPTION 'Completion requires explicit acceptance of the latest delivery' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_engagement BEFORE INSERT OR UPDATE ON opc.engagements FOR EACH ROW EXECUTE FUNCTION opc.guard_engagement();
CREATE TRIGGER engagement_no_delete BEFORE DELETE ON opc.engagements FOR EACH ROW EXECUTE FUNCTION opc.prevent_history_change();

CREATE FUNCTION opc.guard_assignment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM opc.engagements WHERE id=NEW.engagement_id FOR UPDATE;
  PERFORM 1 FROM opc.accounts a JOIN opc.provider_authorizations p ON p.account_id=a.id
    WHERE a.id=NEW.provider_id AND a.status='active' AND p.revoked_at IS NULL FOR SHARE OF a,p;
  IF NOT FOUND THEN RAISE EXCEPTION 'Provider must be active and internally authorized' USING ERRCODE='23514'; END IF;
  IF NOT EXISTS (SELECT 1 FROM opc.engagements WHERE id=NEW.engagement_id AND closed_at IS NULL) OR
    NEW.version <> (SELECT coalesce(max(version),0)+1 FROM opc.assignments WHERE engagement_id=NEW.engagement_id) THEN
    RAISE EXCEPTION 'Assignment requires an active internally authorized provider and the next relationship version' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_assignment BEFORE INSERT ON opc.assignments FOR EACH ROW EXECUTE FUNCTION opc.guard_assignment();

CREATE FUNCTION opc.guard_agreement() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM opc.engagements WHERE id=NEW.engagement_id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM opc.engagements WHERE id=NEW.engagement_id AND closed_at IS NULL) OR
    NEW.version <> (SELECT coalesce(max(version),0)+1 FROM opc.agreement_versions WHERE engagement_id=NEW.engagement_id) OR
    (SELECT count(*) FROM opc.review_decisions WHERE request_id=NEW.request_id AND scope_version=NEW.scope_version AND decision='approved')<>2 THEN
    RAISE EXCEPTION 'Agreement must use a reviewed scope and the next version of an open cooperation' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_agreement BEFORE INSERT ON opc.agreement_versions FOR EACH ROW EXECUTE FUNCTION opc.guard_agreement();
CREATE FUNCTION opc.guard_confirmation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM opc.engagements WHERE id=NEW.engagement_id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM opc.engagements WHERE id=NEW.engagement_id AND closed_at IS NULL) OR
    (NEW.party='customer' AND NOT EXISTS (SELECT 1 FROM opc.engagements e JOIN opc.requests r ON r.id=e.request_id WHERE e.id=NEW.engagement_id AND r.customer_id=NEW.confirmed_by)) OR
    (NEW.party='provider' AND NOT EXISTS (SELECT 1 FROM opc.assignments WHERE engagement_id=NEW.engagement_id AND provider_id=NEW.confirmed_by AND ended_at IS NULL)) THEN
    RAISE EXCEPTION 'Agreement confirmation must identify the actual cooperation party' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_confirmation BEFORE INSERT ON opc.agreement_confirmations FOR EACH ROW EXECUTE FUNCTION opc.guard_confirmation();

CREATE FUNCTION opc.guard_delivery() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM opc.engagements WHERE id=NEW.engagement_id FOR UPDATE;
  PERFORM 1 FROM opc.assignments a JOIN opc.accounts u ON u.id=a.provider_id JOIN opc.provider_authorizations p ON p.account_id=u.id
    WHERE a.id=NEW.assignment_id AND a.engagement_id=NEW.engagement_id AND a.provider_id=NEW.submitted_by
      AND a.ended_at IS NULL AND u.status='active' AND p.revoked_at IS NULL FOR SHARE OF a,u,p;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery submitter must be the active authorized provider' USING ERRCODE='23514'; END IF;
  IF NOT EXISTS (SELECT 1 FROM opc.engagements WHERE id=NEW.engagement_id AND closed_at IS NULL AND status IN ('executing','revision')) OR
    NOT EXISTS (SELECT 1 FROM opc.agreement_confirmations WHERE engagement_id=NEW.engagement_id AND agreement_version=NEW.agreement_version AND party='customer') OR
    NOT EXISTS (SELECT 1 FROM opc.agreement_confirmations WHERE engagement_id=NEW.engagement_id AND agreement_version=NEW.agreement_version AND party='provider' AND confirmed_by=NEW.submitted_by) OR
    NEW.version <> (SELECT coalesce(max(version),0)+1 FROM opc.deliveries WHERE engagement_id=NEW.engagement_id) THEN
    RAISE EXCEPTION 'Delivery requires an open cooperation, current authorized provider, confirmed agreement and next version' USING ERRCODE='23514';
  END IF;
  IF NEW.source_file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM opc.files WHERE id=NEW.source_file_id AND upload_status='ready' AND scan_status='clean') THEN
    RAISE EXCEPTION 'Source archive is not ready' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_delivery BEFORE INSERT ON opc.deliveries FOR EACH ROW EXECUTE FUNCTION opc.guard_delivery();

CREATE FUNCTION opc.guard_delivery_files() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d uuid;
BEGIN
  IF TG_OP='UPDATE' THEN RAISE EXCEPTION 'Delivery reference keys cannot change' USING ERRCODE='55000'; END IF;
  IF TG_OP='DELETE' THEN d:=OLD.delivery_id; ELSE d:=NEW.delivery_id; END IF;
  PERFORM 1 FROM opc.deliveries WHERE id=d FOR UPDATE;
  IF EXISTS (SELECT 1 FROM opc.delivery_reviews WHERE delivery_id=d) THEN
    RAISE EXCEPTION 'Reviewed delivery package cannot change' USING ERRCODE='55000';
  END IF;
  IF TG_OP='INSERT' AND NOT EXISTS (SELECT 1 FROM opc.files WHERE id=NEW.file_id AND upload_status='ready' AND scan_status='clean') THEN
    RAISE EXCEPTION 'Delivery attachment is not ready' USING ERRCODE='23514';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_delivery_files BEFORE INSERT OR UPDATE OR DELETE ON opc.delivery_files FOR EACH ROW EXECUTE FUNCTION opc.guard_delivery_files();
CREATE FUNCTION opc.lock_delivery_review() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM opc.deliveries WHERE id=NEW.delivery_id FOR UPDATE;
  RETURN NEW;
END $$;
CREATE TRIGGER lock_delivery_review BEFORE INSERT ON opc.delivery_reviews FOR EACH ROW EXECUTE FUNCTION opc.lock_delivery_review();

CREATE FUNCTION opc.guard_delivery_publication() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d opc.deliveries%ROWTYPE;
BEGIN
  SELECT * INTO d FROM opc.deliveries WHERE id=NEW.delivery_id;
  PERFORM 1 FROM opc.engagements WHERE id=d.engagement_id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM opc.engagements WHERE id=d.engagement_id AND closed_at IS NULL) OR
    NOT EXISTS (SELECT 1 FROM opc.delivery_reviews WHERE id=NEW.review_id AND delivery_id=NEW.delivery_id AND decision='approved') OR
    EXISTS (SELECT 1 FROM opc.deliveries WHERE engagement_id=d.engagement_id AND version>d.version) OR
    (d.source_file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM opc.files WHERE id=d.source_file_id AND upload_status='ready' AND scan_status='clean')) OR
    EXISTS (SELECT 1 FROM opc.delivery_files l JOIN opc.files f ON f.id=l.file_id WHERE l.delivery_id=d.id AND (f.upload_status<>'ready' OR f.scan_status<>'clean')) THEN
    RAISE EXCEPTION 'Only the latest complete delivery with approved internal QA can be released' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_delivery_publication BEFORE INSERT ON opc.delivery_publications FOR EACH ROW EXECUTE FUNCTION opc.guard_delivery_publication();

CREATE FUNCTION opc.guard_acceptance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d opc.deliveries%ROWTYPE;
BEGIN
  SELECT * INTO d FROM opc.deliveries WHERE id=NEW.delivery_id;
  PERFORM 1 FROM opc.engagements WHERE id=d.engagement_id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM opc.engagements e JOIN opc.requests r ON r.id=e.request_id WHERE e.id=d.engagement_id AND e.closed_at IS NULL AND e.status='awaiting_acceptance' AND r.customer_id=NEW.customer_id) OR
    EXISTS (SELECT 1 FROM opc.deliveries WHERE engagement_id=d.engagement_id AND version>d.version) OR
    NOT EXISTS (SELECT 1 FROM opc.delivery_publications p JOIN opc.delivery_reviews q ON q.id=p.review_id AND q.delivery_id=p.delivery_id
      WHERE p.delivery_id=d.id AND p.withdrawn_at IS NULL AND q.decision='approved') THEN
    RAISE EXCEPTION 'Customer decision must target the latest QA-approved released delivery of their own open cooperation' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_acceptance BEFORE INSERT ON opc.acceptance_decisions FOR EACH ROW EXECUTE FUNCTION opc.guard_acceptance();

CREATE FUNCTION opc.guard_message() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM opc.thread_participants WHERE thread_id=NEW.thread_id AND account_id=NEW.author_id AND left_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Message author must be an active conversation participant' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_message BEFORE INSERT ON opc.messages FOR EACH ROW EXECUTE FUNCTION opc.guard_message();

-- Capture keys and changed field names only. opc.actor_id is attribution supplied by
-- a future trusted backend transaction, never proof of end-user authentication.
CREATE FUNCTION opc.record_audit() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE after_row jsonb; before_row jsonb; keys jsonb; changed text[]; actor text;
BEGIN
  IF TG_OP <> 'DELETE' THEN after_row:=to_jsonb(NEW); END IF;
  IF TG_OP <> 'INSERT' THEN before_row:=to_jsonb(OLD); END IF;
  SELECT coalesce(jsonb_object_agg(k,v),'{}') INTO keys FROM jsonb_each(coalesce(after_row,before_row)) AS x(k,v)
    WHERE k='id' OR k IN ('account_id','request_id','request_version','customer_id','file_id','publication_id','engagement_id','delivery_id','thread_id','actor_id','version','scope_version','agreement_version','party');
  SELECT coalesce(array_agg(k ORDER BY k),'{}') INTO changed FROM jsonb_object_keys(coalesce(after_row,before_row)) AS x(k)
    WHERE TG_OP<>'UPDATE' OR after_row->k IS DISTINCT FROM before_row->k;
  actor:=nullif(current_setting('opc.actor_id',true),'');
  INSERT INTO opc.audit_events(application_actor_id,correlation_id,table_name,operation,entity_key,changed_fields)
    VALUES (actor::uuid,nullif(current_setting('opc.correlation_id',true),''),TG_TABLE_NAME,TG_OP,keys,changed);
  RETURN NULL;
END $$;
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['accounts','password_credentials','auth_sessions','account_roles','provider_authorizations',
    'request_drafts','requests','request_versions','scope_versions','clarifications','review_decisions','publications',
    'files','draft_files','request_files','scope_files','publication_files','file_previews','engagements','assignments',
    'agreement_versions','agreement_confirmations','deliveries','delivery_files','delivery_reviews','delivery_publications',
    'acceptance_decisions','conversation_threads','thread_participants','messages'] LOOP
    EXECUTE format('CREATE TRIGGER audit_change AFTER INSERT OR UPDATE OR DELETE ON opc.%I FOR EACH ROW EXECUTE FUNCTION opc.record_audit()',t);
  END LOOP;
END $$;

CREATE INDEX request_files_file_idx ON opc.request_files(file_id);
CREATE INDEX scope_files_file_idx ON opc.scope_files(file_id);
CREATE INDEX publication_files_file_idx ON opc.publication_files(file_id);
CREATE INDEX delivery_files_file_idx ON opc.delivery_files(file_id);
CREATE INDEX threads_request_idx ON opc.conversation_threads(request_id);
CREATE INDEX audit_actor_idx ON opc.audit_events(application_actor_id,occurred_at DESC) WHERE application_actor_id IS NOT NULL;

REVOKE ALL ON ALL TABLES IN SCHEMA opc FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA opc FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA opc FROM PUBLIC;
