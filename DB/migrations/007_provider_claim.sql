-- 客户明确确认发布范围和条款后，当前内部承接者自行承接。
ALTER TABLE opc.conversation_threads DROP CONSTRAINT conversation_threads_kind_check;
ALTER TABLE opc.conversation_threads ADD CHECK (kind IN ('consultation','negotiation','customer_project','internal'));
ALTER TABLE opc.conversation_threads DROP CONSTRAINT conversation_threads_check;
ALTER TABLE opc.conversation_threads ADD CHECK (
  (kind IN ('consultation','negotiation') AND initiator_id IS NOT NULL AND engagement_id IS NULL) OR
  (kind='customer_project' AND engagement_id IS NOT NULL AND initiator_id IS NULL) OR
  (kind='internal' AND initiator_id IS NULL));
CREATE UNIQUE INDEX negotiations_initiator_uq ON opc.conversation_threads(request_id,initiator_id) WHERE kind='negotiation';
COMMENT ON COLUMN opc.conversation_threads.kind IS '会话类型：consultation 为原有本人向运营咨询，negotiation 为需求客户与特定承接者的合作沟通，customer_project 为已建立合作会话，internal 为运营内部会话。';

CREATE TABLE opc.claim_proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES opc.conversation_threads(id),
  publication_id uuid NOT NULL REFERENCES opc.publications(id),
  provider_id uuid NOT NULL REFERENCES opc.accounts(id),
  terms text NOT NULL CHECK (char_length(btrim(terms)) BETWEEN 1 AND 12000),
  quoted_amount numeric(14,0) CHECK (quoted_amount>=0),
  due_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  confirmed_by uuid REFERENCES opc.accounts(id),
  confirmed_at timestamptz,
  row_version bigint NOT NULL DEFAULT 1,
  updated_usr uuid REFERENCES opc.accounts(id),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((confirmed_by IS NULL) = (confirmed_at IS NULL))
);
CREATE INDEX claim_proposals_thread_idx ON opc.claim_proposals(thread_id,created_at DESC,id);
CREATE TRIGGER touch_claim_proposal BEFORE UPDATE ON opc.claim_proposals FOR EACH ROW EXECUTE FUNCTION opc.touch_row();
CREATE TRIGGER zz_maintenance BEFORE INSERT OR UPDATE ON opc.claim_proposals FOR EACH ROW EXECUTE FUNCTION opc.maintain_row_metadata();
CREATE TRIGGER audit_claim_proposal AFTER INSERT OR UPDATE OR DELETE ON opc.claim_proposals FOR EACH ROW EXECUTE FUNCTION opc.record_audit();
CREATE FUNCTION opc.guard_claim_proposal() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION '合作沟通条款历史不可删除' USING ERRCODE='55000'; END IF;
  IF TG_OP='UPDATE' AND ((NEW.id,NEW.thread_id,NEW.publication_id,NEW.provider_id,NEW.terms,NEW.quoted_amount,NEW.due_at,NEW.created_at)
    IS DISTINCT FROM (OLD.id,OLD.thread_id,OLD.publication_id,OLD.provider_id,OLD.terms,OLD.quoted_amount,OLD.due_at,OLD.created_at)
    OR OLD.confirmed_at IS NOT NULL) THEN
    RAISE EXCEPTION '合作沟通条款及既有确认不可改写' USING ERRCODE='55000';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM opc.conversation_threads t JOIN opc.publications p ON p.request_id=t.request_id
    WHERE t.id=NEW.thread_id AND t.kind='negotiation' AND t.initiator_id=NEW.provider_id AND p.id=NEW.publication_id) THEN
    RAISE EXCEPTION '条款须绑定真实承接者沟通及该需求的发布版本' USING ERRCODE='23514';
  END IF;
  IF NEW.confirmed_by IS NOT NULL AND NOT EXISTS(SELECT 1 FROM opc.conversation_threads t JOIN opc.requests r ON r.id=t.request_id
    WHERE t.id=NEW.thread_id AND r.customer_id=NEW.confirmed_by) THEN
    RAISE EXCEPTION '只能由实际需求客户确认' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_claim_proposal BEFORE INSERT OR UPDATE OR DELETE ON opc.claim_proposals FOR EACH ROW EXECUTE FUNCTION opc.guard_claim_proposal();
COMMENT ON TABLE opc.claim_proposals IS '承接前沟通中的不可变条款提案，绑定审核发布版本；客户显式确认后当前提案承接者可承接，不代表付款或正式认证。';
COMMENT ON COLUMN opc.claim_proposals.id IS '沟通条款提案唯一标识。';
COMMENT ON COLUMN opc.claim_proposals.thread_id IS '客户与特定承接者的沟通会话。';
COMMENT ON COLUMN opc.claim_proposals.publication_id IS '客户确认的审核发布版本；下架或换版后不能继续承接。';
COMMENT ON COLUMN opc.claim_proposals.provider_id IS '提出条款且有权承接的内部账号。';
COMMENT ON COLUMN opc.claim_proposals.terms IS '双方确认的条款原文，提交后不可修改；修改须新增提案并重新确认。';
COMMENT ON COLUMN opc.claim_proposals.quoted_amount IS '约定报价，单位 JPY，可为空，不代表已收款。';
COMMENT ON COLUMN opc.claim_proposals.due_at IS '约定期限，带时区时间，可为空。';
COMMENT ON COLUMN opc.claim_proposals.created_at IS '提案创建时间。';
COMMENT ON COLUMN opc.claim_proposals.confirmed_by IS '实际点击确认的需求客户账号；未确认时为空。';
COMMENT ON COLUMN opc.claim_proposals.confirmed_at IS '客户实际确认时间；未确认时为空。';
COMMENT ON COLUMN opc.claim_proposals.row_version IS '提案并发版本号，确认需提交当前版本。';
COMMENT ON COLUMN opc.claim_proposals.updated_usr IS '可信事务内的业务操作账号；无账号维护时为空。';
COMMENT ON COLUMN opc.claim_proposals.updated_at IS '数据库自动维护的最近更新时间。';
