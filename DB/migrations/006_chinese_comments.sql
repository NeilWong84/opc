-- 为全部表、字段和大厅视图建立中文结构说明；覆盖历史英文对象注释。


COMMENT ON TABLE opc.schema_migrations IS '数据库迁移执行登记：保存已应用文件版本、文件校验值与应用时间，用于重复执行和历史文件一致性检查。';
COMMENT ON COLUMN opc.schema_migrations.version IS '迁移文件版本标识，对应迁移执行器登记的文件名；唯一，不是需求、整理范围或交付版本。';
COMMENT ON COLUMN opc.schema_migrations.checksum IS '已应用迁移文件的 SHA-256 校验值，使用 64 位小写十六进制字符串；用于检测历史文件被修改。';
COMMENT ON COLUMN opc.schema_migrations.applied_at IS '该迁移应用登记时间，带时区；数据库统一使用 UTC。';

COMMENT ON TABLE opc.accounts IS '客户与内部人员的统一账号资料；账号启停、角色、内部承接授权和认证资格不是同一事实，实际登录与对象访问鉴权由后端实现。';
COMMENT ON COLUMN opc.accounts.email IS '账号邮箱，保留提交时的大小写，不允许首尾空格；数据库仅进行基本格式校验，不表示邮箱已经验证。';
COMMENT ON COLUMN opc.accounts.email_normalized IS '由 email 自动转为小写的规范化邮箱，唯一约束不区分邮箱大小写；不由客户端单独填写。';
COMMENT ON COLUMN opc.accounts.display_name IS '账号显示名称，去除首尾空白后为 1 至 80 个字符；显示名不作为身份标识或权限依据。';
COMMENT ON COLUMN opc.accounts.status IS '账号状态：invited=已邀请待启用，active=启用，disabled=停用；启用不自动授予内部承接或管理权限。';
COMMENT ON COLUMN opc.accounts.ui_locale IS '账号界面语言偏好：ja=日语，zh=简体中文，默认 ja；不翻译客户原文，不改变业务版本、JPY 金额、JST 展示时区或权限。';
COMMENT ON COLUMN opc.accounts.created_at IS '账号创建时间，带时区；数据库统一使用 UTC，不表示邮箱验证或邀请接受时间。';
COMMENT ON COLUMN opc.accounts.row_version IS '账号资料行的正整数并发版本，更新触发器递增；用于检测旧数据写入，不等于角色或授权版本。';

COMMENT ON TABLE opc.password_credentials IS '账号密码凭据的独立存储；只接受编码哈希的基本形状，不保存明文密码，不代表真实身份认证、哈希算法或密码策略已经实现。';
COMMENT ON COLUMN opc.password_credentials.account_id IS '凭据所属账号，关联 accounts；每个账号最多一条当前密码凭据。';
COMMENT ON COLUMN opc.password_credentials.password_hash IS '由后端生成的密码编码哈希；当前约束只要求不少于 40 个字符且以美元符号开头，不能证明算法安全或哈希可验证，禁止存入明文密码。';
COMMENT ON COLUMN opc.password_credentials.changed_at IS '当前密码哈希登记或变更时间，带时区；数据库统一使用 UTC。';
COMMENT ON COLUMN opc.password_credentials.must_change IS '是否要求后续修改密码：true=需要修改，false=未要求；实际修改流程和登录限制由后端实施。';

COMMENT ON TABLE opc.auth_sessions IS '可撤销的账号会话记录，区分手机端与管理端用途；保存令牌哈希而非明文令牌，认证签发和实时鉴权尚由后端接入。';
COMMENT ON COLUMN opc.auth_sessions.account_id IS '会话所属账号，关联 accounts；请求仍须核验账号启停、角色及对象权限。';
COMMENT ON COLUMN opc.auth_sessions.token_hash IS '会话令牌哈希，唯一且为 64 位小写十六进制字符串；不保存明文令牌，字段格式不等于已经实现安全令牌生成或验证。';
COMMENT ON COLUMN opc.auth_sessions.audience IS '会话使用端：mobile=手机端，admin=管理端；手机会话不自动获得管理端权限。';
COMMENT ON COLUMN opc.auth_sessions.device_label IS '会话对应的设备说明或显示名称；NULL 表示未提供，不作为设备可信或身份认证证据。';
COMMENT ON COLUMN opc.auth_sessions.created_at IS '会话创建时间，带时区；数据库统一使用 UTC。';
COMMENT ON COLUMN opc.auth_sessions.expires_at IS '会话到期时间，必须晚于创建时间，带时区；是否过期须在真实请求鉴权时核验。';
COMMENT ON COLUMN opc.auth_sessions.revoked_at IS '会话撤销时间，带时区，不能早于创建时间；NULL 仅表示未记录撤销，仍须检查到期时间和账号状态。';

COMMENT ON TABLE opc.roles IS '客户、内部执行及后台职责的双语角色字典；字典记录不直接授予接口权限，实际角色策略由后端鉴权实现。';
COMMENT ON COLUMN opc.roles.code IS '角色代码：customer=客户，provider=内部承接者，compliance_reviewer=合规审核，technical_reviewer=技术整理与审核，quality_reviewer=交付质检，operator=运营，administrator=管理员。';
COMMENT ON COLUMN opc.roles.name_ja IS '角色的日语显示名称；不作为程序权限判断值。';
COMMENT ON COLUMN opc.roles.name_zh IS '角色的简体中文显示名称；不作为程序权限判断值。';
COMMENT ON COLUMN opc.roles.description IS '角色职责及使用边界说明；不替代具体接口和对象级权限规则。';

COMMENT ON TABLE opc.account_roles IS '账号角色授予及撤销历史；同一账号同一角色最多一条未撤销记录，撤销不删除历史，内部承接还需单独授权。';
COMMENT ON COLUMN opc.account_roles.account_id IS '被授予角色的账号，关联 accounts。';
COMMENT ON COLUMN opc.account_roles.role_code IS '授予的角色代码，关联 roles.code；客户、内部承接及后台各职责分别记录，不因注册自动授予管理角色。';
COMMENT ON COLUMN opc.account_roles.granted_by IS '记录本次角色授予的操作账号，关联 accounts；该字段记录归因，不单独证明操作者已通过管理鉴权。';
COMMENT ON COLUMN opc.account_roles.granted_at IS '角色授予时间，带时区；数据库统一使用 UTC。';
COMMENT ON COLUMN opc.account_roles.revoked_by IS '记录本次角色撤销的操作账号；NULL 表示未撤销，须与 revoked_at 同时为空或同时填写。';
COMMENT ON COLUMN opc.account_roles.revoked_at IS '角色撤销时间，带时区且不得早于授予时间；NULL 表示该条角色记录尚未撤销，仍需核验账号状态。';
COMMENT ON COLUMN opc.account_roles.reason IS '角色授予的非空理由；原始授予证据保留，撤销只补充撤销人和撤销时间。';

COMMENT ON TABLE opc.provider_authorizations IS '内部承接授权的授予与撤销历史，独立于账号角色和逐单合作关系；获得内部授权不表示通过正式 OPC 认证。';
COMMENT ON COLUMN opc.provider_authorizations.account_id IS '获得内部承接授权的账号，关联 accounts；同一账号最多一条未撤销授权，业务操作还需核验账号有效及当前任务关系。';
COMMENT ON COLUMN opc.provider_authorizations.granted_by IS '记录本次内部承接授权的操作账号；仅用于授权归因，不表示已实施管理端身份验证。';
COMMENT ON COLUMN opc.provider_authorizations.granted_at IS '内部承接授权授予时间，带时区；数据库统一使用 UTC。';
COMMENT ON COLUMN opc.provider_authorizations.revoked_by IS '记录授权撤销的操作账号；NULL 表示未撤销，须与 revoked_at 一致填写。';
COMMENT ON COLUMN opc.provider_authorizations.revoked_at IS '内部承接授权撤销时间，带时区且不得早于授予时间；NULL 表示尚未撤销，不代表账号始终可用。';
COMMENT ON COLUMN opc.provider_authorizations.reason IS '内部承接授权授予的非空理由；不作为正式认证、逐单接单或负责人确认依据。';

