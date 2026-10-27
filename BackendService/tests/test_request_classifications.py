"""Classification persistence, ownership and pagination against PostgreSQL."""
from uuid import uuid4

import pytest

from tests.test_integration import call, submit

pytestmark = pytest.mark.integration


def test_catalog_and_classified_draft_submission(integration_context):
    ctx = integration_context
    catalog = call(ctx, "GET", "/mobile/request-classifications", "customer")
    assert [x["code"] for x in catalog["platforms"]] == ["web", "website", "android", "ios", "desktop"]
    assert len(catalog["development_types"]) == 6
    assert all(x["name_zh"] and x["name_ja"] for x in catalog["platforms"] + catalog["development_types"])
    call(ctx, "GET", "/mobile/request-classifications", "admin", status=401)
    body = {"platform_code": "web", "development_type_code": "crm", "description": "客户原文，切换界面语言不自动翻译。"}
    draft = call(ctx, "PUT", "/mobile/draft", "customer", payload=body)["draft"]
    assert draft["platform_code"] == "web"
    assert call(ctx, "GET", "/mobile/draft", "customer")["draft"]["development_type_code"] == "crm"
    created = submit(ctx, platform_code="web", development_type_code="crm")
    assert created["original"]["platform_code"] == "web"
    assert created["original"]["development_type_code"] == "crm"
    assert call(ctx, "GET", "/mobile/draft", "customer")["draft"] is None
    history = call(ctx, "GET", f"/mobile/requests/{created['id']}/revisions", "customer")
    assert history["items"][0]["platform_code"] == "web"


def test_classification_filters_before_pagination_and_within_owner(integration_context):
    ctx = integration_context
    first = submit(ctx, platform_code="web", development_type_code="crm")
    submit(ctx, platform_code="android", development_type_code="crm")
    submit(ctx, platform_code="web", development_type_code="hr")
    unclassified = submit(ctx)
    page = call(ctx, "GET", "/mobile/requests?platform_code=web&development_type_code=crm&limit=1", "customer")
    assert page["total"] == 1
    assert page["items"][0]["id"] == first["id"]
    assert page["items"][0]["platform_code"] == "web"
    assert call(ctx, "GET", "/mobile/requests?platform_code=web&development_type_code=crm&offset=1", "customer")["items"] == []
    assert call(ctx, "GET", "/mobile/requests?platform_code=web", "customer")["total"] == 2
    assert call(ctx, "GET", "/mobile/requests?platform_code=web", "stranger")["total"] == 0
    legacy = call(ctx, "GET", "/mobile/requests?platform_code=unclassified&development_type_code=unclassified", "customer")
    assert legacy["total"] == 1 and legacy["items"][0]["id"] == unclassified["id"]


@pytest.mark.parametrize("field,code", [("platform_code", "unknown"), ("development_type_code", "web")])
def test_invalid_classification_never_saved(integration_context, field, code):
    ctx = integration_context
    call(ctx, "PUT", "/mobile/draft", "customer", status=422, payload={field: code})
    call(ctx, "POST", "/mobile/requests", "customer", status=422, key=uuid4().hex, payload={
        "original_description": "这是一个包含非法分类代码的真实需求输入。", "timing_text": "来月", "budget_text": "相談", field: code,
    })
    assert call(ctx, "GET", "/mobile/requests", "customer")["total"] == 0


def test_clarification_preserves_version_classifications(integration_context):
    ctx = integration_context
    created = submit(ctx, platform_code="ios", development_type_code="oa")
    requested = call(ctx, "POST", f"/admin/requests/{created['id']}/clarifications", "admin", status=201, payload={
        "expected_version": created["row_version"], "question": "利用者人数を教えてください。",
    })
    question = requested["clarifications"][0]
    answered = call(ctx, "POST", f"/mobile/requests/{created['id']}/clarifications/{question['id']}/answer", "customer", payload={
        "expected_version": requested["row_version"], "answer": "10名です。",
    })
    assert answered["original"]["platform_code"] == "ios"
    assert answered["original"]["development_type_code"] == "oa"


def test_original_revision_preserves_omitted_codes_and_allows_explicit_unclassified(integration_context):
    ctx = integration_context
    record = submit(ctx, platform_code="desktop", development_type_code="vehicle")
    body = {"expected_version": record["row_version"], "original_description": "车辆管理系统需要新增车辆信息检索功能。", "timing_text": "来月", "budget_text": "相談"}
    revised = call(ctx, "POST", f"/mobile/requests/{record['id']}/revisions", "customer", status=201, payload=body)
    assert revised["original"]["platform_code"] == "desktop"
    assert revised["original"]["development_type_code"] == "vehicle"
    body.update(expected_version=revised["row_version"], platform_code=None, development_type_code=None)
    cleared = call(ctx, "POST", f"/mobile/requests/{record['id']}/revisions", "customer", status=201, payload=body)
    assert cleared["original"]["platform_code"] is None
    history = call(ctx, "GET", f"/mobile/requests/{record['id']}/revisions", "customer")["items"]
    assert history[-1]["platform_code"] == "desktop"
