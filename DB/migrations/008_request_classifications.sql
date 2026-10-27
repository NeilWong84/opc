-- 开发需求双语分类字典；原服务线 development 与技术整理原文 category 保持独立。
CREATE TABLE opc.development_platforms (
  id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*$'),
  name_zh text NOT NULL CHECK (btrim(name_zh) <> ''),
  name_ja text NOT NULL CHECK (btrim(name_ja) <> ''),
  sort_order integer NOT NULL CHECK (sort_order >= 0),
  enabled boolean NOT NULL DEFAULT true,
  updated_usr uuid REFERENCES opc.accounts(id),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE opc.development_types (LIKE opc.development_platforms INCLUDING ALL);
ALTER TABLE opc.development_types ADD FOREIGN KEY (updated_usr) REFERENCES opc.accounts(id);
CREATE TRIGGER zz_maintenance BEFORE INSERT OR UPDATE ON opc.development_platforms
  FOR EACH ROW EXECUTE FUNCTION opc.maintain_row_metadata();
CREATE TRIGGER zz_maintenance BEFORE INSERT OR UPDATE ON opc.development_types
  FOR EACH ROW EXECUTE FUNCTION opc.maintain_row_metadata();

INSERT INTO opc.development_platforms(code,name_zh,name_ja,sort_order) VALUES
('web','Web开发','Webアプリ開発',10),
('website','网站开发','Webサイト制作',20),
('android','Android开发','Androidアプリ開発',30),
('ios','iOS开发','iOSアプリ開発',40),
('desktop','桌面开发','デスクトップアプリ開発',50);
INSERT INTO opc.development_types(code,name_zh,name_ja,sort_order) VALUES
('crm','CRM','顧客管理（CRM）',10),
('hr','HR人力系统','人事管理システム（HR）',20),
('vehicle','车辆管理系统','車両管理システム',30),
('pos','收银销售','レジ・販売管理',40),
('oa','OA系统','オフィス業務システム（OA）',50),
('general','通用信息化系统','汎用業務システム',60);

-- 每个需求版本记录主要开发端及开发类型；NULL 为未分类，不猜测存量原文。
ALTER TABLE opc.request_drafts
  ADD COLUMN platform_code text REFERENCES opc.development_platforms(code),
  ADD COLUMN development_type_code text REFERENCES opc.development_types(code);
ALTER TABLE opc.request_versions
  ADD COLUMN platform_code text REFERENCES opc.development_platforms(code),
  ADD COLUMN development_type_code text REFERENCES opc.development_types(code);
CREATE INDEX request_versions_classification_idx
  ON opc.request_versions(platform_code,development_type_code,request_id,version);

COMMENT ON TABLE opc.development_platforms IS '开发端双语字典；与服务线和技术整理原文分类独立。';
COMMENT ON TABLE opc.development_types IS '开发类型双语字典；固定代码关联需求版本，名称按界面语言显示。';
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['development_platforms','development_types'] LOOP
    EXECUTE format('COMMENT ON COLUMN opc.%I.id IS %L',t,'记录唯一标识，不可修改。');
    EXECUTE format('COMMENT ON COLUMN opc.%I.code IS %L',t,'稳定分类代码，供需求关联与精确检索，不随语言改变。');
    EXECUTE format('COMMENT ON COLUMN opc.%I.name_zh IS %L',t,'简体中文显示名称。');
    EXECUTE format('COMMENT ON COLUMN opc.%I.name_ja IS %L',t,'日语显示名称。');
    EXECUTE format('COMMENT ON COLUMN opc.%I.sort_order IS %L',t,'界面排序，数值小的优先。');
    EXECUTE format('COMMENT ON COLUMN opc.%I.enabled IS %L',t,'是否允许新选用；停用不删除历史关联。');
    EXECUTE format('COMMENT ON COLUMN opc.%I.updated_usr IS %L',t,'可信事务更新账号；无业务账号的维护操作为空。');
    EXECUTE format('COMMENT ON COLUMN opc.%I.updated_at IS %L',t,'数据库维护的最近写入时间。');
  END LOOP;
END $$;
COMMENT ON COLUMN opc.request_drafts.platform_code IS '草稿主要开发端代码；空值表示未分类。';
COMMENT ON COLUMN opc.request_drafts.development_type_code IS '草稿开发类型代码；空值表示未分类。';
COMMENT ON COLUMN opc.request_versions.platform_code IS '本次原始需求版本的主要开发端代码；空值表示未分类。';
COMMENT ON COLUMN opc.request_versions.development_type_code IS '本次原始需求版本的开发类型代码；空值表示未分类。';
REVOKE ALL ON opc.development_platforms,opc.development_types FROM PUBLIC;