COMMENT ON TABLE opc.service_types IS '双语服务类型字典及新需求准入开关；当前只初始化并开放 development 开发服务，不预设其余四条服务线已上线。';
COMMENT ON COLUMN opc.service_types.code IS '服务类型稳定代码，当前 development=AI 开发系统；用于程序关联，不使用翻译后的显示名称判断业务。';
COMMENT ON COLUMN opc.service_types.name_ja IS '服务类型的日语显示名称。';
COMMENT ON COLUMN opc.service_types.name_zh IS '服务类型的简体中文显示名称。';
COMMENT ON COLUMN opc.service_types.enabled IS '是否允许创建该类型的新需求：true=开放，false=关闭；关闭不表示历史需求已经删除或取消。';

COMMENT ON TABLE opc.request_drafts IS '客户提交前的私有需求草稿，每个客户最多一条；允许内容未完整，保存草稿不表示正式提交、审核通过或大厅发布。';
COMMENT ON COLUMN opc.request_drafts.customer_id IS '草稿所属客户账号，关联 accounts；该字段也是每客户一份草稿的唯一键，访问须按本人身份限制。';
COMMENT ON COLUMN opc.request_drafts.description IS '客户尚未正式提交的需求原文，可为空字符串；界面语言切换不改写或自动翻译。';
COMMENT ON COLUMN opc.request_drafts.timing_text IS '客户期望时间的草稿原文，可为空字符串；属于意向描述，不等于已确认合同期限。';
COMMENT ON COLUMN opc.request_drafts.budget_text IS '客户预算意向的草稿原文，可为空字符串；不是可计算金额、正式报价或收款事实。';
COMMENT ON COLUMN opc.request_drafts.row_version IS '草稿行的正整数并发版本，由更新触发器递增；与正式需求原文版本分离。';

COMMENT ON TABLE opc.draft_files IS '客户草稿与私有文件的关联；文件实际上传和访问由文件服务及后端控制，不随草稿保存自动成为公开资料。';
COMMENT ON COLUMN opc.draft_files.customer_id IS '关联的草稿所属客户，引用 request_drafts.customer_id；不能据此跳过真实账号和文件权限检查。';
COMMENT ON COLUMN opc.draft_files.file_id IS '草稿所引用的私有文件记录，关联 files；仅为关联，不代表文件已经上传成功。';
COMMENT ON COLUMN opc.draft_files.sort_order IS '草稿附件展示顺序，非负整数，从 0 开始；同一序号不承诺唯一。';

COMMENT ON TABLE opc.requests IS '需求受理主记录：保存客户归属、服务类型及当前原文与整理范围指针；审核、发布、合作执行和交付各自独立记录，不能用受理状态代替全部业务事实。';
COMMENT ON COLUMN opc.requests.public_code IS '唯一的需求展示编号，默认由序列生成 REQ- 前缀编号；不是访问令牌，序列回滚可能产生空号。';
COMMENT ON COLUMN opc.requests.customer_id IS '需求所属客户账号，关联 accounts；客户本人可查看受理过程，大厅摘要不因此获得私有资料访问权。';
COMMENT ON COLUMN opc.requests.service_code IS '需求服务类型代码，关联 service_types；当前 development=AI 开发系统，创建时必须处于开放状态。';
COMMENT ON COLUMN opc.requests.intake_status IS '受理状态：submitted=已提交，needs_info=待客户补充，in_review=审核处理中，withdrawn=客户需求已撤回，closed=受理已关闭；不等同发布、合作执行、验收或支付状态。';
COMMENT ON COLUMN opc.requests.current_request_version IS '当前客户原文版本号，正整数，关联同一需求的 request_versions.version；不得回退，与整理范围和交付版本各自独立。';
COMMENT ON COLUMN opc.requests.current_scope_version IS '当前激活的整理范围版本，关联同一需求的 scope_versions.version；NULL 表示当前原文尚无激活范围，原文版本未递增时不能直接清空已有指针；激活范围必须对应当前原文。';
COMMENT ON COLUMN opc.requests.created_at IS '需求主记录创建时间，带时区；数据库统一使用 UTC，界面可按日本业务时区 JST 展示。';
COMMENT ON COLUMN opc.requests.row_version IS '需求主记录的正整数并发版本，由更新触发器递增；不是客户原文版本或整理范围版本。';
COMMENT ON COLUMN opc.requests.highest_activated_scope_version IS '触发器维护的最高已激活整理范围版本水位，0 表示尚未激活；只增不减，当前指针清空后仍保留；未激活的更高草稿不会提高该水位。';

COMMENT ON TABLE opc.request_versions IS '不可覆盖的客户原始需求版本，保留客户原话、时间和预算意向及提交证据；技术整理另存范围版本，不覆盖原文。';
COMMENT ON COLUMN opc.request_versions.request_id IS '原始需求版本所属需求，关联 requests；与 version 共同唯一。';
COMMENT ON COLUMN opc.request_versions.version IS '同一需求内的正整数原文版本号；补充或变更形成新版本，不与整理范围、合作协议或交付版本混用。';
COMMENT ON COLUMN opc.request_versions.original_description IS '正式提交的客户原始描述，去除首尾空白后为 10 至 4000 个字符；保留原文，不随界面语言翻译或由整理稿覆盖。';
COMMENT ON COLUMN opc.request_versions.timing_text IS '该次提交的非空期望时间原文；属于客户意向，不是最终承诺期限。';
COMMENT ON COLUMN opc.request_versions.budget_text IS '该次提交的非空预算意向原文；不是正式报价、支付金额或收款记录。';
COMMENT ON COLUMN opc.request_versions.submitted_by IS '提交该原文版本的账号，关联 accounts；记录作者归因，真实本人权限由后端核验。';
COMMENT ON COLUMN opc.request_versions.submitted_at IS '该原文版本提交时间，带时区；数据库统一使用 UTC。';

COMMENT ON TABLE opc.request_files IS '与客户原始需求版本绑定的私有材料清单；不得修改或删除既有绑定，形成引用该原文的整理范围后不可追加，不会因需求发布自动公开。';
COMMENT ON COLUMN opc.request_files.request_id IS '私有材料所属需求，须与 request_version 共同引用同一原文版本。';
COMMENT ON COLUMN opc.request_files.request_version IS '材料关联的客户原文版本号；不是整理范围或发布版本，后续补充需形成新原文版本。';
COMMENT ON COLUMN opc.request_files.file_id IS '客户私有材料的文件记录，关联 files；名称、内容与下载均不自动进入大厅或发布文件列表。';
COMMENT ON COLUMN opc.request_files.sort_order IS '该原文版本内的材料展示顺序，非负整数，从 0 开始；绑定记录不可直接更新。';

COMMENT ON TABLE opc.scope_versions IS '不可覆盖的技术整理范围版本，独立引用同一需求的客户原文；可以先保存未激活草稿，审核与发布必须绑定准确范围版本。';
COMMENT ON COLUMN opc.scope_versions.request_id IS '整理范围所属需求，关联 requests；与 version 共同唯一，来源原文必须属于同一需求。';
COMMENT ON COLUMN opc.scope_versions.version IS '同一需求内的正整数整理范围版本号，与原文版本独立；保存更高草稿不等于激活、审核通过或发布。';
COMMENT ON COLUMN opc.scope_versions.request_version IS '本整理范围依据的客户原文版本，和 request_id 联合引用 request_versions；数值无需与整理范围版本相同。';
COMMENT ON COLUMN opc.scope_versions.title IS '整理后的非空任务标题；属于该版本的业务内容，不随界面语言自动翻译。';
COMMENT ON COLUMN opc.scope_versions.public_summary IS '为发布准备的非空公开摘要，独立于客户原话；只有满足审核、有效发布和访问条件时才可进入大厅。';
COMMENT ON COLUMN opc.scope_versions.category IS '整理后的开发任务分类值，目前为非空文本，未冻结为枚举；分类不扩展为当前未开放的其他服务线。';
COMMENT ON COLUMN opc.scope_versions.goal IS '本范围拟解决的问题和目标；空字符串表示尚未填写，不能据此声称已确认。';
COMMENT ON COLUMN opc.scope_versions.included_scope IS '本版本包含的工作范围说明；空字符串表示尚未填写。';
COMMENT ON COLUMN opc.scope_versions.excluded_scope IS '本版本明确排除的工作范围说明；空字符串表示未记录，不表示默认包含所有工作。';
COMMENT ON COLUMN opc.scope_versions.deliverables IS '本范围约定交付物的 JSON 数组，空数组表示未列出；当前仅约束为数组，元素结构仍由后端业务契约规定。';
COMMENT ON COLUMN opc.scope_versions.acceptance_criteria IS '本范围拟采用的验收标准 JSON 数组，空数组表示未列出；不是客户已经完成验收的记录。';
COMMENT ON COLUMN opc.scope_versions.duration_text IS '整理后的预计工期说明原文；空字符串表示未记录，不等于合作协议中的已确认截止时间。';
COMMENT ON COLUMN opc.scope_versions.revision_terms IS '本范围的修改次数、边界或处理约定原文；空字符串表示未记录，不能推定无限修改。';
COMMENT ON COLUMN opc.scope_versions.authored_by IS '编写本范围版本的账号，关联 accounts；作者身份不自动代表审核通过或客户确认。';
COMMENT ON COLUMN opc.scope_versions.authored_at IS '整理范围版本编写登记时间，带时区；数据库统一使用 UTC。';

