"""补齐只返回 dict/SQL 行的路由在 Swagger / ReDoc 中的响应契约。

这里按 method + path 登记实际返回投影，不修改路由、鉴权或运行时序列化。
带 SELECT * 的后台对象明确允许数据库附加字段；手机端投影单独建模。
示例完全由本文件的合成常量生成，不访问数据库、环境变量或登录令牌。
新增没有 response_model 的接口时必须补登记，避免重新出现空白成功模型。
"""

from __future__ import annotations

from copy import deepcopy


SAMPLE_ID = "00000000-0000-4000-8000-000000000001"
SAMPLE_TIME = "2026-10-16T00:00:00Z"


def string(description="原文文本", *, example="示例文本", enum=None, format=None):
    result = {"type": "string", "description": description, "example": example}
    if enum is not None:
        result["enum"] = enum
        result["example"] = example if example in enum else enum[0]
    if format:
        result["format"] = format
    return result


def integer(description="整数", *, minimum=0, example=1):
    return {"type": "integer", "minimum": minimum, "description": description, "example": example}


def boolean(description="布尔值", example=False):
    return {"type": "boolean", "description": description, "example": example}


def ref(name):
    return {"$ref": "#/components/schemas/" + name}


def nullable(schema):
    return {"anyOf": [schema, {"type": "null"}], "example": None}


def array(items, description="列表"):
    return {"type": "array", "items": items, "description": description}


def obj(description, properties, *, required=None, extra=False):
    return {"type": "object", "description": description, "properties": properties,
            "required": list(properties) if required is None else required, "additionalProperties": extra}


def page(item, *, total=False, paginated=True):
    fields = {"items": array(ref(item), "当前有权访问的记录")}
    if total:
        fields["total"] = integer("经过身份、版本和状态过滤的总数", example=0)
    if paginated:
        fields.update(limit=integer("本次分页上限", minimum=1, example=30), offset=integer("记录偏移量", example=0))
    return obj("列表响应；只有实际返回 total 的接口才声明总数", fields)


ID = string("记录 UUID；示例不是实际业务记录", example=SAMPLE_ID, format="uuid")
DATE = string("带时区时间；界面可按 JST 显示", example=SAMPLE_TIME, format="date-time")
VERSION = integer("当前记录乐观并发版本；写操作通过 expected_version 原样提交", minimum=1)
TEXT = string()
CLASSIFICATION_PROPERTIES = {
    "platform_code": nullable(string("主要开发端字典代码；空值为未分类", example="web")),
    "development_type_code": nullable(string("开发类型字典代码；空值为未分类", example="crm")),
}
OPEN_OBJECT = obj("业务 JSON 对象；键由事件或审计内容决定", {}, required=[], extra=True)
INTAKE = string("受理状态，与审核、发布及履约状态分别记录", example="submitted",
                enum=["submitted", "needs_info", "in_review", "withdrawn", "closed"])
ENGAGEMENT_STATUS = string("合作履约状态", example="pending_confirmation", enum=[
    "pending_confirmation", "executing", "internal_review", "awaiting_acceptance", "revision", "completed", "cancelled",
])
FILE_PROPERTIES = {
    "original_name": string("文件原始名称，不随界面语言翻译", example="运行说明.md"),
    "kind": string("文件分类", example="text"), "media_type": string("声明的 MIME 类型", example="text/markdown"),
    "size_bytes": integer("原文件字节数", example=128), "duration_ms": nullable(integer("视频时长，毫秒")),
}
REQUEST_PROPERTIES = {
    "id": ID, "public_code": string("人类可读需求号", example="REQ-00001001"),
    "service_code": string("当前仅开发服务", example="development", enum=["development"]),
    "intake_status": INTAKE, "current_request_version": integer("原始需求版本", minimum=1),
    "current_scope_version": nullable(integer("当前激活的技术整理版本", minimum=1)),
    "row_version": VERSION, "created_at": DATE, "updated_at": DATE,
}
SCOPE_PROPERTIES = {
    "version": integer("技术整理版本", minimum=1), "request_version": integer("所引用的原始需求版本", minimum=1),
    "title": string("整理后的任务标题", example="库存查询工具"), "public_summary": string("已审核的公开摘要", example="开发用于查询库存的手机工具"),
    "category": string("开发分类", example="业务工具"), "goal": string("目标", example="减少重复查询"),
    "included_scope": string("范围内事项", example="查询页面与权限校验"), "excluded_scope": string("范围外事项", example="不包含支付"),
    "deliverables": array(TEXT, "约定交付物原文"), "acceptance_criteria": array(TEXT, "验收标准原文"),
    "duration_text": string("工期说明", example="双方确认后 10 个工作日"),
    "revision_terms": string("修改与维护边界", example="按已确认范围处理修改"), "authored_at": DATE,
}
REVIEW_PROPERTIES = {
    "id": ID, "scope_version": integer("审核绑定的范围版本", minimum=1),
    "kind": string("审核类型", example="compliance", enum=["compliance", "technical"]),
    "decision": string("审核决定", example="approved", enum=["approved", "needs_info", "rejected"]), "decided_at": DATE,
}
CLARIFICATION_PROPERTIES = {
    "id": ID, "request_version": integer("提问对应的原文版本", minimum=1),
    "question": string("向客户提出的澄清问题", example="请说明库存查询的使用人数"), "asked_at": DATE,
    "answer": nullable(string("客户的原文回答")), "answered_at": nullable(DATE),
}
PUBLICATION_PROPERTIES = {"id": ID, "scope_version": integer("发布范围版本", minimum=1),
                          "published_at": DATE, "withdrawn_at": nullable(DATE)}
