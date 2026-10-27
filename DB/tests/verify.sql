\set ON_ERROR_STOP on
\echo 'OPC schema verification: all fixture rows are rolled back.'

-- Run after the migrations with: psql -v ON_ERROR_STOP=1 -f DB/tests/verify.sql
-- This script never creates a real login, password, or customer file. PostgreSQL
-- sequences may advance even though all fixture rows and helper objects roll back.
BEGIN;

CREATE TEMP TABLE verification_results (
  assertion text NOT NULL,
  expected_sqlstate text
) ON COMMIT DROP;

CREATE FUNCTION pg_temp.assert_true(condition boolean, description text)
RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Assertion failed: %', description;
  END IF;
  INSERT INTO verification_results VALUES (description, NULL);
END;
$function$;

CREATE FUNCTION pg_temp.expect_error(statement text, expected_sqlstate text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
  actual_sqlstate text;
  actual_message text;
BEGIN
  -- The inner block is a subtransaction: rejected writes cannot contaminate the
  -- next assertion, and an unexpectedly successful statement fails the script.
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      actual_sqlstate = RETURNED_SQLSTATE,
      actual_message = MESSAGE_TEXT;
  END;
  IF actual_sqlstate IS NULL THEN
    RAISE EXCEPTION 'Expected SQLSTATE %, but statement succeeded: %',
      expected_sqlstate, statement;
  END IF;
  IF actual_sqlstate <> expected_sqlstate THEN
    RAISE EXCEPTION 'Expected SQLSTATE %, received % (%): %',
      expected_sqlstate, actual_sqlstate, actual_message, statement;
  END IF;
  INSERT INTO verification_results VALUES (statement, expected_sqlstate);
END;
$function$;

DO $verification$
#variable_conflict use_variable
DECLARE
  customer uuid := gen_random_uuid();
  provider uuid := gen_random_uuid();
  operator_account uuid := gen_random_uuid();
  other_customer uuid := gen_random_uuid();
  request_id uuid := gen_random_uuid();
  other_request uuid := gen_random_uuid();
  visible_file uuid := gen_random_uuid();
  private_file uuid := gen_random_uuid();
  pending_file uuid := gen_random_uuid();
  rejected_file uuid := gen_random_uuid();
  source_file uuid := gen_random_uuid();
  compliance_review uuid := gen_random_uuid();
  technical_review uuid := gen_random_uuid();
  other_scope_compliance uuid := gen_random_uuid();
  other_scope_technical uuid := gen_random_uuid();
  rejected_scope_compliance uuid := gen_random_uuid();
  rejected_scope_technical uuid := gen_random_uuid();
  publication uuid := gen_random_uuid();
  engagement uuid := gen_random_uuid();
  assignment uuid := gen_random_uuid();
  delivery_one uuid := gen_random_uuid();
  delivery_two uuid := gen_random_uuid();
  delivery_three uuid := gen_random_uuid();
  qa_one uuid := gen_random_uuid();
  qa_two uuid := gen_random_uuid();
  qa_three uuid := gen_random_uuid();
  audit_id bigint;
  provider_authorization uuid := gen_random_uuid();
  email_suffix text := replace(gen_random_uuid()::text, '-', '');
  delivery_insert text;
BEGIN
  -- Use random IDs and explicit public codes; do not assume an empty database or
  -- consume the production request-number sequence for test requests.
  INSERT INTO opc.accounts (id, email, display_name, ui_locale) VALUES
    (customer, 'verify.zh.' || email_suffix || '@example.invalid', '验证客户', 'zh'),
    (provider, 'verify.ja.' || email_suffix || '@example.invalid', '検証担当者', 'ja'),
    (operator_account, 'verify.ops.' || email_suffix || '@example.invalid', '验证运营', 'ja'),
    (other_customer, 'verify.other.' || email_suffix || '@example.invalid', '其他客户', 'zh');
  PERFORM pg_temp.assert_true(
    (SELECT ui_locale = 'zh' FROM opc.accounts WHERE id = customer)
    AND (SELECT ui_locale = 'ja' FROM opc.accounts WHERE id = provider),
    'accounts persist Chinese and Japanese preferences independently');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.accounts(email,display_name) VALUES (%L,%L)',
    'VERIFY.ZH.' || upper(email_suffix) || '@EXAMPLE.INVALID', '重复邮箱'), '23505');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.accounts(email,display_name,ui_locale) VALUES (%L,%L,%L)',
    'verify.invalid.' || email_suffix || '@example.invalid', '无效语言', 'en'), '23514');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.password_credentials(account_id,password_hash) VALUES (%L,%L)',
    customer, 'plaintext-password-that-is-longer-than-forty-characters'), '23514');

  -- Reference catalog rows are fixtures only if not already seeded by migrations.
  INSERT INTO opc.roles(code,name_ja,name_zh,description) VALUES
    ('customer','顧客','客户','verification fixture'),
    ('provider','内部担当者','内部承接者','verification fixture'),
    ('operator','運営','运营','verification fixture')
  ON CONFLICT (code) DO NOTHING;
  INSERT INTO opc.service_types(code,name_ja,name_zh,enabled)
  VALUES ('development','開発','开发',true) ON CONFLICT (code) DO NOTHING;
  INSERT INTO opc.account_roles(account_id,role_code,granted_by,reason) VALUES
    (customer,'customer',operator_account,'verification fixture'),
    (other_customer,'customer',operator_account,'verification fixture'),
    (provider,'provider',operator_account,'verification fixture'),
    (operator_account,'operator',operator_account,'verification fixture');
  INSERT INTO opc.provider_authorizations(id,account_id,granted_by,reason)
  VALUES (provider_authorization,provider,operator_account,'verification fixture');

  INSERT INTO opc.requests(id,public_code,customer_id,current_request_version,current_scope_version)
  VALUES (request_id,'VERIFY-' || request_id::text,customer,1,2),
    (other_request,'VERIFY-' || other_request::text,other_customer,2,NULL);
  INSERT INTO opc.request_versions(request_id,version,original_description,timing_text,budget_text,submitted_by)
  VALUES (request_id,1,'客户原文：需要集中管理咨询并跟踪处理进度。','相談して決めたい','予算は相談',customer),
    (other_request,2,'其他客户的原始需求版本只属于另一个项目。','来月','未定',other_customer);
  INSERT INTO opc.files(id,owner_id,original_name,media_type,kind,storage_key,size_bytes,sha256,upload_status,scan_status)
  VALUES
    (visible_file,customer,'approved-reference.pdf','application/pdf','pdf','verify/' || visible_file::text,64,repeat('a',64),'ready','clean'),
    (private_file,customer,'private-client-notes.txt','text/plain','text','verify/' || private_file::text,64,repeat('b',64),'ready','clean'),
    (pending_file,customer,'incomplete.txt','text/plain','text','verify/' || pending_file::text,0,NULL,'pending','pending'),
    (rejected_file,customer,'rejected.txt','text/plain','text','verify/' || rejected_file::text,64,repeat('c',64),'ready','rejected'),
    (source_file,provider,'source.zip','application/zip','other','verify/' || source_file::text,64,repeat('d',64),'ready','clean');
  -- Original attachments must be attached before any scope describes that
  -- original version. Subsequent material requires a new original version.
  INSERT INTO opc.request_files(request_id,request_version,file_id)
  VALUES (request_id,1,private_file);
  INSERT INTO opc.scope_versions(request_id,version,request_version,title,public_summary,category,authored_by)
  VALUES (request_id,1,1,'旧整理稿','只用于验证旧范围审核不能复用','web_application',operator_account),
    (request_id,2,1,'审核整理后的咨询管理系统','公开摘要与客户原文独立保存','web_application',operator_account),
    (other_request,1,2,'审核未通过的其他需求','技术审核被拒绝的范围','web_application',operator_account);
  UPDATE opc.requests SET current_scope_version=1 WHERE id=other_request;
  -- The original version may differ numerically from the scope version, but must
  -- belong to the same request. A version existing only in another request fails.
  PERFORM pg_temp.assert_true(
    (SELECT request_version = 1 AND version = 2 FROM opc.scope_versions
      WHERE scope_versions.request_id = request_id AND version = 2),
    'scope v2 can refer to original requirement v1');
  PERFORM pg_temp.assert_true(
    (SELECT original_description = '客户原文：需要集中管理咨询并跟踪处理进度。'
      FROM opc.request_versions WHERE request_versions.request_id = request_id AND version = 1),
    'scope creation preserves the original customer text');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.scope_versions(request_id,version,request_version,title,public_summary,category,authored_by)
     VALUES (%L,99,2,%L,%L,%L,%L)',
    request_id,'错误跨需求来源','版本 2 仅存在于另一需求','web_application',operator_account), '23503');
  SET CONSTRAINTS ALL IMMEDIATE;

  PERFORM pg_temp.expect_error(format(
    'UPDATE opc.requests SET current_scope_version=NULL WHERE id=%L',request_id), '23514');
  PERFORM pg_temp.assert_true(
    (SELECT current_request_version=1 AND current_scope_version=2
      FROM opc.requests WHERE id=request_id),
    'rejected scope clearing preserves both current version pointers');
  -- Prepared drafts are not activated versions. Keeping a v3 draft must not
  -- invalidate an unrelated update while the reviewed/current pointer stays v2.
  INSERT INTO opc.scope_versions(request_id,version,request_version,title,public_summary,category,authored_by)
  VALUES (request_id,3,1,'未激活的整理草稿','草稿不替换当前公开范围','web_application',operator_account);
  UPDATE opc.requests SET intake_status='in_review' WHERE id=request_id;
  PERFORM pg_temp.assert_true(
    (SELECT intake_status='in_review' AND current_scope_version=2
      AND highest_activated_scope_version=2 FROM opc.requests WHERE id=request_id),
    'a higher unactivated scope draft permits request updates without advancing the active scope');
  UPDATE opc.requests SET highest_activated_scope_version=0 WHERE id=request_id;
  PERFORM pg_temp.assert_true(
    (SELECT current_scope_version=2 AND highest_activated_scope_version=2
      FROM opc.requests WHERE id=request_id),
    'direct watermark lowering is ignored and preserves the highest activated scope');
  PERFORM pg_temp.expect_error(format(
    'UPDATE opc.requests SET current_scope_version=1 WHERE id=%L',request_id), '23514');
  PERFORM pg_temp.assert_true(
    (SELECT current_scope_version=2 AND highest_activated_scope_version=2
      FROM opc.requests WHERE id=request_id),
    'a rejected activation rollback retains scope v2 and its monotonic watermark');
  PERFORM pg_temp.expect_error(format(
    'UPDATE opc.request_files SET sort_order=1 WHERE request_id=%L AND request_version=1 AND file_id=%L',
    request_id,private_file), '55000');
  PERFORM pg_temp.expect_error(format(
    'DELETE FROM opc.request_files WHERE request_id=%L AND request_version=1 AND file_id=%L',
    request_id,private_file), '55000');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.request_files(request_id,request_version,file_id) VALUES (%L,1,%L)',
    request_id,visible_file), '55000');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.scope_files(request_id,scope_version,file_id) VALUES (%L,2,%L)',
    request_id,pending_file), '23514');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.scope_files(request_id,scope_version,file_id) VALUES (%L,2,%L)',
    request_id,rejected_file), '23514');
  INSERT INTO opc.scope_files(request_id,scope_version,file_id)
  VALUES (request_id,2,visible_file);

  INSERT INTO opc.review_decisions(id,request_id,scope_version,kind,decision,reviewer_id,reason)
  VALUES (compliance_review,request_id,2,'compliance','approved',operator_account,'用途确认通过'),
    (other_scope_compliance,request_id,1,'compliance','approved',operator_account,'旧范围用途通过'),
    (other_scope_technical,request_id,1,'technical','approved',operator_account,'旧范围技术通过'),
    (rejected_scope_compliance,other_request,1,'compliance','approved',operator_account,'用途通过'),
    (rejected_scope_technical,other_request,1,'technical','rejected',operator_account,'技术条件未满足');
  PERFORM pg_temp.assert_true(
    NOT EXISTS (SELECT 1 FROM opc.hall_requests h WHERE h.request_id = request_id),
    'single-review request is absent from the hall');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.publications(request_id,scope_version,compliance_review_id,technical_review_id,published_by)
     VALUES (%L,2,%L,%L,%L)',
    request_id,compliance_review,compliance_review,operator_account), '23514');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.publications(request_id,scope_version,compliance_review_id,technical_review_id,published_by)
     VALUES (%L,2,%L,%L,%L)',
    request_id,compliance_review,other_scope_technical,operator_account), '23514');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.publications(request_id,scope_version,compliance_review_id,technical_review_id,published_by)
     VALUES (%L,1,%L,%L,%L)',
    other_request,rejected_scope_compliance,rejected_scope_technical,operator_account), '23514');
  INSERT INTO opc.review_decisions(id,request_id,scope_version,kind,decision,reviewer_id,reason)
  VALUES (technical_review,request_id,2,'technical','approved',operator_account,'技术整理通过');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.review_decisions(request_id,scope_version,kind,decision,reviewer_id,reason)
     VALUES (%L,2,%L,%L,%L,%L)',
    request_id,'technical','approved',operator_account,'重复决定'), '23505');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.publications(request_id,scope_version,compliance_review_id,technical_review_id,published_by)
     VALUES (%L,2,%L,%L,%L)',
    request_id,technical_review,compliance_review,operator_account), '23514');

  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.scope_files(request_id,scope_version,file_id) VALUES (%L,2,%L)',
    request_id,private_file), '55000');
  PERFORM pg_temp.expect_error(format(
    'UPDATE opc.scope_files SET sort_order=1 WHERE request_id=%L AND scope_version=2 AND file_id=%L',
    request_id,visible_file), '55000');
  PERFORM pg_temp.expect_error(format(
    'DELETE FROM opc.scope_files WHERE request_id=%L AND scope_version=2 AND file_id=%L',
    request_id,visible_file), '55000');

  UPDATE opc.files SET scan_status='rejected' WHERE id=visible_file;
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.publications(request_id,scope_version,compliance_review_id,technical_review_id,published_by)
     VALUES (%L,2,%L,%L,%L)',
    request_id,compliance_review,technical_review,operator_account), '23514');
  UPDATE opc.files SET scan_status='clean' WHERE id=visible_file;
  INSERT INTO opc.publications(id,request_id,scope_version,compliance_review_id,technical_review_id,published_by)
  VALUES (publication,request_id,2,compliance_review,technical_review,operator_account);
  INSERT INTO opc.publication_files(publication_id,request_id,scope_version,file_id)
  VALUES (publication,request_id,2,visible_file);
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.publication_files(publication_id,request_id,scope_version,file_id) VALUES (%L,%L,2,%L)',
    publication,request_id,private_file), '23503');
  PERFORM pg_temp.assert_true(
    (SELECT count(*) = 1 FROM opc.hall_requests h WHERE h.request_id = request_id),
    'the valid current double-reviewed publication appears once in the hall');
  PERFORM pg_temp.assert_true(
    (SELECT h.public_summary = '公开摘要与客户原文独立保存'
      AND NOT (to_jsonb(h) ?| ARRAY['original_description','customer_id','storage_key'])
      FROM opc.hall_requests h WHERE h.request_id=request_id),
    'hall projection exposes the approved summary without original text, owner or storage identity');
  PERFORM pg_temp.assert_true(
    (SELECT count(*) = 1 FROM opc.hall_reference_files f WHERE f.publication_id = publication)
    AND EXISTS (SELECT 1 FROM opc.hall_reference_files f
      WHERE f.publication_id = publication AND f.file_id = visible_file)
    AND NOT EXISTS (SELECT 1 FROM opc.hall_reference_files f
      WHERE f.publication_id = publication AND f.file_id = private_file),
    'hall file metadata contains only explicitly published reviewed files');

  INSERT INTO opc.engagements(id,request_id,created_by)
  VALUES (engagement,request_id,operator_account);
  PERFORM pg_temp.assert_true(
    NOT EXISTS (SELECT 1 FROM opc.hall_requests h WHERE h.request_id=request_id),
    'an active cooperation removes the task from available hall results');
  INSERT INTO opc.assignments(id,engagement_id,version,provider_id,recorded_by,reason)
  VALUES (assignment,engagement,1,provider,operator_account,'验证有效负责人关系，不预设接单机制');
  INSERT INTO opc.agreement_versions(engagement_id,version,request_id,scope_version,terms,authored_by)
  VALUES (engagement,1,request_id,2,'双方确认的范围及交付方式；不涉及付款',operator_account);
  INSERT INTO opc.agreement_confirmations(engagement_id,agreement_version,party,confirmed_by)
  VALUES (engagement,1,'customer',customer);
  UPDATE opc.engagements SET status='executing' WHERE id=engagement;
  delivery_insert := format(
    'INSERT INTO opc.deliveries(id,engagement_id,version,assignment_id,agreement_version,submitted_by,note,source_file_id,guide_text,test_report_text)
     VALUES (%L,%L,1,%L,1,%L,%L,%L,%L,%L)',
    delivery_one,engagement,assignment,provider,'初版交付',source_file,'操作说明','真实测试证据字段的结构验证');
  PERFORM pg_temp.expect_error(delivery_insert,'23514');
  INSERT INTO opc.agreement_confirmations(engagement_id,agreement_version,party,confirmed_by)
  VALUES (engagement,1,'provider',provider);
  UPDATE opc.engagements SET status='pending_confirmation' WHERE id=engagement;
  PERFORM pg_temp.expect_error(delivery_insert,'23514');
  UPDATE opc.engagements SET status='internal_review' WHERE id=engagement;
  PERFORM pg_temp.expect_error(delivery_insert,'23514');
  UPDATE opc.engagements SET status='awaiting_acceptance' WHERE id=engagement;
  PERFORM pg_temp.expect_error(delivery_insert,'23514');
  UPDATE opc.engagements SET status='executing' WHERE id=engagement;
  -- Publication withdrawal closes discovery, not the historical agreement.
  UPDATE opc.publications SET withdrawn_by=operator_account,withdrawn_at=now(),
    withdrawal_reason='验证下架不抹除已确认合作' WHERE id=publication;
  UPDATE opc.accounts SET status='disabled' WHERE id=provider;
  PERFORM pg_temp.expect_error(delivery_insert,'23514');
  UPDATE opc.accounts SET status='active' WHERE id=provider;
  UPDATE opc.provider_authorizations SET revoked_by=operator_account,revoked_at=now()
    WHERE id=provider_authorization;
  PERFORM pg_temp.expect_error(delivery_insert,'23514');
  INSERT INTO opc.provider_authorizations(account_id,granted_by,reason)
  VALUES (provider,operator_account,'验证重新授权后新提交');
  EXECUTE delivery_insert;
  UPDATE opc.engagements SET status='internal_review' WHERE id=engagement;

  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.delivery_publications(delivery_id,review_id,published_by) VALUES (%L,%L,%L)',
    delivery_one,gen_random_uuid(),operator_account),'23514');
  INSERT INTO opc.delivery_reviews(id,delivery_id,reviewer_id,decision,evidence)
  VALUES (qa_one,delivery_one,operator_account,'approved','初版内部检查记录');
  INSERT INTO opc.delivery_publications(delivery_id,review_id,published_by)
  VALUES (delivery_one,qa_one,operator_account);
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.acceptance_decisions(delivery_id,customer_id,decision) VALUES (%L,%L,%L)',
    delivery_one,customer,'accepted'),'23514');
  UPDATE opc.engagements SET status='revision' WHERE id=engagement;
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.acceptance_decisions(delivery_id,customer_id,decision) VALUES (%L,%L,%L)',
    delivery_one,customer,'accepted'),'23514');
  UPDATE opc.engagements SET status='awaiting_acceptance' WHERE id=engagement;
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.acceptance_decisions(delivery_id,customer_id,decision) VALUES (%L,%L,%L)',
    delivery_one,other_customer,'accepted'),'23514');

  -- A newer submitted version invalidates acceptance of the earlier public
  -- version, even before the new version passes QA or is published to clients.
  UPDATE opc.engagements SET status='revision' WHERE id=engagement;
  INSERT INTO opc.deliveries(id,engagement_id,version,assignment_id,agreement_version,submitted_by,note,source_file_id,guide_text,test_report_text)
  VALUES (delivery_two,engagement,2,assignment,1,provider,'第二版交付',source_file,'操作说明二','测试记录二');
  UPDATE opc.engagements SET status='awaiting_acceptance' WHERE id=engagement;
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.acceptance_decisions(delivery_id,customer_id,decision) VALUES (%L,%L,%L)',
    delivery_one,customer,'accepted'),'23514');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.acceptance_decisions(delivery_id,customer_id,decision) VALUES (%L,%L,%L)',
    delivery_two,customer,'accepted'),'23514');
  UPDATE opc.engagements SET status='internal_review' WHERE id=engagement;
  INSERT INTO opc.delivery_reviews(id,delivery_id,reviewer_id,decision,evidence)
  VALUES (qa_two,delivery_two,operator_account,'changes_requested','第二版内部检查要求修正');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.delivery_publications(delivery_id,review_id,published_by) VALUES (%L,%L,%L)',
    delivery_two,qa_two,operator_account),'23514');

  UPDATE opc.engagements SET status='revision' WHERE id=engagement;
  INSERT INTO opc.deliveries(id,engagement_id,version,assignment_id,agreement_version,submitted_by,note,source_file_id,guide_text,test_report_text)
  VALUES (delivery_three,engagement,3,assignment,1,provider,'第三版修正交付',source_file,'操作说明三','测试记录三');
  UPDATE opc.engagements SET status='internal_review' WHERE id=engagement;
  INSERT INTO opc.delivery_reviews(id,delivery_id,reviewer_id,decision,evidence)
  VALUES (qa_three,delivery_three,operator_account,'approved','第三版内部检查通过');
  PERFORM pg_temp.expect_error(format(
    'INSERT INTO opc.delivery_publications(delivery_id,review_id,published_by) VALUES (%L,%L,%L)',
    delivery_three,qa_one,operator_account),'23514');
  INSERT INTO opc.delivery_publications(delivery_id,review_id,published_by)
  VALUES (delivery_three,qa_three,operator_account);
  UPDATE opc.engagements SET status='awaiting_acceptance' WHERE id=engagement;
  INSERT INTO opc.acceptance_decisions(delivery_id,customer_id,decision)
  VALUES (delivery_three,customer,'accepted');
  PERFORM pg_temp.assert_true(
    EXISTS (SELECT 1 FROM opc.acceptance_decisions a
      WHERE a.delivery_id=delivery_three AND a.customer_id=customer AND a.decision='accepted'),
    'the owning customer can accept the latest QA-approved published delivery');
  UPDATE opc.engagements SET status='completed',closed_at=now() WHERE id=engagement;

  INSERT INTO opc.audit_events(application_actor_id,table_name,operation,entity_key,details)
  VALUES (operator_account,'verification','BUSINESS',jsonb_build_object('id',request_id),'{"fixture":true}')
  RETURNING id INTO audit_id;
  PERFORM pg_temp.expect_error(format(
    'UPDATE opc.audit_events SET details=%L::jsonb WHERE id=%s','{"tampered":true}',audit_id),'55000');
  PERFORM pg_temp.expect_error(format(
    'DELETE FROM opc.audit_events WHERE id=%s',audit_id),'55000');
  SET CONSTRAINTS ALL IMMEDIATE;
END;
$verification$;

SELECT count(*) AS passed_assertions,
  count(*) FILTER (WHERE expected_sqlstate IS NOT NULL) AS expected_rejections
FROM verification_results;

ROLLBACK;
\echo 'OPC verification passed; all fixture rows rolled back.'