COMMENT ON TABLE opc.scope_files IS '明确纳入某整理范围审核包的候选大厅参考资料；首次审核决定产生后冻结清单，加入时文件须已上传且检查通过，仍需显式发布文件关联。';
COMMENT ON COLUMN opc.scope_files.request_id IS '候选参考资料所属需求，须与 scope_version 共同引用同一整理范围。';
COMMENT ON COLUMN opc.scope_files.scope_version IS '参考资料受审核的准确整理范围版本；旧版文件关联不能替代新版本的审核包。';
COMMENT ON COLUMN opc.scope_files.file_id IS '候选参考文件记录，关联 files；加入时要求 upload_status=ready 且 scan_status=clean，不自动公开客户原始私有附件。';
COMMENT ON COLUMN opc.scope_files.sort_order IS '该范围参考资料的展示顺序，非负整数，从 0 开始；已有绑定不直接更新，首次审核后不可变更清单。';

COMMENT ON TABLE opc.clarifications IS '绑定客户原文版本的澄清问题及一次回答记录；保留提问、回答作者和时间，不以单一最新备注覆盖沟通证据。';
COMMENT ON COLUMN opc.clarifications.request_id IS '澄清所属需求，与 request_version 共同关联被询问的原文版本。';
COMMENT ON COLUMN opc.clarifications.request_version IS '本问题针对的客户原文版本号；后续回答形成新需求版本时仍保留原问题的版本依据。';
COMMENT ON COLUMN opc.clarifications.question IS '本次非空澄清问题原文；仅在相应需求权限范围内提供。';
COMMENT ON COLUMN opc.clarifications.asked_by IS '提出该问题的账号，关联 accounts；记录提问人，不单独代表已获得后台审核权限。';
COMMENT ON COLUMN opc.clarifications.asked_at IS '提问时间，带时区；数据库统一使用 UTC。';
COMMENT ON COLUMN opc.clarifications.answer IS '澄清问题的回答原文；NULL 表示尚未回答，回答一经记录不可覆盖，回答人和时间须同时填写，真实回答权限由后端核验。';
COMMENT ON COLUMN opc.clarifications.answered_by IS '回答该问题的账号，关联 accounts；NULL 表示尚未回答，须与 answer、answered_at 一致填写，真实回答权限由后端核验。';
COMMENT ON COLUMN opc.clarifications.answered_at IS '回答时间，带时区且不得早于提问时间；NULL 表示尚未回答。';

COMMENT ON TABLE opc.review_decisions IS '针对准确整理范围版本的人工审核决定；每范围每类审核仅一条不可覆盖记录，合规与技术均通过才满足发布的审核条件。';
COMMENT ON COLUMN opc.review_decisions.request_id IS '审核决定所属需求，与 scope_version 联合引用被审核的整理范围。';
COMMENT ON COLUMN opc.review_decisions.scope_version IS '审核所针对的准确整理范围版本号；不能将旧范围通过结论套用到新范围。';
COMMENT ON COLUMN opc.review_decisions.kind IS '审核类别：compliance=用途合规审核，technical=技术整理与审核；两类决定独立记录。';
COMMENT ON COLUMN opc.review_decisions.decision IS '审核结论：approved=通过，needs_info=需要补充资料，rejected=拒绝；只有对应范围两类均为 approved 才可作为发布依据。';
COMMENT ON COLUMN opc.review_decisions.reviewer_id IS '记录该审核决定的审核账号，关联 accounts；实际管理权限须由后端核验，AI 建议不能冒充人工审核。';
COMMENT ON COLUMN opc.review_decisions.reason IS '本次审核结论的非空理由或依据，保留人工判断证据；不是客户合作确认或交付验收。';
COMMENT ON COLUMN opc.review_decisions.decided_at IS '审核决定时间，带时区；数据库统一使用 UTC。';

COMMENT ON TABLE opc.publications IS '准确整理范围版本的大厅发布与下架历史，绑定该版本双审核通过证据；同一需求最多一条未下架发布，不自动公开原始私有材料或建立合作关系。';
COMMENT ON COLUMN opc.publications.request_id IS '发布所属需求，与 scope_version 联合引用被发布范围；发布时须为需求当前有效范围。';
COMMENT ON COLUMN opc.publications.scope_version IS '本次发布的准确整理范围版本号；同版本的合规与技术审核必须均通过，版本变化不能继承旧审核公开。';
COMMENT ON COLUMN opc.publications.compliance_review_id IS '本发布依据的合规审核决定，关联 review_decisions；必须属于同需求、同范围，kind=compliance 且 decision=approved。';
COMMENT ON COLUMN opc.publications.technical_review_id IS '本发布依据的技术审核决定，关联 review_decisions；必须属于同需求、同范围，kind=technical 且 decision=approved。';
COMMENT ON COLUMN opc.publications.published_by IS '记录本次发布的操作账号，关联 accounts；真实发布管理权限由后端核验，不属于普通手机账号权限。';
COMMENT ON COLUMN opc.publications.published_at IS '发布登记时间，带时区；数据库统一使用 UTC。';
COMMENT ON COLUMN opc.publications.withdrawn_by IS '记录本次下架的操作账号；NULL 表示尚未记录下架，须与下架时间及理由一致填写。';
COMMENT ON COLUMN opc.publications.withdrawn_at IS '本次发布的下架时间，带时区且不得早于发布时间；NULL 表示该发布未下架，但大厅仍需检查当前版本、受理和合作状态。';
COMMENT ON COLUMN opc.publications.withdrawal_reason IS '本次下架的非空理由；NULL 表示尚未下架，下架不删除历史审核、已确认合作或交付证据。';



COMMENT ON TABLE opc.publication_files IS '大厅发布版本明确引用的参考资料清单；关联同一需求范围版本中的文件，不自动公开客户原始私有附件。记录禁止修改和删除，实际读取仍须校验当前发布状态、文件状态及访问者权限。';
COMMENT ON COLUMN opc.publication_files.publication_id IS '发布记录标识；与 request_id、scope_version 组成外键引用 publications(id,request_id,scope_version)，与 file_id 共同唯一标识一项发布附件。';
COMMENT ON COLUMN opc.publication_files.request_id IS '所属需求标识；参与指向 publications 和 scope_files 的复合外键，确保发布记录、范围版本和文件属于同一需求。';
COMMENT ON COLUMN opc.publication_files.scope_version IS '发布所引用的技术整理范围版本；参与指向 publications 和 scope_files 的复合外键，不是客户原文版本或文件转换版本。';
COMMENT ON COLUMN opc.publication_files.file_id IS '参考文件标识；与 request_id、scope_version 组成外键引用 scope_files(request_id,scope_version,file_id)，仅能引用该范围版本已收录的文件；不存放文件内容或下载地址。';