ENGAGEMENT_PROPERTIES = {
    "id": ID, "request_id": ID, "public_code": string("需求编号", example="REQ-00001001"),
    "status": ENGAGEMENT_STATUS, "created_at": DATE, "closed_at": nullable(DATE),
    "row_version": VERSION, "provider_id": nullable(ID),
}


def build_schemas():
    """Schema sources are the route return statements and their explicit SQL projections."""
    schemas = {
        "ErrorDetail": obj("只返回字段位置与错误类型，不回显密码、令牌或被拒绝的原文", {
            "field": string("参数位置", example="body.expected_version"),
            "type": string("校验错误类型", example="greater_than_equal"),
        }),
        "ErrorResponse": obj("所有错误使用此包装；request_id 可用于关联服务端日志", {
            "error": obj("稳定错误码与诊断信息", {
                "code": string("稳定机器错误码；界面应据此本地化", example="VERSION_CONFLICT"),
                "message": string("诊断信息", example="记录已变化，请刷新后重新操作"),
                "details": array(ref("ErrorDetail"), "仅参数验证等错误返回"),
            }, required=["code", "message"]),
            "request_id": string("本次请求的关联标识", example=SAMPLE_ID),
        }),
        "DocHealthLive": obj("只表示进程存活", {"status": string(example="ok", enum=["ok"]), "service": string(example="opc-backend")}),
        "DocHealthReady": obj("数据库及基线迁移就绪", {"status": string(example="ready", enum=["ready"]), "migrations": integer("已应用迁移数量", example=6)}),
        "DocCapabilities": obj("实际能力配置；false 表示尚未接入", {
            "service_codes": {**array(string(enum=["development"])), "example": ["development"]},
            "locales": {**array(string(enum=["ja", "zh"])), "example": ["ja", "zh"]},
            "currency": string(example="JPY", enum=["JPY"]), "business_timezone": string(example="Asia/Tokyo"),
            "hall_audience": string(example="internal", enum=["disabled", "internal", "authenticated"]),
            "assignment_mode": string(example="disabled", enum=["disabled", "record_confirmed"]),
            "file_storage": string(example="local_private"), "file_inspection": string(example="manual_evidence"),
            **{key: boolean("当前尚未接入") for key in ["office_pdf_conversion", "email_push_delivery", "password_recovery",
                "email_verification", "ai_provider", "payments", "formal_certification"]},
        }),
        "DocService": obj("服务字典；语言字段仅为界面名称", {
            "code": string(example="development"), "name_ja": string(example="AI開発システム"), "name_zh": string(example="AI 开发系统"),
        }),
        "DocAccount": obj("账号公开投影；内部授权和正式认证严格分开，不含密码或会话令牌", {
            "id": ID, "email": string("账号邮箱", example="customer@example.test", format="email"),
            "display_name": string("显示名", example="示例客户"), "status": string(example="active", enum=["invited", "active", "disabled"]),
            "ui_locale": string(example="ja", enum=["ja", "zh"]), "row_version": VERSION, "created_at": DATE,
            "roles": array(string("实际已授予且未撤销的角色", example="customer")),
            "internally_authorized": boolean("是否具有当前内部承接授权"), "opc_certified": boolean("当前版本固定为 false"),
        }),
        "DocToken": obj("登录产生的用途隔离会话；将实际 access_token 填入 Swagger 的 Authorize", {
            "access_token": string("敏感令牌；此处仅为占位符，不可用于登录", example="<登录接口生成的访问令牌>"),
            "token_type": string(example="bearer", enum=["bearer"]),
            "audience": string("会话用途", example="mobile", enum=["mobile", "admin"]), "expires_at": DATE,
        }),
        "DocRevoked": obj("会话、角色或内部授权已撤销", {"revoked": boolean(example=True)}),
        "DocReauthenticate": obj("密码变更后所有会话已撤销，必须重新登录", {"reauthentication_required": boolean(example=True)}),
        "DocRoleGrant": obj("新增角色授权记录；不是账号认证", {"id": ID, "role_code": string(example="provider"), "granted_at": DATE}),
        "DocProviderGrant": obj("新增内部承接授权记录；不是 OPC 正式认证", {"id": ID, "granted_at": DATE}),
        "DocId": obj("新建或已存在记录的标识", {"id": ID}),
        "DocDeleted": obj("本人草稿已删除", {"deleted": boolean(example=True)}),
        "DocFile": obj("私有文件元数据；存储键和服务器路径不会返回", {
            "id": ID, **FILE_PROPERTIES, "sha256": nullable(string("完整原文件 SHA-256", example="0" * 64)),
            "upload_status": string("上传状态", example="ready"), "scan_status": string("安全检查状态；上传后为 pending", example="pending"),
            "row_version": VERSION,
        }),
        "DocReferenceFile": obj("显式发布且有权限的参考资料；名称、数量和下载使用同一授权边界", {
            "file_id": ID, **FILE_PROPERTIES, "sort_order": integer("显示顺序", example=0),
        }),
        "DocPrivateFile": obj("客户本人或后台有权读取的原始附件投影", {
            "file_id": ID, **FILE_PROPERTIES, "upload_status": string(example="ready"),
            "scan_status": string(example="clean"), "sort_order": integer(example=0),
        }),
        "DocDraft": obj("本人当前需求草稿", {
            **CLASSIFICATION_PROPERTIES,
            "description": TEXT, "timing_text": string(example="两周内"), "budget_text": string(example="预算待确认"),
            "row_version": VERSION, "updated_at": DATE, "files": array(ref("DocPrivateFile")),
        }),
        "DocDraftResponse": obj("没有草稿时 draft 为 null", {"draft": nullable(ref("DocDraft"))}),
        "DocOriginal": obj("原始需求版本；语言切换不改写原文", {
            **CLASSIFICATION_PROPERTIES,
            "version": integer(minimum=1), "original_description": string(example="需要开发一个供内部员工查询库存的小工具。"),
            "timing_text": string(example="两周内"), "budget_text": string(example="预算待确认"), "submitted_at": DATE,
        }),
        "DocOriginalRevision": obj("原文历史及该版本私有附件", {
            **CLASSIFICATION_PROPERTIES,
            "version": integer(minimum=1), "original_description": TEXT, "timing_text": TEXT, "budget_text": TEXT,
            "submitted_at": DATE, "private_files": array(ref("DocPrivateFile")),
        }),
        "DocScope": obj("手机端技术整理投影；参考资料仅包含当前合法发布集合", {
            **SCOPE_PROPERTIES, "reference_files": array(ref("DocReferenceFile")),
        }),
        "DocAdminScope": obj("后台整理版本，additionalProperties 为数据库维护字段等附加字段", {
            **SCOPE_PROPERTIES, "request_id": ID, "authored_by": ID, "reference_files": array(ref("DocPrivateFile")),
        }, extra=True),
        "DocReview": obj("客户可见审核结论，排除内部理由", REVIEW_PROPERTIES),
        "DocAdminReview": obj("后台审核证据；附加数据库维护字段允许存在", {
            **REVIEW_PROPERTIES, "request_id": ID, "reviewer_id": ID, "reason": string("内部审核理由"),
        }, extra=True),
        "DocClarification": obj("客户可见的澄清问答", CLARIFICATION_PROPERTIES),
        "DocAdminClarification": obj("后台澄清及实际操作人；附加数据库维护字段允许存在", {
            **CLARIFICATION_PROPERTIES, "request_id": ID, "asked_by": ID, "answered_by": nullable(ID),
        }, extra=True),
        "DocPublication": obj("客户可见的发布与下架历史", PUBLICATION_PROPERTIES),
        "DocAdminPublication": obj("后台发布证据；附加数据库维护字段允许存在", {
            **PUBLICATION_PROPERTIES, "request_id": ID, "compliance_review_id": ID, "technical_review_id": ID,
            "published_by": ID, "withdrawn_by": nullable(ID), "withdrawal_reason": nullable(TEXT),
        }, extra=True),
        "DocRequestItem": obj("本人需求列表投影", {**REQUEST_PROPERTIES, **CLASSIFICATION_PROPERTIES, "original_description": TEXT}),
        "DocClassification": obj("开发分类双语字典", {
            "code": TEXT, "name_zh": TEXT, "name_ja": TEXT, "enabled": boolean(),
        }),
        "DocClassifications": obj("开发端与开发类型；停用项保留历史显示但不可新选", {
            "platforms": array(ref("DocClassification")), "development_types": array(ref("DocClassification")),
        }),
        "DocAdminRequestItem": obj("后台需求列表；允许维护字段等实际附加字段", {
            **REQUEST_PROPERTIES, "customer_id": ID, "original_description": TEXT,
        }, extra=True),
        "DocRequestDetail": obj("本人受理详情；不包含内部审核理由或后台操作人", {
            **REQUEST_PROPERTIES, "original": nullable(ref("DocOriginal")), "private_files": array(ref("DocPrivateFile")),
            "scope": nullable(ref("DocScope")), "reviews": array(ref("DocReview")),
            "clarifications": array(ref("DocClarification")), "publications": array(ref("DocPublication")),
        }),
        "DocAdminRequestDetail": obj("后台受理详情；附加字段来自现有数据库记录，不对手机端开放", {
            **REQUEST_PROPERTIES, "customer_id": ID, "original": nullable(ref("DocOriginal")),
            "private_files": array(ref("DocPrivateFile")), "scope": nullable(ref("DocAdminScope")),
            "reviews": array(ref("DocAdminReview")), "clarifications": array(ref("DocAdminClarification")),
            "publications": array(ref("DocAdminPublication")),
        }, extra=True),
        "DocEngagementItem": obj("合作列表投影；后台额外包含 customer_id", {
            **ENGAGEMENT_PROPERTIES, "customer_id": ID,
        }, required=list(ENGAGEMENT_PROPERTIES), extra=False),
        "DocEngagement": obj("合作详情的共同头部；不是需求审核或支付状态", {**ENGAGEMENT_PROPERTIES, "customer_id": ID}),
        "DocAgreement": obj("逐版本的合作条款；报价只表示 JPY 报价", {
            "version": integer(minimum=1), "scope_version": integer(minimum=1), "terms": TEXT,
            "quoted_amount": nullable(integer("JPY 整数报价，不代表收款")), "currency": string(example="JPY", enum=["JPY"]),
            "due_at": nullable(DATE), "authored_at": DATE,
            "scope": obj("该条款引用的已审核范围快照", {**{key: SCOPE_PROPERTIES[key] for key in [
                "title", "goal", "included_scope", "excluded_scope", "deliverables", "acceptance_criteria", "duration_text", "revision_terms"]},
                "reference_files": array(ref("DocReferenceFile"))}),
        }),
        "DocConfirmation": obj("实际一方对确切条款版本的确认", {
            "agreement_version": integer(minimum=1), "party": string(enum=["customer", "provider"]),
            "confirmed_by": ID, "confirmed_at": DATE,
        }),
        "DocDeliveryFile": obj("交付文件投影，不含私有存储键", {
            "id": ID, **{key: value for key, value in FILE_PROPERTIES.items() if key != "duration_ms"},
            "sha256": nullable(string("原文件 SHA-256", example="0" * 64)),
            "purpose": string(enum=["source", "guide", "tests", "demo", "other"]),
        }),
        "DocDelivery": obj("交付投影；客户只看到最新、当前条款下有效发布且文件检查通过的交付", {
            "id": ID, "version": integer(minimum=1), "agreement_version": integer(minimum=1),
            "note": TEXT, "source_file_id": nullable(ID), "repository_url": nullable(string("HTTPS 仓库地址", example="https://example.test/repository")),
            "source_commit": nullable(string("完整固定 commit", example="a" * 40)), "source_archive_ref": nullable(TEXT),
            "guide_text": TEXT, "test_report_text": TEXT, "submitted_at": DATE, "published": boolean(example=True),
            "files": array(ref("DocDeliveryFile")),
        }),
        "DocAcceptance": obj("客户对具体交付的明确决定，不触发支付", {
            "id": ID, "delivery_id": ID, "delivery_version": integer(minimum=1),
            "decision": string(enum=["accepted", "revision_requested"]), "feedback": TEXT, "decided_at": DATE,
        }),
        "DocAssignment": obj("仅后台返回的负责人历史；允许数据库维护字段", {
            "id": ID, "engagement_id": ID, "version": integer(minimum=1), "provider_id": ID, "recorded_by": ID,
            "reason": TEXT, "started_at": DATE, "ended_at": nullable(DATE), "ended_by": nullable(ID), "end_reason": nullable(TEXT),
        }, extra=True),
        "DocDeliveryReview": obj("仅后台返回的内部质检证据；不等于客户验收", {
            "id": ID, "delivery_id": ID, "reviewer_id": ID, "decision": string(enum=["approved", "changes_requested", "rejected"]),
            "evidence": TEXT, "reviewed_at": DATE,
        }, extra=True),
        "DocDeliveryPublication": obj("仅后台返回的交付发布与撤回证据", {
            "id": ID, "delivery_id": ID, "review_id": ID, "published_by": ID, "published_at": DATE,
            "withdrawn_by": nullable(ID), "withdrawn_at": nullable(DATE), "withdrawal_reason": nullable(TEXT),
        }, extra=True),
        "DocThread": obj("会话记录；实际业务关系和当前授权决定可见范围，允许数据库维护字段", {
            "id": ID, "request_id": ID, "kind": string(enum=["consultation", "negotiation", "customer_project", "internal"]),
            "initiator_id": nullable(ID), "engagement_id": nullable(ID), "created_at": DATE,
        }, extra=True),
        "DocMessage": obj("读取的消息投影；原文不自动翻译", {
            "id": ID, "author_id": ID, "author_name": string("发送者当前显示名；不返回邮箱或其他账号私有字段"),
            "body": TEXT, "client_message_id": ID, "sent_at": DATE,
        }),
        "DocSentMessage": obj("发送或幂等重放返回的消息投影", {"id": ID, "thread_id": ID, "body": TEXT, "sent_at": DATE}),
        "DocNotification": obj("站内持久化通知；不表示邮件或推送已投递", {
            "id": ID, "template_key": string(example="request.submitted"), "parameters": OPEN_OBJECT,
            "created_at": DATE, "read_at": nullable(DATE),
        }),
        "DocNotificationRead": obj("本人通知的已读状态", {"id": ID, "read_at": DATE}),
        "DocAuditEvent": obj("管理审计投影；不包含密码、令牌或私有文件内容", {
            "id": integer("审计序号", minimum=1), "occurred_at": DATE, "application_actor_id": nullable(ID),
            "correlation_id": nullable(TEXT), "table_name": string(example="requests"), "operation": string(example="UPDATE"),
            "entity_key": OPEN_OBJECT, "changed_fields": array(TEXT), "details": OPEN_OBJECT,
        }),
        "DocDashboard": obj("按实际状态分组的计数；没有记录的状态可能不返回", {
            "requests": array(obj("受理计数", {"intake_status": INTAKE, "count": integer(example=0)})),
            "engagements": array(obj("履约计数", {"status": ENGAGEMENT_STATUS, "count": integer(example=0)})),
        }),
        "DocBinaryFile": {"type": "string", "format": "binary", "description": "通过实时授权后返回的原文件字节；不是 JSON"},
        "DocPreview": obj("文本安全预览，或尚未接入的预览格式状态；图片和 MP4 使用对应二进制媒体类型", {
            "state": string(enum=["ready", "unsupported"], example="unsupported"),
            "format": string(example="text"), "text": TEXT, "truncated": boolean(),
            "error_code": string(example="PREVIEW_CONVERTER_NOT_CONFIGURED"),
            "download_available": boolean(example=True),
        }, required=["state"]),
    }
    hall_fields = {"request_id": ID, "public_code": REQUEST_PROPERTIES["public_code"], "service_code": REQUEST_PROPERTIES["service_code"],
                   "scope_version": integer(minimum=1), **{k: v for k, v in SCOPE_PROPERTIES.items() if k not in ["version", "request_version", "authored_at"]},
                   "publication_id": ID, "published_at": DATE}
    schemas["DocHallItem"] = obj("大厅列表仅含合法当前双审发布投影，不含客户原文或身份", {
        **hall_fields, "reference_count": integer("当前发布且可读取的参考资料数量", example=0)})
    schemas["DocHallDetail"] = obj("大厅详情与同一发布版本参考资料", {**hall_fields, "references": array(ref("DocReferenceFile"))})
    common_engagement = {"engagement": ref("DocEngagement"), "agreements": array(ref("DocAgreement")),
                         "confirmations": array(ref("DocConfirmation")), "deliveries": array(ref("DocDelivery")), "acceptances": array(ref("DocAcceptance"))}
    schemas["DocMobileEngagementDetail"] = obj("手机合作详情，三组内部历史字段固定为空数组", {
        **common_engagement, **{key: {"type": "array", "items": ref(model), "maxItems": 0, "description": "手机响应固定为空"}
                              for key, model in [("assignments", "DocAssignment"), ("reviews", "DocDeliveryReview"), ("publications", "DocDeliveryPublication")]}})
    schemas["DocAdminEngagementDetail"] = obj("后台合作详情及内部证据", {
        **common_engagement, "assignments": array(ref("DocAssignment")), "reviews": array(ref("DocDeliveryReview")), "publications": array(ref("DocDeliveryPublication"))})
    for name, item, total, paginated in [
        ("DocServiceList", "DocService", False, False), ("DocAccountPage", "DocAccount", False, True),
        ("DocRequestPage", "DocRequestItem", True, True), ("DocAdminRequestPage", "DocAdminRequestItem", True, True),
        ("DocHallPage", "DocHallItem", True, True), ("DocOriginalList", "DocOriginalRevision", False, False),
        ("DocClarificationList", "DocClarification", False, False), ("DocAdminClarificationList", "DocAdminClarification", False, False),
        ("DocAdminScopeList", "DocAdminScope", False, False), ("DocAdminReviewList", "DocAdminReview", False, False),
        ("DocEngagementPage", "DocEngagementItem", False, True), ("DocThreadPage", "DocThread", False, True),
        ("DocMessagePage", "DocMessage", False, True), ("DocNotificationPage", "DocNotification", False, True),
        ("DocAuditList", "DocAuditEvent", False, False), ("DocFilePage", "DocFile", False, True),
    ]:
        schemas[name] = page(item, total=total, paginated=paginated)
    return deepcopy(schemas)


