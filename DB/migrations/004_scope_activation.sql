-- Track activation history separately from drafts awaiting activation. This lets
-- a new prepared scope exist without breaking unrelated updates to the request.
ALTER TABLE opc.requests ADD COLUMN highest_activated_scope_version integer NOT NULL DEFAULT 0
  CHECK (highest_activated_scope_version >= 0);
COMMENT ON COLUMN opc.requests.highest_activated_scope_version IS 'Trigger-managed monotonic activation watermark; never inferred from the highest prepared draft.';

CREATE OR REPLACE FUNCTION opc.guard_request() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    IF NOT EXISTS (SELECT 1 FROM opc.service_types WHERE code=NEW.service_code AND enabled) THEN
      RAISE EXCEPTION 'Service is not enabled' USING ERRCODE='23514';
    END IF;
    NEW.highest_activated_scope_version:=coalesce(NEW.current_scope_version,0);
  ELSE
    IF (NEW.id,NEW.customer_id,NEW.service_code,NEW.public_code,NEW.created_at) IS DISTINCT FROM
       (OLD.id,OLD.customer_id,OLD.service_code,OLD.public_code,OLD.created_at) OR
       NEW.current_request_version < OLD.current_request_version OR
       (OLD.current_scope_version IS NOT NULL AND NEW.current_scope_version IS NULL AND NEW.current_request_version=OLD.current_request_version) OR
       (NEW.current_scope_version IS NOT NULL AND NEW.current_scope_version < OLD.highest_activated_scope_version) THEN
      RAISE EXCEPTION 'Request identity and activated version history cannot be replaced or rewound' USING ERRCODE='23514';
    END IF;
    NEW.highest_activated_scope_version:=greatest(OLD.highest_activated_scope_version,coalesce(NEW.current_scope_version,0));
  END IF;
  RETURN NEW;
END $$;

-- Bootstrap any current pointers when upgrading; future changes cannot lower
-- this field, including attempts that directly write the watermark column.
UPDATE opc.requests SET highest_activated_scope_version=coalesce(current_scope_version,0);

CREATE OR REPLACE FUNCTION opc.check_current_scope() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM opc.requests r JOIN opc.scope_versions s ON s.request_id=r.id AND s.version=r.current_scope_version
    WHERE r.id=NEW.id AND s.request_version<>r.current_request_version) THEN
    RAISE EXCEPTION 'Current scope must describe the current original request' USING ERRCODE='23514';
  END IF;
  RETURN NULL;
END $$;
