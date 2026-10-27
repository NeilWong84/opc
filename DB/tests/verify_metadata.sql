\set ON_ERROR_STOP on
\echo 'OPC 统一字段验证：所有测试数据和辅助对象均在结束后回滚。'

-- 在迁移 005 和 006 完成后执行。本文件不主动建立数据库连接。
-- 测试数据最终回滚，但 PostgreSQL 标识列序列取号可能继续递增。
BEGIN;

CREATE TEMP TABLE metadata_verification_results (
  assertion text NOT NULL,
  expected_sqlstate text
) ON COMMIT DROP;

CREATE FUNCTION pg_temp.metadata_assert(condition boolean, description text)
RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN
    RAISE EXCEPTION '统一字段验证未通过：%', description;
  END IF;
  INSERT INTO metadata_verification_results VALUES (description, NULL);
END;
$function$;

CREATE FUNCTION pg_temp.metadata_expect_error(statement text, expected_sqlstate text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
  actual_sqlstate text;
  actual_message text;
BEGIN
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      actual_sqlstate = RETURNED_SQLSTATE,
      actual_message = MESSAGE_TEXT;
  END;
  IF actual_sqlstate IS NULL THEN
    RAISE EXCEPTION '预期 SQLSTATE %，但语句意外成功：%',
      expected_sqlstate, statement;
  END IF;
  IF actual_sqlstate <> expected_sqlstate THEN
    RAISE EXCEPTION '预期 SQLSTATE %，实际收到 %（%）：%',
      expected_sqlstate, actual_sqlstate, actual_message, statement;
  END IF;
  INSERT INTO metadata_verification_results VALUES (statement, expected_sqlstate);
END;
$function$;

DO $catalog_verification$
DECLARE
  table_record record;
  id_attribute smallint;
  actor_attribute smallint;
  accounts_id_attribute smallint;
  primary_key_columns text[];
  primary_key_record record;
BEGIN
  PERFORM pg_temp.metadata_assert(
    (SELECT count(*) = 40 FROM pg_class
      WHERE relnamespace = 'opc'::regnamespace AND relkind = 'r'),
    'opc 包含预期的 40 张持久化表');
  PERFORM pg_temp.metadata_assert(
    (SELECT count(*) = 2 FROM pg_class
      WHERE relnamespace = 'opc'::regnamespace AND relkind = 'v'),
    'opc 保留两个任务大厅视图');

  SELECT attnum INTO accounts_id_attribute FROM pg_attribute
  WHERE attrelid = 'opc.accounts'::regclass AND attname = 'id' AND NOT attisdropped;

  FOR table_record IN
    SELECT oid, relname FROM pg_class
    WHERE relnamespace = 'opc'::regnamespace AND relkind = 'r'
    ORDER BY relname
  LOOP
    PERFORM pg_temp.metadata_assert(
      (SELECT count(*) = 3 FROM pg_attribute
        WHERE attrelid = table_record.oid AND attnum > 0 AND NOT attisdropped
          AND attname IN ('id', 'updated_usr', 'updated_at')),
      table_record.relname || '：三个统一字段均存在');

    SELECT attnum INTO id_attribute FROM pg_attribute
    WHERE attrelid = table_record.oid AND attname = 'id' AND NOT attisdropped;
    PERFORM pg_temp.metadata_assert(
      (SELECT attnotnull AND atttypid =
        CASE WHEN table_record.relname = 'audit_events' THEN 'bigint'::regtype ELSE 'uuid'::regtype END
        FROM pg_attribute WHERE attrelid = table_record.oid AND attnum = id_attribute)
      AND EXISTS (SELECT 1 FROM pg_index i
        WHERE i.indrelid = table_record.oid AND i.indisunique AND i.indisvalid
          AND i.indnkeyatts = 1 AND i.indkey[0] = id_attribute
          AND i.indpred IS NULL AND i.indexprs IS NULL),
      table_record.relname || '：id 非空、独立唯一且类型正确');

    SELECT attnum INTO actor_attribute FROM pg_attribute
    WHERE attrelid = table_record.oid AND attname = 'updated_usr' AND NOT attisdropped;
    PERFORM pg_temp.metadata_assert(
      (SELECT NOT attnotnull AND atttypid = 'uuid'::regtype
        FROM pg_attribute WHERE attrelid = table_record.oid AND attnum = actor_attribute)
      AND EXISTS (SELECT 1 FROM pg_constraint
        WHERE conrelid = table_record.oid AND contype = 'f' AND convalidated
          AND conkey = ARRAY[actor_attribute]
          AND confrelid = 'opc.accounts'::regclass
          AND confkey = ARRAY[accounts_id_attribute]),
      table_record.relname || '：updated_usr 为可空 UUID，外键关联 accounts');

    PERFORM pg_temp.metadata_assert(
      (SELECT attnotnull AND atttypid = 'timestamptz'::regtype
        FROM pg_attribute WHERE attrelid = table_record.oid
          AND attname = 'updated_at' AND NOT attisdropped),
      table_record.relname || '：updated_at 为非空 timestamptz');
  END LOOP;

  PERFORM pg_temp.metadata_assert(
    (SELECT attidentity = 'a' FROM pg_attribute
      WHERE attrelid = 'opc.audit_events'::regclass AND attname = 'id')
    AND pg_get_serial_sequence('opc.audit_events', 'id') IS NOT NULL,
    'audit_events 保留 bigint GENERATED ALWAYS 标识列及其原序列');

  -- 这 15 张表新增了独立 id，原主键仍用于业务唯一性和既有复合外键关系。
  FOR primary_key_record IN
    SELECT * FROM (VALUES
      ('schema_migrations', ARRAY['version']),
      ('password_credentials', ARRAY['account_id']),
      ('roles', ARRAY['code']),
      ('service_types', ARRAY['code']),
      ('request_drafts', ARRAY['customer_id']),
      ('request_versions', ARRAY['request_id','version']),
      ('scope_versions', ARRAY['request_id','version']),
      ('draft_files', ARRAY['customer_id','file_id']),
      ('request_files', ARRAY['request_id','request_version','file_id']),
      ('scope_files', ARRAY['request_id','scope_version','file_id']),
      ('publication_files', ARRAY['publication_id','file_id']),
      ('agreement_versions', ARRAY['engagement_id','version']),
      ('agreement_confirmations', ARRAY['engagement_id','agreement_version','party']),
      ('delivery_files', ARRAY['delivery_id','file_id']),
      ('idempotency_keys', ARRAY['actor_id','operation','key'])
    ) AS expected(table_name, column_names)
  LOOP
    SELECT array_agg(a.attname::text ORDER BY k.position) INTO primary_key_columns
    FROM pg_constraint c
    CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attribute_number, position)
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attribute_number
    WHERE c.conrelid = to_regclass('opc.' || primary_key_record.table_name)
      AND c.contype = 'p';
    PERFORM pg_temp.metadata_assert(primary_key_columns = primary_key_record.column_names,
      primary_key_record.table_name || '：原主键保持不变');
  END LOOP;

  -- 覆盖检查发现缺失或纯英文注释；中文描述的业务含义另在迁移源码中审阅。
  PERFORM pg_temp.metadata_assert(
    NOT EXISTS (SELECT 1 FROM pg_class c
      WHERE c.relnamespace = 'opc'::regnamespace AND c.relkind IN ('r','v')
        AND coalesce(obj_description(c.oid, 'pg_class'), '') !~ '[一-龥]'),
    'opc 全部表和视图都有包含中文汉字的说明');
  PERFORM pg_temp.metadata_assert(
    NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_attribute a ON a.attrelid = c.oid
      WHERE c.relnamespace = 'opc'::regnamespace AND c.relkind IN ('r','v')
        AND a.attnum > 0 AND NOT a.attisdropped
        AND coalesce(col_description(c.oid, a.attnum), '') !~ '[一-龥]'),
    'opc 全部表字段和视图字段都有包含中文汉字的说明');