def response_contracts():
    """Exact registrations, deliberately avoiding path substring inference."""
    contracts = {}

    def add(method, path, model):
        contracts[(method.lower(), path)] = model

    for path, model in [("/health/live", "DocHealthLive"), ("/health/ready", "DocHealthReady"),
                        ("/api/v1/capabilities", "DocCapabilities"), ("/api/v1/services", "DocServiceList")]:
        add("get", path, model)
    add("post", "/api/v1/mobile/auth/register", "DocAccount")
    for audience in ("mobile", "admin"):
        prefix = "/api/v1/" + audience
        for method, suffix, model in [
            ("post", "/auth/login", "DocToken"), ("get", "/auth/me", "DocAccount"), ("patch", "/auth/me", "DocAccount"),
            ("post", "/auth/logout", "DocRevoked"), ("post", "/auth/password", "DocReauthenticate"),
            ("get", "/engagements", "DocEngagementPage"),
            ("get", "/engagements/{engagement_id}", "DocAdminEngagementDetail" if audience == "admin" else "DocMobileEngagementDetail"),
            ("post", "/files", "DocFile"), ("get", "/files", "DocFilePage"), ("get", "/files/{file_id}", "DocFile"),
            ("get", "/files/{file_id}/download", "DocBinaryFile"), ("get", "/files/{file_id}/preview", "DocPreview"),
            ("get", "/threads", "DocThreadPage"), ("get", "/threads/{thread_id}/messages", "DocMessagePage"),
            ("post", "/threads/{thread_id}/messages", "DocSentMessage"), ("get", "/notifications", "DocNotificationPage"),
            ("post", "/notifications/{notification_id}/read", "DocNotificationRead"),
        ]:
            add(method, prefix + suffix, model)
    for method, suffix, model in [
        ("get", "/accounts", "DocAccountPage"), ("post", "/accounts", "DocAccount"),
        ("put", "/accounts/{account_id}/status", "DocAccount"), ("post", "/accounts/{account_id}/roles", "DocRoleGrant"),
        ("post", "/accounts/{account_id}/roles/revoke", "DocRevoked"),
        ("post", "/accounts/{account_id}/provider-authorization", "DocProviderGrant"),
        ("post", "/accounts/{account_id}/provider-authorization/revoke", "DocRevoked"),
        ("get", "/requests", "DocAdminRequestPage"), ("get", "/requests/{request_id}", "DocAdminRequestDetail"),
        ("get", "/requests/{request_id}/scopes", "DocAdminScopeList"), ("post", "/requests/{request_id}/scopes", "DocAdminRequestDetail"),
        ("get", "/requests/{request_id}/reviews", "DocAdminReviewList"), ("post", "/requests/{request_id}/reviews", "DocAdminRequestDetail"),
        ("post", "/requests/{request_id}/publish", "DocAdminRequestDetail"),
        ("post", "/requests/{request_id}/publication/withdraw", "DocAdminRequestDetail"),
        ("get", "/requests/{request_id}/clarifications", "DocAdminClarificationList"),
        ("post", "/requests/{request_id}/clarifications", "DocAdminRequestDetail"),
        ("post", "/files/{file_id}/inspection", "DocFile"), ("post", "/threads", "DocId"),
        ("get", "/audit-events", "DocAuditList"), ("get", "/dashboard", "DocDashboard"),
    ]:
        add(method, "/api/v1/admin" + suffix, model)
    for method, suffix, model in [
        ("get", "/draft", "DocDraftResponse"), ("put", "/draft", "DocDraftResponse"), ("delete", "/draft", "DocDeleted"),
        ("get", "/request-classifications", "DocClassifications"),
        ("post", "/requests", "DocRequestDetail"), ("get", "/requests", "DocRequestPage"),
        ("get", "/requests/{request_id}", "DocRequestDetail"), ("get", "/requests/{request_id}/revisions", "DocOriginalList"),
        ("post", "/requests/{request_id}/revisions", "DocRequestDetail"), ("post", "/requests/{request_id}/withdraw", "DocRequestDetail"),
        ("get", "/requests/{request_id}/clarifications", "DocClarificationList"),
        ("post", "/requests/{request_id}/clarifications/{clarification_id}/answer", "DocRequestDetail"),
        ("post", "/requests/{request_id}/consultation", "DocId"), ("get", "/hall", "DocHallPage"), ("get", "/hall/{request_id}", "DocHallDetail"),
        ("post", "/requests/{request_id}/negotiation", "DocId"),
        ("get", "/threads/{thread_id}/negotiation", "NegotiationDetail"),
        ("post", "/threads/{thread_id}/proposal", "DocId"),
        ("post", "/claim-proposals/{proposal_id}/confirm", "DocId"),
    ]:
        add(method, "/api/v1/mobile" + suffix, model)
    for path in [
        "/api/v1/admin/engagements", "/api/v1/admin/engagements/{engagement_id}/reassign",
        "/api/v1/mobile/claim-proposals/{proposal_id}/claim",
        "/api/v1/admin/engagements/{engagement_id}/cancel", "/api/v1/admin/engagements/{engagement_id}/agreements",
        "/api/v1/mobile/engagements/{engagement_id}/agreements/{agreement_version}/confirm",
        "/api/v1/mobile/engagements/{engagement_id}/deliveries",
        "/api/v1/admin/engagements/{engagement_id}/deliveries/{delivery_id}/review",
        "/api/v1/admin/engagements/{engagement_id}/deliveries/{delivery_id}/publish",
        "/api/v1/admin/engagements/{engagement_id}/deliveries/{delivery_id}/withdraw",
        "/api/v1/mobile/engagements/{engagement_id}/deliveries/{delivery_id}/acceptance",
    ]:
        add("post", path, "MutationResult")  # Keep the real Pydantic response model.
    return contracts


