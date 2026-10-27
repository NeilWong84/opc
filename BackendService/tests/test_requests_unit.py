"""Request API input and projection boundaries independent of PostgreSQL."""

from types import SimpleNamespace
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.errors import DomainError
from app.requests import (
    HALL_FIELDS,
    REQUEST_FIELDS,
    ClarificationAnswer,
    DraftInput,
    RequestCreate,
    ReviewCreate,
    ScopeCreate,
    authorize_hall,
    project_fields,
    require_customer,
    require_open,
)


def request_input(**changes):
    return {"original_description": "顧客が注文状況を確認できるアプリを作りたいです。", "timing_text": "来月", "budget_text": "相談希望", **changes}


def scope_input(**changes):
    return {
        "expected_version": 1, "title": "注文照会アプリ", "public_summary": "顧客向けの注文照会機能",
        "category": "development", "goal": "照会を効率化", "included_scope": "ログインと注文照会",
        "excluded_scope": "決済機能", "deliverables": ["固定バージョンのソースコード"],
        "acceptance_criteria": ["顧客が自分の注文のみ閲覧できる"], "duration_text": "2週間", "revision_terms": "合意した範囲で対応",
        **changes,
    }


def test_draft_can_be_incomplete_but_submission_cannot():
    assert DraftInput().description == ""
    with pytest.raises(ValidationError):
        RequestCreate(**request_input(original_description="短い説明"))


@pytest.mark.parametrize("changes", [
    {"original_description": " " * 20}, {"timing_text": " \n "}, {"budget_text": "\t"},
    {"service_code": "short_video"}, {"service_code": "documents"},
    {"customer_id": str(uuid4())}, {"intake_status": "published"}, {"reviewer_id": str(uuid4())},
])
def test_submission_cannot_inject_authority_or_bypass_development_scope(changes):
    with pytest.raises(ValidationError):
        RequestCreate(**request_input(**changes))


def test_request_text_remains_in_original_language():
    raw = "お客様の入力原文を自動翻訳せずに保存する。"
    body = RequestCreate(**request_input(original_description=raw))
    assert body.original_description == raw


def test_attachment_selection_rejects_duplicate_ids():
    identifier = uuid4()
    with pytest.raises(ValidationError, match="文件 ID 不能重复"):
        RequestCreate(**request_input(file_ids=[identifier, identifier]))


@pytest.mark.parametrize("field", ["title", "public_summary", "goal", "included_scope", "excluded_scope", "revision_terms"])
def test_scope_requires_concrete_nonblank_scope_and_terms(field):
    with pytest.raises(ValidationError):
        ScopeCreate(**scope_input(**{field: "  "}))


@pytest.mark.parametrize("changes", [
    {"deliverables": []}, {"acceptance_criteria": []}, {"acceptance_criteria": ["  "]},
    {"expected_version": 0}, {"authored_by": str(uuid4())}, {"scope_version": 999},
])
def test_scope_requires_acceptance_evidence_and_server_owned_version(changes):
    with pytest.raises(ValidationError):
        ScopeCreate(**scope_input(**changes))


def test_return_for_information_requires_customer_facing_question():
    values = {"expected_version": 1, "scope_version": 1, "kind": "compliance", "decision": "needs_info", "reason": "利用目的の説明が必要"}
    with pytest.raises(ValidationError, match="澄清问题"):
        ReviewCreate(**values)
    assert ReviewCreate(**values, question="取得した情報の利用目的を教えてください。").question


def test_approval_does_not_silently_create_unanswered_question():
    with pytest.raises(ValidationError):
        ReviewCreate(expected_version=1, scope_version=1, kind="technical", decision="approved", reason="全項目を確認", question="確認事項")


def test_clarification_cannot_be_blank_or_set_answering_identity():
    with pytest.raises(ValidationError):
        ClarificationAnswer(expected_version=1, answer="  ")
    with pytest.raises(ValidationError):
        ClarificationAnswer(expected_version=1, answer="回答です", answered_by=uuid4())


def test_hall_projection_never_inherits_new_private_database_columns():
    row = {
        "request_id": uuid4(), "title": "公開タイトル", "publication_id": uuid4(),
        "customer_id": uuid4(), "original_description": "私的な説明", "review_reason": "内部メモ",
        "storage_key": "secrets/object", "private_files": ["秘密.pdf"], "future_internal_notes": "secret",
    }
    assert set(project_fields(row, HALL_FIELDS)) == {"request_id", "title", "publication_id"}


def test_customer_summary_does_not_expose_internal_actor_or_activation_watermark():
    row = {"id": uuid4(), "row_version": 3, "updated_usr": uuid4(), "highest_activated_scope_version": 2, "customer_id": uuid4()}
    assert set(project_fields(row, REQUEST_FIELDS)) == {"id", "row_version"}


@pytest.mark.parametrize("status", ["withdrawn", "closed"])
def test_closed_intake_cannot_be_reopened_by_revision_or_review(status):
    with pytest.raises(DomainError):
        require_open({"intake_status": status})


@pytest.mark.parametrize("status", ["submitted", "needs_info", "in_review"])
def test_open_intake_can_proceed_to_version_checks(status):
    require_open({"intake_status": status})


def test_provider_role_alone_cannot_submit_a_customer_request():
    actor = SimpleNamespace(audience="mobile", roles=frozenset({"provider"}))
    with pytest.raises(DomainError):
        require_customer(actor)


def test_admin_session_cannot_use_customer_intake_even_with_customer_role():
    actor = SimpleNamespace(audience="admin", roles=frozenset({"customer", "administrator"}))
    with pytest.raises(DomainError):
        require_customer(actor)


@pytest.mark.parametrize("audience", ["disabled", "misspelled_policy"])
def test_hall_fails_closed_when_audience_is_disabled_or_invalid(audience):
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(settings=SimpleNamespace(hall_audience=audience))))
    actor = SimpleNamespace(audience="mobile", roles=frozenset({"customer"}))
    with pytest.raises(DomainError):
        authorize_hall(request, None, actor)


def test_internal_hall_always_checks_current_provider_authorization(monkeypatch):
    import app.requests as requests

    called = []
    monkeypatch.setattr(requests, "ensure_provider", lambda conn, actor: called.append(actor))
    actor = SimpleNamespace(audience="mobile", roles=frozenset({"provider"}))
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(settings=SimpleNamespace(hall_audience="internal"))))
    authorize_hall(request, None, actor)
    assert called == [actor]


def test_authenticated_hall_does_not_grant_admin_audience_access():
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(settings=SimpleNamespace(hall_audience="authenticated"))))
    actor = SimpleNamespace(audience="admin", roles=frozenset({"administrator"}))
    with pytest.raises(DomainError):
        authorize_hall(request, None, actor)