COMMENT ON TABLE opc.files IS '私有文件的归属、内容身份、上传及安全检查状态。文件字节存放于待接入的私有存储，表内仅保存元数据；关联需求、发布或成果不等于向任意用户公开。状态值不证明上传器或扫描服务已经实现。';
COMMENT ON COLUMN opc.files.owner_id IS '文件所属账号，外键引用 accounts(id)；归属在创建后不可改写，不等同于文件的全部可访问账号清单。';
COMMENT ON COLUMN opc.files.original_name IS '原始文件名，必须非空且不得包含正斜杠或反斜杠；用于展示文件名称，不是本地路径或存储定位符，创建后不可改写。';
COMMENT ON COLUMN opc.files.media_type IS '文件媒体类型，使用非空 MIME 类型文本，例如 application/pdf；不是受 CHECK 枚举限制的代码，也不代表已验证文件真实格式。';
COMMENT ON COLUMN opc.files.kind IS '文件分类代码：image＝图片，video＝视频，document＝文档，spreadsheet＝电子表格，presentation＝演示文稿，pdf＝PDF 文档，text＝纯文本，other＝其他文件。';
COMMENT ON COLUMN opc.files.storage_key IS '私有存储中的不透明文件定位标识，全局唯一且非空；不得作为公开 URL 或签名 URL 保存，创建后不可改写。存储供应商未确定，下载须经服务端重新授权。';
COMMENT ON COLUMN opc.files.size_bytes IS '文件大小，单位为字节，非负整数；ready 状态必须大于 0。上传完成或摘要确定后不可改写，替换内容应建立新的文件记录。';
COMMENT ON COLUMN opc.files.sha256 IS '文件内容 SHA-256 摘要，64 位小写十六进制文本；NULL 表示尚未记录摘要，ready 状态必须非 NULL。摘要用于内容身份和完整性核对，不等同于安全扫描通过。';
COMMENT ON COLUMN opc.files.upload_status IS '上传状态代码：pending＝等待或尚未完成上传，ready＝记录为可用且已有非零大小及摘要，failed＝上传失败，deleted＝记录为已删除。状态本身不证明外部存储操作已经执行。';
COMMENT ON COLUMN opc.files.scan_status IS '文件安全检查状态代码：pending＝待检查，clean＝检查结果记录为通过，rejected＝检查结果拒绝，failed＝检查执行失败。clean 不构成绝对安全保证，实际扫描服务尚需接入。';
COMMENT ON COLUMN opc.files.duration_ms IS '音视频等有时长文件的时长，单位为毫秒，非负整数；NULL 表示不适用或尚未取得时长，不等于零时长。内容身份固定后不可改写。';
COMMENT ON COLUMN opc.files.created_at IS '文件元数据创建时刻，带时区时间戳，默认当前事务时间；保存绝对时刻，界面可按日本标准时间 JST 展示。';
COMMENT ON COLUMN opc.files.row_version IS '记录修订计数，正整数且初始为 1，更新时递增，可供后端并发控制使用；不是文件内容版本、需求版本或交付版本。';

COMMENT ON TABLE opc.file_previews IS '私有文件的预览产物及转换任务状态；同一文件、预览格式和转换器版本至多一条记录。预览必须继承原文件的访问边界，不因生成缩略图或文本而扩大可见范围；任意文件转换服务尚未实现。';
COMMENT ON COLUMN opc.file_previews.file_id IS '被预览的原文件标识，外键引用 files(id)；与 format、converter_version 组成唯一约束，预览授权应回溯该原文件及其业务关联。';
COMMENT ON COLUMN opc.file_previews.format IS '预览格式代码：thumbnail＝缩略图，image_pages＝分页图片，video＝视频预览，table＝表格预览，text＝文本预览；不表示原文件扩展名。';
COMMENT ON COLUMN opc.file_previews.converter_version IS '生成预览所用转换器的非空版本标识；参与预览唯一约束，用于区分转换实现或规则变化，不是原文件业务版本。';
COMMENT ON COLUMN opc.file_previews.state IS '预览处理状态代码：pending＝待处理，processing＝处理中，ready＝产物记录为可用，failed＝处理失败，unsupported＝不支持该转换。ready 时必须存在非空私有产物定位标识。';
COMMENT ON COLUMN opc.file_previews.private_storage_key IS '预览产物的私有存储定位标识，不应保存公开下载链接；NULL 表示尚未登记产物位置，ready 状态必须非空。读取产物仍需校验原文件访问权限。';
COMMENT ON COLUMN opc.file_previews.metadata IS '预览元数据 JSON 对象，默认空对象；可承载页数、尺寸、工作表等与格式有关的描述，具体键及单位由转换接口约定，现有数据库仅约束为对象，不验证这些业务键。不得以此绕过私有文件授权。';
COMMENT ON COLUMN opc.file_previews.error_code IS '转换错误代码，具体代码集待转换接口定义；NULL 表示未记录错误代码，不据此推断转换成功，应同时检查 state。';
COMMENT ON COLUMN opc.file_previews.attempt_count IS '转换尝试次数，非负整数，默认 0 表示尚未记录尝试；不是重试间隔、页数或文件下载次数。';
COMMENT ON COLUMN opc.file_previews.created_at IS '预览任务记录创建时刻，带时区时间戳，默认当前事务时间；不代表转换完成时间，界面按 JST 展示。';
COMMENT ON COLUMN opc.file_previews.row_version IS '预览记录修订计数，正整数且初始为 1，更新时递增；用于记录并发控制，不替代 converter_version。';

COMMENT ON TABLE opc.engagements IS '需求进入履约后的合作关系及履约状态；同一需求至多存在一个未关闭关系。保留关系历史，禁止删除；该结构不预先决定抢单、申请确认或逐单指派机制，也不实现支付结算。';
COMMENT ON COLUMN opc.engagements.request_id IS '合作所对应的需求标识，外键引用 requests(id)；同一需求在 closed_at 为 NULL 时至多一条合作关系，创建后不得改换需求。';
COMMENT ON COLUMN opc.engagements.status IS '履约状态代码：pending_confirmation＝待合作确认，executing＝执行中，internal_review＝成果内部审核中，awaiting_acceptance＝待客户验收，revision＝修正中，completed＝已完成，cancelled＝已取消。完成或取消时必须填写 closed_at。';
COMMENT ON COLUMN opc.engagements.created_by IS '建立合作关系的账号，外键引用 accounts(id)；记录操作者，不据此推断该账号为客户、承接者或具有管理员权限。';
COMMENT ON COLUMN opc.engagements.created_at IS '合作关系建立时刻，带时区时间戳，默认当前事务时间；保存绝对时刻，界面按 JST 展示。';
COMMENT ON COLUMN opc.engagements.closed_at IS '合作关系关闭时刻，带时区时间戳；NULL 表示未关闭，非 NULL 对应 completed 或 cancelled，且不得早于 created_at。关闭不等同于资金结算完成。';
COMMENT ON COLUMN opc.engagements.row_version IS '合作关系记录修订计数，正整数且初始为 1，更新时递增；用于并发控制，不是承接关系、合作条款或成果的业务版本。';

COMMENT ON TABLE opc.assignments IS '合作关系中承接账号的生效与结束历史；同一合作至多一个未结束承接关系，版本顺序递增。写入时要求有效账号及内部接单授权，不表示正式 OPC 认证，也不将接单机制固定为人工派单。';
COMMENT ON COLUMN opc.assignments.engagement_id IS '所属合作关系标识，外键引用 engagements(id)；与 version 组成唯一约束，承接关系创建时合作必须未关闭。';
COMMENT ON COLUMN opc.assignments.version IS '该合作内承接关系的正整数版本，从 1 开始按已有最大版本加 1 递增；用于保留承接账号变更历史，不是合作条款版本。';
COMMENT ON COLUMN opc.assignments.provider_id IS '实际承接账号，外键引用 accounts(id)；写入时要求账号 active 且存在未撤销的内部接单授权，内部授权不等于正式认证。';
COMMENT ON COLUMN opc.assignments.recorded_by IS '登记该承接关系的账号，外键引用 accounts(id)；用于归属记录，具体业务操作权限仍由服务端校验。';
COMMENT ON COLUMN opc.assignments.reason IS '登记或调整承接关系的非空原因说明；用于解释本版本建立原因，不能替代合作双方对条款的确认。';
COMMENT ON COLUMN opc.assignments.started_at IS '本版本承接关系开始时刻，带时区时间戳，默认当前事务时间；界面按 JST 展示。';
COMMENT ON COLUMN opc.assignments.ended_at IS '本版本承接关系结束时刻，带时区时间戳；NULL 表示尚未结束，结束时须与 ended_by、end_reason 同时填写，且不得早于 started_at。';
COMMENT ON COLUMN opc.assignments.ended_by IS '结束本版本承接关系的账号，外键引用 accounts(id)；未结束时为 NULL，结束时与 ended_at、end_reason 一并记录。';
COMMENT ON COLUMN opc.assignments.end_reason IS '结束本版本承接关系的原因；未结束时为 NULL，结束时必须非空并同时填写 ended_at、ended_by。';