ERRORS = {
    "401": ("需要有效且用途匹配的会话（适用鉴权接口）", "AUTH_REQUIRED", "请先登录"),
    "403": ("角色、用途或当前授权不足（适用权限检查）", "ROLE_FORBIDDEN", "当前角色无权执行此操作"),
    "404": ("记录不存在或当前账号无权访问（适用对象访问）", "NOT_FOUND", "记录不存在或无权访问"),
    "409": ("业务状态、版本或幂等冲突（适用状态检查）", "VERSION_CONFLICT", "记录已变化，请刷新后重新操作"),
    "422": ("输入校验失败；不回显敏感原始输入", "VALIDATION_ERROR", "参数校验失败"),
    "503": ("数据库、文件或所需能力尚未就绪（适用依赖检查）", "DATABASE_UNAVAILABLE", "所需服务当前不可用"),
    "500": ("未预期异常；使用 request_id 联系维护人员", "INTERNAL_ERROR", "服务暂时不可用，请提供请求编号以便排查"),
}


def example_for(schema, schemas):
    """Deterministic synthetic examples; optional fields are intentionally omitted."""
    if "example" in schema:
        return deepcopy(schema["example"])
    if "$ref" in schema:
        return example_for(schemas[schema["$ref"].rsplit("/", 1)[1]], schemas)
    if "anyOf" in schema:
        return example_for(schema["anyOf"][0], schemas)
    if "enum" in schema:
        return schema["enum"][0]
    kind = schema.get("type")
    if kind == "object":
        return {key: example_for(schema["properties"][key], schemas) for key in schema.get("required", [])}
    if kind == "array":
        return []
    if kind == "integer" or kind == "number":
        return max(1, schema.get("minimum", 0))
    if kind == "boolean":
        return False
    if kind == "null":
        return None
    if schema.get("format") == "uuid":
        return SAMPLE_ID
    if schema.get("format") == "date-time":
        return SAMPLE_TIME
    return "示例文本"


