INSERT INTO opc.roles(code,name_ja,name_zh,description) VALUES
('customer','依頼者','客户','Customer identity; API access remains scoped to the authenticated account.'),
('provider','担当者','承接者','Provider UI role; active provider_authorizations is separately required. Not OPC certification.'),
('compliance_reviewer','コンプライアンス審査','合规审核','Administrative compliance-review capability; not a mobile admin entitlement.'),
('technical_reviewer','技術整理・審査','技术整理与审核','Administrative technical-review capability.'),
('quality_reviewer','納品品質確認','交付质检','Administrative internal delivery QA capability.'),
('operator','運営担当','运营人员','Administrative operational capability; actual role-to-API policy is pending.'),
('administrator','管理者','管理员','Administrative account management; never automatically assigned to mobile users.');
INSERT INTO opc.service_types(code,name_ja,name_zh,enabled) VALUES
('development','AI開発システム','AI 开发系统',true);
