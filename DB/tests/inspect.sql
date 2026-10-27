\set ON_ERROR_STOP on
SELECT current_database() AS database,current_user AS maintenance_user,
  current_setting('server_version') AS server_version,
  current_setting('server_encoding') AS encoding,current_setting('TimeZone') AS timezone;
SELECT datname,pg_get_userbyid(datdba) AS owner,datlocprovider,datlocale,
  shobj_description(oid,'pg_database') AS ownership_marker
FROM pg_database WHERE datname=current_database();
SELECT count(*) FILTER(WHERE relkind='r') AS tables,
  count(*) FILTER(WHERE relkind='v') AS views
FROM pg_class WHERE relnamespace='opc'::regnamespace AND relkind IN ('r','v');
SELECT version,checksum,applied_at FROM opc.schema_migrations ORDER BY version;
SELECT code,name_ja,name_zh,enabled FROM opc.service_types;
SELECT code,name_ja,name_zh FROM opc.roles ORDER BY code;
SELECT format('SELECT %L AS table_name, count(*) AS rows FROM opc.%I;',tablename,tablename)
FROM pg_tables WHERE schemaname='opc' ORDER BY tablename
\gexec
-- PUBLIC (grantee 0) should hold no database/schema/object privileges here.
SELECT 'database' AS object_type,d.datname AS object_name,a.privilege_type
FROM pg_database d CROSS JOIN LATERAL aclexplode(coalesce(d.datacl,acldefault('d',d.datdba))) a
WHERE d.datname=current_database() AND a.grantee=0
UNION ALL
SELECT 'schema',n.nspname,a.privilege_type
FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a
WHERE n.nspname IN ('opc','public') AND a.grantee=0
UNION ALL
SELECT 'relation',c.relname,a.privilege_type
FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault(CASE WHEN c.relkind='S' THEN 'S'::"char" ELSE 'r'::"char" END,c.relowner))) a
WHERE c.relnamespace='opc'::regnamespace AND c.relkind IN ('r','v','S') AND a.grantee=0
UNION ALL
SELECT 'function',p.proname,a.privilege_type
FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
WHERE p.pronamespace='opc'::regnamespace AND a.grantee=0;

-- 中文结构说明覆盖率：表、视图和各自字段均应全部覆盖。
SELECT CASE c.relkind WHEN 'r' THEN '表' ELSE '视图' END AS 对象类型,
  count(DISTINCT c.oid) AS 对象数,
  count(DISTINCT c.oid) FILTER(WHERE coalesce(obj_description(c.oid,'pg_class'),'') ~ '[一-龥]') AS 中文对象注释数,
  count(*) AS 字段数,
  count(*) FILTER(WHERE coalesce(col_description(c.oid,a.attnum),'') ~ '[一-龥]') AS 中文字段注释数
FROM pg_class c JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
WHERE c.relnamespace='opc'::regnamespace AND c.relkind IN ('r','v') GROUP BY c.relkind ORDER BY c.relkind;

-- 输出应为零行：每张持久化表必须具备三个统一字段。
SELECT c.relname AS 缺失统一字段的表
FROM pg_class c JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
WHERE c.relnamespace='opc'::regnamespace AND c.relkind='r'
GROUP BY c.relname HAVING count(*) FILTER(WHERE a.attname IN ('id','updated_usr','updated_at'))<>3;