def install_openapi(app):
    """Install once after routers are registered; rebuilding OpenAPI is read-only."""
    if getattr(app.state, "opc_openapi_installed", False):
        return
    original = app.openapi
    app.openapi_schema = None

    def enriched_openapi():
        if app.openapi_schema and app.openapi_schema.get("x-opc-response-contracts"):
            return app.openapi_schema
        schema = original()
        schemas = schema.setdefault("components", {}).setdefault("schemas", {})
        schemas.update(build_schemas())
        contracts = response_contracts()
        for path, methods in schema["paths"].items():
            for method, operation in methods.items():
                if method not in {"get", "post", "put", "patch", "delete", "head", "options"}:
                    continue
                model = contracts.get((method, path))
                if not model:
                    raise ValueError(f"未登记响应契约：{method.upper()} {path}")
                success = next(code for code in operation["responses"] if code.startswith("2"))
                content = {"application/json": {"schema": ref(model), "example": example_for(ref(model), schemas)}}
                if model == "DocToken":
                    content["application/json"]["example"]["audience"] = "admin" if "/admin/" in path else "mobile"
                elif model == "MutationResult":
                    state = "pending_confirmation"
                    if path.endswith("/cancel"):
                        state = "cancelled"
                    elif path.endswith("/confirm"):
                        state = "executing"
                    elif path.endswith(("/deliveries", "/review")):
                        state = "internal_review"
                    elif path.endswith("/publish"):
                        state = "awaiting_acceptance"
                    elif path.endswith("/withdraw"):
                        state = "revision"
                    elif path.endswith("/acceptance"):
                        state = "completed"
                    content["application/json"]["example"]["status"] = state
                if model == "DocPreview":
                    content["application/json"]["example"] = {"state": "unsupported", "error_code": "PREVIEW_CONVERTER_NOT_CONFIGURED", "download_available": True}
                    for media in ["image/png", "image/jpeg", "image/webp", "image/gif", "video/mp4", "video/webm",
                                  "audio/mpeg", "audio/mp4", "audio/wav", "audio/ogg", "audio/flac", "application/pdf"]:
                        content[media] = {"schema": ref("DocBinaryFile")}
                elif model == "DocBinaryFile":
                    content = {"application/octet-stream": {"schema": ref(model)}}
                operation["responses"][success] = {
                    "description": "成功；示例为合成契约数据，不代表已存在的账号、业务记录或服务凭证",
                    "content": content,
                    "headers": {"X-Request-ID": {"description": "本次请求关联标识", "schema": {"type": "string"}}},
                }
                for status, (description, code, message) in ERRORS.items():
                    operation["responses"][status] = {"description": description, "content": {"application/json": {
                        "schema": ref("ErrorResponse"), "example": {"error": {"code": code, "message": message}, "request_id": SAMPLE_ID},
                    }}}
                if path.endswith("/auth/login") or path.endswith("/auth/register"):
                    operation["responses"]["429"] = {"description": "认证请求频率超限", "content": {"application/json": {"schema": ref("ErrorResponse")}}}
                if path.endswith("/files") and method == "post":
                    operation["responses"]["413"] = {"description": "文件或请求体超过当前配置上限", "content": {"application/json": {"schema": ref("ErrorResponse")}}}
                if model == "DocBinaryFile":
                    operation["responses"]["206"] = {"description": "合法 Range 请求的部分原文件内容", "content": deepcopy(content)}
                operation["x-opc-response-model"] = model
                operation["x-opc-contract-source"] = "实际 response_model 或明确返回字段；允许的数据库附加字段已在模型说明中注明"
        schema["x-opc-response-contracts"] = True
        app.openapi_schema = schema
        return schema

    app.openapi = enriched_openapi
    app.state.opc_openapi_installed = True