END;
$catalog_verification$;

DO $behavior_verification$
DECLARE
  actor_one uuid := gen_random_uuid();
  actor_two uuid := gen_random_uuid();
  customer uuid := gen_random_uuid();
  request_id uuid := gen_random_uuid();
  clarification_id uuid := gen_random_uuid();
  grant_id uuid := gen_random_uuid();
  role_id uuid;
  suffix text := replace(gen_random_uuid()::text, '-', '');
  role_code text;
  migration_version text;
  stored_actor uuid;
  stored_time timestamptz;
  started_at timestamptz;
  old_row_version bigint;
  stored_row_version bigint;
  audit_id bigint;
  existing_migration text;
BEGIN
  role_code := 'metadata_verify_' || suffix;
  migration_version := '999_metadata_verify_' || suffix;
  -- 归因配置仅在当前事务内生效，回滚后恢复原状态。空值表示系统写入，
  -- 不创建虚构的系统账号或持久登录凭据。
  PERFORM set_config('opc.actor_id', '', true);
  INSERT INTO opc.accounts(id, email, display_name) VALUES
    (actor_one, 'metadata.first.' || suffix || '@example.invalid', '维护字段验证人员一'),
    (actor_two, 'metadata.second.' || suffix || '@example.invalid', '维护字段验证人员二'),
    (customer, 'metadata.customer.' || suffix || '@example.invalid', '维护字段验证客户');
  PERFORM pg_temp.metadata_assert(
    (SELECT count(*) = 3 FROM opc.accounts
      WHERE id IN (actor_one, actor_two, customer) AND updated_usr IS NULL AND updated_at IS NOT NULL),
    '系统新增记录自动写入时间，用户归因为 NULL');

  PERFORM set_config('opc.actor_id', actor_one::text, true);
  started_at := clock_timestamp();
  INSERT INTO opc.roles(code, name_ja, name_zh, description, updated_usr, updated_at)
  VALUES (role_code, '検証用', '验证角色', '仅事务回滚验证', actor_two, '2000-01-01T00:00:00Z')
  RETURNING id, updated_usr, updated_at INTO role_id, stored_actor, stored_time;
  PERFORM pg_temp.metadata_assert(role_id IS NOT NULL AND stored_actor = actor_one
    AND stored_time >= started_at AND stored_time <= clock_timestamp(),
    '新增记录自动生成 id，并用事务归因和当前时间覆盖传入的维护字段');

  SELECT row_version INTO old_row_version FROM opc.accounts WHERE id = customer;
  started_at := clock_timestamp();
  UPDATE opc.accounts SET display_name = '第一次维护', row_version = 9000,
    updated_usr = actor_two, updated_at = '2000-01-01T00:00:00Z'
  WHERE id = customer
  RETURNING updated_usr, updated_at, row_version INTO stored_actor, stored_time, stored_row_version;
  PERFORM pg_temp.metadata_assert(stored_actor = actor_one
    AND stored_time >= started_at AND stored_time <= clock_timestamp()
    AND stored_row_version = old_row_version + 1,
    '更新覆盖传入的维护字段，row_version 恰好递增一次');
  PERFORM pg_temp.metadata_assert(
    (SELECT application_actor_id = actor_one AND updated_usr = actor_one
      FROM opc.audit_events WHERE table_name = 'accounts' AND operation = 'UPDATE'
        AND entity_key->>'id' = customer::text ORDER BY id DESC LIMIT 1),
    '自动审计的事件归因和维护字段记录同一事务操作者');

  PERFORM set_config('opc.actor_id', actor_two::text, true);
  UPDATE opc.accounts SET display_name = '第二次维护' WHERE id = customer
  RETURNING updated_usr INTO stored_actor;
  PERFORM pg_temp.metadata_assert(stored_actor = actor_two,
    '切换事务操作者后，后续写入记录新的操作者');
  PERFORM set_config('opc.actor_id', '', true);
  UPDATE opc.accounts SET display_name = '系统维护' WHERE id = customer
  RETURNING updated_usr INTO stored_actor;
  PERFORM pg_temp.metadata_assert(stored_actor IS NULL,
    '系统更新将归因设为 NULL，不沿用上次人工操作者');
  PERFORM pg_temp.metadata_assert(
    (SELECT application_actor_id IS NULL AND updated_usr IS NULL
      FROM opc.audit_events WHERE table_name = 'accounts' AND operation = 'UPDATE'
        AND entity_key->>'id' = customer::text ORDER BY id DESC LIMIT 1),
    '系统更新的审计记录也保持 NULL 应用用户归因');

  PERFORM pg_temp.metadata_expect_error(format(
    'UPDATE opc.roles SET id = %L WHERE id = %L', gen_random_uuid(), role_id), '55000');
  PERFORM pg_temp.metadata_assert(
    EXISTS (SELECT 1 FROM opc.roles WHERE code = role_code AND id = role_id),
    'id 改写被拒绝后，原生成标识保持不变');

  PERFORM set_config('opc.actor_id', actor_one::text, true);
  INSERT INTO opc.account_roles(id, account_id, role_code, granted_by, reason)
  VALUES (grant_id, customer, role_code, actor_one, '验证一次性关闭与维护字段兼容');
  PERFORM set_config('opc.actor_id', actor_two::text, true);
  UPDATE opc.account_roles SET revoked_by = actor_two, revoked_at = clock_timestamp()
  WHERE id = grant_id;
  PERFORM pg_temp.metadata_assert(
    (SELECT revoked_by = actor_two AND revoked_at IS NOT NULL
      AND updated_usr = actor_two AND updated_at >= revoked_at
      FROM opc.account_roles WHERE id = grant_id),
    '合法角色撤销通过历史校验后，自动写入维护字段');
  PERFORM pg_temp.metadata_expect_error(format(
    'UPDATE opc.account_roles SET revoked_at = clock_timestamp() WHERE id = %L', grant_id), '55000');

  PERFORM set_config('opc.actor_id', actor_one::text, true);
  INSERT INTO opc.requests(id, public_code, customer_id)
  VALUES (request_id, 'VERIFY-META-' || suffix, customer);
  INSERT INTO opc.request_versions(request_id, version, original_description, timing_text, budget_text, submitted_by)
  VALUES (request_id, 1, '验证统一维护字段不会覆盖客户提交的原始需求内容。', '待协商', '待协商', customer);
  -- 先完成需求与原文版本的循环延迟外键，再验证只能答复一次的历史保护。
  -- 本次测试使用显式需求编号，不消耗正式业务编号序列。
  SET CONSTRAINTS ALL IMMEDIATE;
  INSERT INTO opc.clarifications(id, request_id, request_version, question, asked_by)
  VALUES (clarification_id, request_id, 1, '请说明适用用户范围。', actor_one);
  PERFORM set_config('opc.actor_id', customer::text, true);
  UPDATE opc.clarifications SET answer = '仅供内部受控成员使用。',
    answered_by = customer, answered_at = clock_timestamp()
  WHERE id = clarification_id;
  PERFORM pg_temp.metadata_assert(
    (SELECT question = '请说明适用用户范围。' AND answer = '仅供内部受控成员使用。'
      AND answered_by = customer AND updated_usr = customer AND updated_at >= answered_at
      FROM opc.clarifications WHERE id = clarification_id),
    '合法澄清答复保留原问题，并记录答复事务的维护信息');
  PERFORM pg_temp.metadata_expect_error(format(
    'UPDATE opc.clarifications SET answer = %L WHERE id = %L', '覆盖原答复', clarification_id), '55000');
  PERFORM pg_temp.metadata_expect_error(format(
    'UPDATE opc.request_versions SET updated_at = clock_timestamp() WHERE request_id = %L AND version = 1',
    request_id), '55000');

  SELECT id INTO audit_id FROM opc.audit_events
  WHERE table_name = 'clarifications' AND operation = 'UPDATE'
    AND entity_key->>'id' = clarification_id::text ORDER BY id DESC LIMIT 1;
  PERFORM pg_temp.metadata_assert(audit_id IS NOT NULL,
    '已答复澄清生成结构变更审计记录');
  PERFORM pg_temp.metadata_expect_error(format(
    'UPDATE opc.audit_events SET updated_at = clock_timestamp() WHERE id = %s', audit_id), '55000');

  SELECT version INTO existing_migration FROM opc.schema_migrations ORDER BY version LIMIT 1;
  PERFORM pg_temp.metadata_assert(existing_migration IS NOT NULL,
    '迁移登记表已有历史记录，可验证其不可改写保护');
  PERFORM pg_temp.metadata_expect_error(format(
    'UPDATE opc.schema_migrations SET updated_at = clock_timestamp() WHERE version = %L', existing_migration), '55000');
  PERFORM pg_temp.metadata_expect_error(format(
    'DELETE FROM opc.schema_migrations WHERE version = %L', existing_migration), '55000');
  PERFORM pg_temp.metadata_expect_error('TRUNCATE opc.schema_migrations', '55000');

  PERFORM set_config('opc.actor_id', '', true);
  INSERT INTO opc.schema_migrations(version, checksum)
  VALUES (migration_version, repeat('a', 64));
  PERFORM pg_temp.metadata_assert(
    (SELECT id IS NOT NULL AND updated_usr IS NULL AND updated_at IS NOT NULL
      FROM opc.schema_migrations WHERE version = migration_version),
    '迁移封装仍可仅提供版本和校验值追加新记录，维护字段自动填写');
  SET CONSTRAINTS ALL IMMEDIATE;
END;
$behavior_verification$;

SELECT count(*) AS "通过断言数",
  count(*) FILTER (WHERE expected_sqlstate IS NOT NULL) AS "预期拒绝数"
FROM metadata_verification_results;

ROLLBACK;
\echo 'OPC 统一字段验证通过；所有测试数据已回滚。'