COMMENT ON TABLE opc.agreement_versions IS '合作条款的不可变版本快照，绑定同一需求的已审核范围版本；同一合作内版本递增，双方确认分别记录。金额字段不预设托管、抽佣、分账、内部报酬或税务处理方案。';
COMMENT ON COLUMN opc.agreement_versions.engagement_id IS '合作关系标识；与 version 组成主键，并与 request_id 组成外键引用 engagements(id,request_id)，保证条款属于该需求的合作关系。';
COMMENT ON COLUMN opc.agreement_versions.version IS '合作条款正整数版本，同一合作内从 1 开始按已有最大版本加 1 递增；确认和交付须引用具体版本，不能以最新版本自动替代。';
COMMENT ON COLUMN opc.agreement_versions.request_id IS '条款对应的需求标识；参与指向 engagements 和 scope_versions 的复合外键，确保合作和技术整理范围属于同一需求。';
COMMENT ON COLUMN opc.agreement_versions.scope_version IS '条款绑定的技术整理范围版本；与 request_id 组成外键引用 scope_versions(request_id,version)，新增条款时须已有该版本的合规和技术审核通过记录。';
COMMENT ON COLUMN opc.agreement_versions.terms IS '本版本完整合作条款的非空文本；保存当时约定原文，界面语言切换不翻译或改写该业务快照。';
COMMENT ON COLUMN opc.agreement_versions.quoted_amount IS '本版本报价金额，numeric(14,0)，单位为日元，允许非负整数；NULL 表示尚未记录报价，不等于 0 元，也不代表已付款或已结算。';
COMMENT ON COLUMN opc.agreement_versions.currency IS '币种代码，当前仅允许 JPY＝日元，默认 JPY；界面语言切换不更换币种或自动进行汇率换算。';
COMMENT ON COLUMN opc.agreement_versions.due_at IS '本版本约定的到期时刻，带时区时间戳；NULL 表示未约定具体到期时刻，非 NULL 时保存绝对时刻并按 JST 展示。';
COMMENT ON COLUMN opc.agreement_versions.authored_by IS '编制本版本合作条款的账号，外键引用 accounts(id)；编制不等于客户或承接者已经确认。';
COMMENT ON COLUMN opc.agreement_versions.authored_at IS '本版本条款编制记录时刻，带时区时间戳，默认当前事务时间；不是双方确认时间，界面按 JST 展示。';

COMMENT ON TABLE opc.agreement_confirmations IS '客户与承接者对指定合作条款版本的不可变确认记录；每个版本、每一方至多一条确认，不因条款后续修订而自动迁移确认。';
COMMENT ON COLUMN opc.agreement_confirmations.engagement_id IS '所确认条款的合作关系标识；与 agreement_version 组成外键引用 agreement_versions(engagement_id,version)，并参与主键。';
COMMENT ON COLUMN opc.agreement_confirmations.agreement_version IS '明确确认的合作条款版本；与 engagement_id、party 共同唯一标识一次单方确认，不是技术范围版本或交付版本。';
COMMENT ON COLUMN opc.agreement_confirmations.party IS '确认方代码：customer＝该需求的客户，provider＝该合作当前承接者；同一条款版本分别记录双方确认，不能以一方确认代替另一方。';
COMMENT ON COLUMN opc.agreement_confirmations.confirmed_by IS '实际确认账号，外键引用 accounts(id)；写入时根据 party 校验为需求客户或该合作未结束承接关系中的承接账号。';
COMMENT ON COLUMN opc.agreement_confirmations.confirmed_at IS '本方确认该条款版本的时刻，带时区时间戳，默认当前事务时间；不表示付款或履约完成，界面按 JST 展示。';

COMMENT ON TABLE opc.deliveries IS '承接者提交的不可变成果版本及证据，绑定具体承接关系与双方已确认的条款版本。提交仅允许执行中或修正中的合作；提交不自动对客户发布。源码固定版本的语法有效性不证明仓库可访问、内容可取得或测试通过。';
COMMENT ON COLUMN opc.deliveries.engagement_id IS '成果所属合作关系标识，外键引用 engagements(id)；与 version 组成唯一约束，并参与承接关系和合作条款的复合外键。';
COMMENT ON COLUMN opc.deliveries.version IS '该合作内成果的正整数版本，从 1 开始按已有最大版本加 1 递增；内部审核、对客发布和验收均绑定本条具体成果，不能混用旧版本。';
COMMENT ON COLUMN opc.deliveries.assignment_id IS '提交时的承接关系标识；与 engagement_id 组成外键引用 assignments(id,engagement_id)，写入时须为未结束且对应 submitted_by 的承接关系。';
COMMENT ON COLUMN opc.deliveries.agreement_version IS '本成果依据的合作条款版本；与 engagement_id 组成外键引用 agreement_versions(engagement_id,version)，提交时须已有客户与本次提交承接者对该版本的确认。';
COMMENT ON COLUMN opc.deliveries.submitted_by IS '成果提交账号，外键引用 accounts(id)；写入时须为当前承接账号且账号有效、内部接单授权未撤销，不表示具有正式 OPC 认证。';
COMMENT ON COLUMN opc.deliveries.note IS '本成果版本的非空交付说明原文；记录实现内容及需关注事项，语言切换不改写该原文，也不将说明文本视为审核结论。';
COMMENT ON COLUMN opc.deliveries.source_file_id IS '采用上传源码包方式时的私有文件标识，外键引用 files(id)，提交时须 ready 且 clean；NULL 表示采用仓库引用方式。非 NULL 时 repository_url 和 source_commit 必须为 NULL。';
COMMENT ON COLUMN opc.deliveries.repository_url IS '采用仓库引用方式时的 HTTPS 仓库地址；采用上传源码包方式时必须为 NULL。地址格式检查不验证访问授权、网络可达性或仓库真实性，不应携带访问凭证。';
COMMENT ON COLUMN opc.deliveries.source_commit IS '仓库方式的固定完整提交号，必须为 40 位或 64 位小写十六进制文本；上传源码包方式为 NULL。固定提交号不等于提交真实存在或可访问，不能用分支名、HEAD 或 latest 代替。';
COMMENT ON COLUMN opc.deliveries.source_archive_ref IS '源码归档或取得约定的引用说明；仓库方式必须非空，上传源码包方式允许 NULL。该字段不是可访问性、归档已完成或下载成功的验证结果，不应存放凭证。';
COMMENT ON COLUMN opc.deliveries.guide_text IS '本成果版本的非空使用说明文本；作为交付证据保留原文，不表示系统已执行说明中的操作。';
COMMENT ON COLUMN opc.deliveries.test_report_text IS '本成果版本的非空测试报告文本；可记录测试范围、结果和限制，填写非空不证明测试真实执行或全部通过，须由内部审核判断证据。';
COMMENT ON COLUMN opc.deliveries.submitted_at IS '成果版本提交时刻，带时区时间戳，默认当前事务时间；不是审核、发布或验收时间，界面按 JST 展示。';

COMMENT ON TABLE opc.delivery_files IS '指定成果版本的私有交付附件清单，按用途区分源码、说明、测试及演示等。附件须 ready 且 clean；进入内部审核后清单不得增删，关联键不得修改。客户访问须依成果发布状态及业务权限校验。';
COMMENT ON COLUMN opc.delivery_files.delivery_id IS '附件所属的具体成果标识，外键引用 deliveries(id)；与 file_id 组成主键，不因新增成果版本自动复制或转移附件。';
COMMENT ON COLUMN opc.delivery_files.file_id IS '私有交付文件标识，外键引用 files(id)；新增关联时要求文件 ready 且 clean，仅关联文件不自动公开其存储位置或授予下载权限。';
COMMENT ON COLUMN opc.delivery_files.purpose IS '交付附件用途代码：source＝源码，guide＝使用说明，tests＝测试资料，demo＝演示资料，other＝其他资料；用途标记不证明源码可执行或测试通过。';

