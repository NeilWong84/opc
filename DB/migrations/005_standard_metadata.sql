-- 统一所有业务及支撑表的记录标识、更新用户和更新时间。
-- 原有主键、复合业务唯一约束、外键和只追加历史规则保持有效。
DO $$
DECLARE t record;
BEGIN
  FOR t IN SELECT c.oid,c.relname FROM pg_class c
    WHERE c.relnamespace='opc'::regnamespace AND c.relkind='r' ORDER BY c.relname LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid=t.oid AND attname='id' AND attnum>0 AND NOT attisdropped) THEN
      EXECUTE format('ALTER TABLE opc.%I ADD COLUMN id uuid NOT NULL DEFAULT gen_random_uuid()',t.relname);
      EXECUTE format('ALTER TABLE opc.%I ADD CONSTRAINT %I UNIQUE (id)',t.relname,t.relname||'_id_key');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid=t.oid AND attname='updated_at' AND attnum>0 AND NOT attisdropped) THEN
      -- 已存在的记录以本次补列时间初始化，不能当作其原始业务事件发生时间。
      EXECUTE format('ALTER TABLE opc.%I ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now()',t.relname);
    END IF;
    EXECUTE format('ALTER TABLE opc.%I ADD COLUMN updated_usr uuid REFERENCES opc.accounts(id)',t.relname);
  END LOOP;
END $$;

-- 更新时间统一由后置维护触发器写入；原触发器仅负责乐观并发版本递增。
CREATE OR REPLACE FUNCTION opc.touch_row() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.row_version:=OLD.row_version+1;
  RETURN NEW;
END $$;

CREATE FUNCTION opc.maintain_row_metadata() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='UPDATE' AND NEW.id IS DISTINCT FROM OLD.id THEN
    RAISE EXCEPTION '记录唯一标识不可修改' USING ERRCODE='55000';
  END IF;
  -- 归因来自可信后端事务，不以客户端传入的字段值证明用户身份。
  -- 本地维护没有指定业务账号时为空，不继承上次修改人的身份。
  NEW.updated_usr:=nullif(current_setting('opc.actor_id',true),'')::uuid;
  NEW.updated_at:=clock_timestamp();
  RETURN NEW;
END $$;

DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT relname FROM pg_class WHERE relnamespace='opc'::regnamespace AND relkind='r' ORDER BY relname LOOP
    -- 同事件触发器按名字排序：先运行业务及历史保护，再写系统维护字段。
    EXECUTE format('CREATE TRIGGER zz_maintenance BEFORE INSERT OR UPDATE ON opc.%I FOR EACH ROW EXECUTE FUNCTION opc.maintain_row_metadata()',t.relname);
  END LOOP;
END $$;

-- 迁移登记只允许追加，通用维护列不能成为改写历史校验值的入口。
CREATE TRIGGER immutable_migration_history BEFORE UPDATE OR DELETE ON opc.schema_migrations
  FOR EACH ROW EXECUTE FUNCTION opc.prevent_history_change();
CREATE TRIGGER immutable_migration_truncate BEFORE TRUNCATE ON opc.schema_migrations
  FOR EACH STATEMENT EXECUTE FUNCTION opc.prevent_history_change();

COMMENT ON FUNCTION opc.maintain_row_metadata() IS '通用维护字段触发器：禁止修改记录标识，根据当前事务的业务账号设置更新用户，并自动记录本次写入时间；归因字段不替代身份验证。';
COMMENT ON FUNCTION opc.touch_row() IS '业务行更新时递增乐观并发版本号；更新时间由统一维护触发器设置。';