COMMENT ON TABLE opc.delivery_reviews IS '指定成果版本的一次内部质量审核结论及证据，写入后不可修改或删除。内部审核通过是对客发布条件，不替代客户验收，也不构成支付或绝对安全保证。';
COMMENT ON COLUMN opc.delivery_reviews.delivery_id IS '被审核的具体成果标识，外键引用 deliveries(id) 且唯一；同一成果至多一条审核记录，修订成果应建立新的成果版本。';
COMMENT ON COLUMN opc.delivery_reviews.reviewer_id IS '内部审核操作者账号，外键引用 accounts(id)；是否具有审核权限仍须由可信服务端验证，外键本身不授予该权限。';
COMMENT ON COLUMN opc.delivery_reviews.decision IS '内部审核结论代码：approved＝审核通过，changes_requested＝要求修改，rejected＝审核拒绝；只有 approved 可作为对客发布的审核依据。';
COMMENT ON COLUMN opc.delivery_reviews.evidence IS '支撑内部审核结论的非空证据与说明文本；记录审核依据，不存放账号凭证，也不因字段非空而证明质量检查已充分完成。';
COMMENT ON COLUMN opc.delivery_reviews.reviewed_at IS '内部审核记录时刻，带时区时间戳，默认当前事务时间；不是客户验收时间，界面按 JST 展示。';

COMMENT ON TABLE opc.delivery_publications IS '将内部审核通过的最新成果版本发布给该项目客户的记录；对客发布不等于互联网公开。每项成果至多一条发布记录，可一次性记录撤回，访问和验收须检查未撤回状态及业务权限。';
COMMENT ON COLUMN opc.delivery_publications.delivery_id IS '对客发布的具体成果标识，外键引用 deliveries(id) 且唯一；发布时须为未关闭合作中的最新成果，源码包与附件状态须可用且检查通过。';
COMMENT ON COLUMN opc.delivery_publications.review_id IS '本次发布依据的内部审核记录，外键引用 delivery_reviews(id)；写入时须对应 delivery_id 且结论为 approved，不能引用其他成果的审核。';
COMMENT ON COLUMN opc.delivery_publications.published_by IS '执行对客发布的账号，外键引用 accounts(id)；具体发布权限须由服务端校验，不通过账号外键推断管理员身份。';
COMMENT ON COLUMN opc.delivery_publications.published_at IS '本成果对客发布时刻，带时区时间戳，默认当前事务时间；不代表客户已阅读或验收，界面按 JST 展示。';
COMMENT ON COLUMN opc.delivery_publications.withdrawn_by IS '执行撤回的账号，外键引用 accounts(id)；未撤回时为 NULL，撤回时须与 withdrawn_at、withdrawal_reason 同时填写。';
COMMENT ON COLUMN opc.delivery_publications.withdrawn_at IS '发布撤回时刻，带时区时间戳；NULL 表示未撤回，非 NULL 时不得早于 published_at。撤回限制后续访问，不声称收回已下载或导出的副本。';
COMMENT ON COLUMN opc.delivery_publications.withdrawal_reason IS '撤回对客发布的原因；未撤回时为 NULL，撤回时必须非空并同时记录 withdrawn_at、withdrawn_by。';

COMMENT ON TABLE opc.acceptance_decisions IS '需求客户对最新、内部审核通过且未撤回发布成果的不可变验收决定；仅待验收中的未关闭合作可记录。每项成果至多一个决定，要求修正必须提供理由，验收不自动表示支付结算。';
COMMENT ON COLUMN opc.acceptance_decisions.delivery_id IS '本次验收决定针对的具体成果标识，外键引用 deliveries(id) 且唯一；写入时校验为合作中的最新已发布成果，旧版本不得替代当前版本验收。';
COMMENT ON COLUMN opc.acceptance_decisions.customer_id IS '作出决定的客户账号，外键引用 accounts(id)；写入时须与该成果所属需求的 customer_id 一致，不能由承接者代替客户作出决定。';
COMMENT ON COLUMN opc.acceptance_decisions.decision IS '客户验收决定代码：accepted＝明确验收通过，revision_requested＝要求修正；只作用于 delivery_id 指定成果，不代表资金支付或后续版本自动通过。';
COMMENT ON COLUMN opc.acceptance_decisions.feedback IS '客户验收反馈原文，默认空字符串；revision_requested 时必须为非空修正理由，accepted 时允许空字符串。此列不允许 NULL，语言切换不翻译或改写客户原文。';
COMMENT ON COLUMN opc.acceptance_decisions.decided_at IS '客户作出该版本验收决定的记录时刻，带时区时间戳，默认当前事务时间；界面按 JST 展示。';

COMMENT ON TABLE opc.conversation_threads IS '按需求和用途隔离的会话容器：咨询面向该咨询获准参与者，客户项目会话面向该项目获准参与者，内部会话不得作为客户项目消息对外展示。读取须校验会话参与关系及业务权限；本表及参与者记录不替代服务端授权。';
COMMENT ON COLUMN opc.conversation_threads.request_id IS '会话关联需求标识，外键引用 requests(id)；与 engagement_id 共同约束会话引用的合作关系必须属于同一需求，不授予查看其他需求的权限。';
COMMENT ON COLUMN opc.conversation_threads.kind IS '会话用途代码：consultation＝按发起账号隔离的需求咨询，customer_project＝客户项目沟通，internal＝内部沟通；三种用途的消息可见范围不可混用，不能将 internal 内容并入对客消息。';
COMMENT ON COLUMN opc.conversation_threads.initiator_id IS '咨询发起账号，外键引用 accounts(id)；consultation 时必须非 NULL，且同一需求同一发起者只有一个咨询会话；customer_project 和 internal 时必须为 NULL。';
COMMENT ON COLUMN opc.conversation_threads.engagement_id IS '关联合作关系标识；非 NULL 时与 request_id 组成外键引用 engagements(id,request_id)。customer_project 时必填且每个合作只有一个项目会话，consultation 时必须 NULL，internal 时允许 NULL 表示仅关联需求。';
COMMENT ON COLUMN opc.conversation_threads.created_at IS '会话创建时刻，带时区时间戳，默认当前事务时间；不是最近消息发送时间，界面按 JST 展示。';

COMMENT ON TABLE opc.thread_participants IS '会话参与账号的加入与退出历史，同一会话同一账号至多一条未退出记录。消息写入检查当前参与关系；参与记录不自动授予跨需求、内部会话或管理员权限，读取仍须按业务角色校验。';
COMMENT ON COLUMN opc.thread_participants.thread_id IS '参与关系所属会话，外键引用 conversation_threads(id)；消息可见范围须遵循该会话 kind 及其需求、合作关系边界。';
COMMENT ON COLUMN opc.thread_participants.account_id IS '加入会话的账号，外键引用 accounts(id)；与 thread_id 在 left_at 为 NULL 时保持唯一，不等同于拥有该会话全部关联资料的访问权限。';
COMMENT ON COLUMN opc.thread_participants.added_by IS '登记会话参与关系的账号，外键引用 accounts(id)；邀请或加入权限须由服务端校验，记录者身份不等于被加入者身份。';
COMMENT ON COLUMN opc.thread_participants.joined_at IS '本次加入会话的时刻，带时区时间戳，默认当前事务时间；界面按 JST 展示。';
COMMENT ON COLUMN opc.thread_participants.left_at IS '本次参与关系退出时刻，带时区时间戳；NULL 表示仍在会话中，非 NULL 时不得早于 joined_at，仅允许从未退出改为已退出。退出后的历史消息读取策略须由服务端按业务权限执行。';

COMMENT ON TABLE opc.messages IS '会话内不可变的文本消息；写入者须有未退出的参与记录。消息仅向对应会话获准用户提供，不因需求已发布而进入大厅，不混用咨询、客户项目与内部消息；实际读取、实时投递及推送仍需后端实现。';
COMMENT ON COLUMN opc.messages.thread_id IS '消息所属会话，外键引用 conversation_threads(id)；消息沿该会话的需求和用途边界授权，不可只凭消息标识跨会话读取。';
COMMENT ON COLUMN opc.messages.author_id IS '消息作者账号，外键引用 accounts(id)；写入时须在 thread_participants 中拥有该会话 left_at 为 NULL 的参与记录。';
COMMENT ON COLUMN opc.messages.body IS '消息原文文本，去除首尾空白后的字符数须为 1 至 4000；不自动翻译，不视为可执行代码或受信任 HTML，读取时按会话权限保护。';
COMMENT ON COLUMN opc.messages.client_message_id IS '客户端为一次消息提交生成的 UUID；与 author_id 组成唯一约束，用于重复发送去重。同一作者跨会话也不能复用该标识，不是外键或业务需求编号。';
COMMENT ON COLUMN opc.messages.sent_at IS '消息入库时记录的发送时刻，带时区时间戳，默认当前事务时间；不代表收件人已接收或已阅读，界面按 JST 展示。';

COMMENT ON TABLE opc.notifications IS '面向单个收件账号的站内通知及已读状态，按事件键去重；通知不代替业务原始记录，也不授予关联需求或资料的访问权限。系统推送通道与真实通知处理尚需接入。';
COMMENT ON COLUMN opc.notifications.recipient_id IS '通知收件账号，外键引用 accounts(id)；与 event_key 组成唯一约束，读取应限定本账号或具有相应权限的后台操作。';
COMMENT ON COLUMN opc.notifications.request_id IS '可选关联需求标识，外键引用 requests(id)；NULL 表示未关联具体需求的通知，非 NULL 时打开通知仍须重新校验该需求访问权限。';
COMMENT ON COLUMN opc.notifications.event_key IS '业务事件去重键，与 recipient_id 共同唯一；同一事件可向不同收件人各生成一条通知。当前未限定代码枚举，生成规则由通知业务接口约定。';
COMMENT ON COLUMN opc.notifications.template_key IS '通知本地化模板标识，由界面语言选择对应文本资源；当前未限定代码枚举。模板切换不翻译客户原文、不改变业务版本、币种或时区。';
COMMENT ON COLUMN opc.notifications.parameters IS '通知模板参数 JSON 对象，默认空对象；保存模板需要的参数，具体键由通知接口约定，数据库只约束对象类型。不得存放凭证或用参数绕过关联资料访问权限。';
COMMENT ON COLUMN opc.notifications.created_at IS '站内通知记录创建时刻，带时区时间戳，默认当前事务时间；不等于外部推送送达时间，界面按 JST 展示。';
COMMENT ON COLUMN opc.notifications.read_at IS '收件人标记已读的时刻，带时区时间戳；NULL 表示尚未标记已读，非 NULL 时不得早于 created_at。已读标记不构成业务确认或验收决定。';

COMMENT ON TABLE opc.outbox_events IS '事务发件箱中的待投递业务事件及处理状态，用于后续异步通知或任务分发。当前结构不代表工作进程或消息基础设施已接通；事件处理与业务权限、幂等及重试仍需后端实现。';
COMMENT ON COLUMN opc.outbox_events.topic IS '事件主题或处理路由标识，当前未限定代码枚举；由生产者与消费者接口约定，用于解释 aggregate_id 和 payload 的业务类型。';
COMMENT ON COLUMN opc.outbox_events.aggregate_id IS '事件关联的业务聚合标识 UUID，由 topic 解释所属实体；本列没有外键，不保证指向 requests 或任何特定表，也不等于事件自身标识。';
COMMENT ON COLUMN opc.outbox_events.payload IS '事件载荷 JSON 对象，保存处理所需的业务标识、版本及必要上下文；具体键由主题接口约定，数据库仅校验对象类型。应避免凭证、完整私有消息正文和文件字节，消费者须重新授权及核对版本。';
COMMENT ON COLUMN opc.outbox_events.status IS '事件处理状态代码：pending＝待处理，processing＝处理中，sent＝记录为已投递，failed＝处理失败。sent 不等于用户已读、客户已验收或款项已结算。';
COMMENT ON COLUMN opc.outbox_events.attempts IS '事件处理尝试次数，非负整数，默认 0 表示尚未记录处理尝试；不是重试间隔或成功投递次数。';
COMMENT ON COLUMN opc.outbox_events.available_at IS '事件最早可被处理的时刻，带时区时间戳，默认当前事务时间；可用于延迟处理及失败重试调度，具体调度由工作进程执行。';
COMMENT ON COLUMN opc.outbox_events.locked_until IS '处理租约预计到期时刻，带时区时间戳；NULL 表示未记录租约期限。该值本身不构成数据库行锁，也不能单独证明某工作进程仍在运行。';
COMMENT ON COLUMN opc.outbox_events.completed_at IS '事件处理完成的记录时刻，带时区时间戳；NULL 表示尚未登记完成时间，是否成功还须结合 status，完成含义由消费者协议约定。';
COMMENT ON COLUMN opc.outbox_events.last_error_code IS '最近一次处理错误代码，具体代码集待消费者定义；NULL 表示尚未记录错误代码，不等于处理必然成功，不应保存含凭证的完整异常信息。';
COMMENT ON COLUMN opc.outbox_events.created_at IS '事件写入事务发件箱的时刻，带时区时间戳，默认当前事务时间；不是实际投递完成时刻，界面按 JST 展示。';

COMMENT ON TABLE opc.idempotency_keys IS '按账号、业务操作和调用方幂等键记录请求摘要及可重用结果，支持后续 API 防止重复提交。同键不同请求的冲突判定、结果写入及过期清理由服务端实现，不以本表存在代替完整幂等协议。';
COMMENT ON COLUMN opc.idempotency_keys.actor_id IS '发起幂等操作的账号，外键引用 accounts(id)；与 operation、key 组成主键，隔离不同账号的幂等命名空间，不代表已通过身份认证。';
COMMENT ON COLUMN opc.idempotency_keys.operation IS '业务操作标识，当前未限定代码枚举；与 actor_id、key 共同确定幂等范围，具体命名及权限由 API 契约约定。';
COMMENT ON COLUMN opc.idempotency_keys.key IS '调用方提供的幂等键，长度为 1 至 200 个字符；在同一 actor_id、operation 下唯一，不是认证密钥、访问令牌或可公开分享的业务授权。';
COMMENT ON COLUMN opc.idempotency_keys.request_hash IS '请求内容摘要，格式为 64 位小写十六进制文本；服务端须约定规范化方式与摘要算法，并核对相同幂等键是否对应同一请求。格式约束不完成请求一致性判断。';
COMMENT ON COLUMN opc.idempotency_keys.result IS '可重用的操作结果 JSON 值，当前未限制必须为对象，具体结构由 API 契约约定；SQL NULL 表示未保存结果，不能据此认定业务未执行，JSON null 与 SQL NULL 不同。不得缓存凭证或未授权私有内容。';
COMMENT ON COLUMN opc.idempotency_keys.created_at IS '幂等记录创建时刻，带时区时间戳，默认当前事务时间；用于保留窗口计算，界面按 JST 展示。';
COMMENT ON COLUMN opc.idempotency_keys.expires_at IS '幂等记录的过期时刻，带时区时间戳且必须晚于 created_at；有效期单位由两时刻的差确定，本列不会自动删除记录或自动撤销业务操作。';

COMMENT ON TABLE opc.audit_events IS '追加式结构审计记录，保存对象键和字段名，不记录密码、令牌摘要、消息正文或文件内容。普通修改及删除由触发器禁止，但所有者或超级用户仍可改变数据库，因此不是加密防篡改存证；应用操作者归属也不等于认证证明。';
COMMENT ON COLUMN opc.audit_events.occurred_at IS '审计记录发生时刻，带时区时间戳，默认 clock_timestamp() 的实际当前时刻而非事务开始时间；界面按 JST 展示。';
COMMENT ON COLUMN opc.audit_events.database_actor IS '数据库会话登录角色名，默认 session_user；用于记录数据库连接身份，不等同于应用最终用户，也不随 SET ROLE 的当前执行角色自动替换。';
COMMENT ON COLUMN opc.audit_events.application_actor_id IS '应用操作者账号，外键引用 accounts(id)；自动审计从事务上下文 opc.actor_id 读取，NULL 表示未提供应用账号归属。上下文须由可信后端设置，本列不证明用户已认证或已授权。';
COMMENT ON COLUMN opc.audit_events.correlation_id IS '可选请求或事务关联标识，自动审计从 opc.correlation_id 读取；NULL 表示没有关联标识，用于串联日志，不是外键、访问凭证或业务版本。';
COMMENT ON COLUMN opc.audit_events.table_name IS '审计对象的表名或业务目标名称；自动结构审计写入触发器的 TG_TABLE_NAME，不附带模式名。不是外键，不能仅凭此字段确认操作者权限。';
COMMENT ON COLUMN opc.audit_events.operation IS '审计操作代码：INSERT＝新增记录，UPDATE＝修改记录，DELETE＝删除记录，BUSINESS＝显式业务事件；自动表触发器记录前三类，BUSINESS 的写入语义由可信后端约定。';
COMMENT ON COLUMN opc.audit_events.entity_key IS '被审计实体定位键的 JSON 对象；自动审计提取已配置的 id、关联账号或需求标识、request_version、scope_version、agreement_version、version、party 等键，不保存整行业务内容。具体键随对象结构而异，数据库只约束对象类型。';
COMMENT ON COLUMN opc.audit_events.changed_fields IS '本次涉及的字段名称文本数组，默认空数组；UPDATE 自动记录前后值不同的字段名，INSERT 和 DELETE 自动记录对应行的字段名。仅记录名称，不保存旧值或新值；空数组表示没有登记字段名。';
COMMENT ON COLUMN opc.audit_events.details IS '补充审计信息 JSON 对象，默认空对象，当前自动结构审计不写入额外详情；具体键由可信业务事件约定。只允许必要的非敏感说明，不应放入密码、令牌摘要、消息正文或文件内容；该列不是防篡改签名。';


DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT relname FROM pg_class WHERE relnamespace='opc'::regnamespace AND relkind='r' ORDER BY relname LOOP
    EXECUTE format('COMMENT ON COLUMN opc.%I.id IS %L',t.relname,
      CASE WHEN t.relname='audit_events' THEN '记录唯一标识，沿用原有自增整数；创建后不可修改。'
        ELSE '记录唯一标识，使用 UUID，非空且单列唯一；创建后不可修改，原有业务主键及复合关联约束保持有效。' END);
    EXECUTE format('COMMENT ON COLUMN opc.%I.updated_usr IS %L',t.relname,
      '最近一次写入的业务账号标识，关联 accounts.id，由数据库读取当前事务的 opc.actor_id 自动设置；未指定业务账号的维护操作为 NULL，不继承上次修改人，也不替代真实身份验证。');
    EXECUTE format('COMMENT ON COLUMN opc.%I.updated_at IS %L',t.relname,
      '记录最近一次写入时间，使用带时区时间戳，由数据库在新增或更新时自动维护；数据库默认 UTC，业务界面按日本标准时间显示。原先缺失该字段的存量行以补建字段时刻初始化，不等同原业务事件时间。');
  END LOOP;
END $$;


COMMENT ON VIEW opc.hall_requests IS '任务大厅有效发布视图：仅返回当前范围双审核通过、未下架且无进行中合作的整理字段；不包含客户原文或私有附件，服务端仍须校验大厅访问权限。';
COMMENT ON COLUMN opc.hall_requests.request_id IS '需求唯一标识，来源于 requests.id。';
COMMENT ON COLUMN opc.hall_requests.public_code IS '面向用户显示的需求编号，与数据库唯一标识分开。';
COMMENT ON COLUMN opc.hall_requests.service_code IS '服务类型代码，关联服务字典；当前仅开放 development 开发服务。';
COMMENT ON COLUMN opc.hall_requests.scope_version IS '本次有效发布绑定的技术整理范围版本，不是原文版本或交付版本。';
COMMENT ON COLUMN opc.hall_requests.title IS '当前已审核范围的大厅标题。';
COMMENT ON COLUMN opc.hall_requests.public_summary IS '当前已审核范围的大厅摘要，不直接使用客户私有原始描述。';
COMMENT ON COLUMN opc.hall_requests.category IS '当前已审核范围的开发分类描述。';
COMMENT ON COLUMN opc.hall_requests.goal IS '当前已审核范围需要实现的业务目标。';
COMMENT ON COLUMN opc.hall_requests.included_scope IS '当前已审核范围明确包含的工作内容。';
COMMENT ON COLUMN opc.hall_requests.excluded_scope IS '当前已审核范围明确排除的工作内容。';
COMMENT ON COLUMN opc.hall_requests.deliverables IS '当前已审核范围的交付物清单，使用 JSON 数组保存。';
COMMENT ON COLUMN opc.hall_requests.acceptance_criteria IS '当前已审核范围的验收标准清单，使用 JSON 数组保存，不代表客户已完成验收。';
COMMENT ON COLUMN opc.hall_requests.duration_text IS '当前已审核范围的预计时长说明，不自动等同合作中已确认的交期。';
COMMENT ON COLUMN opc.hall_requests.revision_terms IS '当前已审核范围的修改约定说明。';
COMMENT ON COLUMN opc.hall_requests.publication_id IS '当前有效发布记录的唯一标识，来源于 publications.id。';
COMMENT ON COLUMN opc.hall_requests.published_at IS '当前有效范围的发布时间，带时区；数据库默认 UTC，界面按日本标准时间显示。';

COMMENT ON VIEW opc.hall_reference_files IS '任务大厅当前有效发布资料视图：仅展示明确发布且上传完成、检查通过的参考文件；不返回私有存储键，名称、数量、预览和下载仍须统一校验权限。';
COMMENT ON COLUMN opc.hall_reference_files.request_id IS '资料所属需求的唯一标识。';
COMMENT ON COLUMN opc.hall_reference_files.scope_version IS '资料所绑定的已审核、当前有效发布范围版本。';
COMMENT ON COLUMN opc.hall_reference_files.publication_id IS '资料对应的当前有效发布记录标识。';
COMMENT ON COLUMN opc.hall_reference_files.file_id IS '资料原文件的唯一标识，下载和预览应据此经服务端授权，不将该标识视为公开链接。';
COMMENT ON COLUMN opc.hall_reference_files.original_name IS '可见参考资料的原文件名，不随界面语言切换自动翻译。';
COMMENT ON COLUMN opc.hall_reference_files.kind IS '资料类型：image=图片，video=视频，document=文档，spreadsheet=表格，presentation=演示文稿，pdf=PDF 文档，text=文本，other=其他。';
COMMENT ON COLUMN opc.hall_reference_files.media_type IS '原文件媒体类型，使用 MIME 标识；类型标识不等于文件内容已经验证。';
COMMENT ON COLUMN opc.hall_reference_files.size_bytes IS '原文件大小，单位为字节。';
COMMENT ON COLUMN opc.hall_reference_files.duration_ms IS '视频等媒体的时长，单位为毫秒；NULL 表示未提供或该类型不适用。';
COMMENT ON COLUMN opc.hall_reference_files.sort_order IS '参考资料在当前审核范围内的展示顺序，非负整数，越小越靠前。';

COMMENT ON SCHEMA opc IS 'OPC 日本国内开发服务的统一业务数据结构，供受控后端访问；包含账号、需求审核、发布、交付验收及审计。';
COMMENT ON SEQUENCE opc.request_number_seq IS '用户可读需求编号的取号序列；事务回滚可能产生空号，不能用作业务记录数量。';
COMMENT ON SEQUENCE opc.audit_events_id_seq IS '审计事件自增标识序列；事务回滚可能产生空号，序号连续性不代表审计完整性。';


DO $$ DECLARE missing text; BEGIN
  SELECT string_agg(c.relname,', ' ORDER BY c.relname) INTO missing
  FROM pg_class c WHERE c.relnamespace='opc'::regnamespace AND c.relkind IN ('r','v')
    AND coalesce(obj_description(c.oid,'pg_class'),'') !~ '[一-龥]';
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION '以下表或视图缺少中文注释：%',missing;
  END IF;
  SELECT string_agg(c.relname||'.'||a.attname,', ' ORDER BY c.relname,a.attnum) INTO missing
  FROM pg_class c JOIN pg_attribute a ON a.attrelid=c.oid
  WHERE c.relnamespace='opc'::regnamespace AND c.relkind IN ('r','v')
    AND a.attnum>0 AND NOT a.attisdropped AND coalesce(col_description(c.oid,a.attnum),'') !~ '[一-龥]';
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION '以下字段缺少中文注释：%',missing;
  END IF;
END $$;
