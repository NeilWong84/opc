from datetime import datetime, timezone
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.errors import DomainError
from app.fulfillment import (
    AcceptanceInput,
    AgreementInput,
    CreateEngagement,
    DeliveryInput,
    ReviewInput,
    parties_confirmed,
    require_latest,
    require_state,
)


def repository_delivery(**overrides):
    return {
        "expected_version": 3,
        "agreement_version": 1,
        "note": "包含源码与实际测试材料",
        "repository_url": "https://example.test/customer/repository",
        "source_commit": "a" * 40,
        "source_archive_ref": "约定归档 OPC-001/source.zip；客户已获权限",
        "guide_text": "运行方式和环境变量样例",
        "test_report_text": "已运行 12 项测试，日志见交付材料",
        **overrides,
    }


@pytest.mark.parametrize("commit", ["main", "master", "HEAD", "latest", "a" * 39, "a" * 41, "A" * 40, "z" * 40])
def test_mutable_or_noncanonical_commit_is_rejected(commit):
    with pytest.raises(ValidationError):
        DeliveryInput(**repository_delivery(source_commit=commit))


@pytest.mark.parametrize("length", [40, 64])
def test_full_commit_hash_is_accepted(length):
    assert DeliveryInput(**repository_delivery(source_commit="b" * length)).source_commit == "b" * length


@pytest.mark.parametrize("url", ["http://example.test/repo", "file:///secret", "https:///repo", "https://u:p@example.test/repo", "https://example.test/repo#main"])
def test_repository_requires_https_host_and_no_embedded_credentials(url):
    with pytest.raises(ValidationError):
        DeliveryInput(**repository_delivery(repository_url=url))


@pytest.mark.parametrize("archive", [None, "", "  "])
def test_repository_source_needs_archive_evidence(archive):
    with pytest.raises(ValidationError):
        DeliveryInput(**repository_delivery(source_archive_ref=archive))


def test_source_package_and_repository_are_mutually_exclusive():
    with pytest.raises(ValidationError):
        DeliveryInput(**repository_delivery(source_file_id=uuid4()))
    source = uuid4()
    package = repository_delivery(source_file_id=source, repository_url=None, source_commit=None, source_archive_ref=None)
    assert DeliveryInput(**package).source_file_id == source


def test_duplicate_files_and_primary_source_repetition_are_rejected():
    file_id = uuid4()
    with pytest.raises(ValidationError):
        DeliveryInput(**repository_delivery(files=[{"file_id": file_id, "purpose": "tests"}, {"file_id": file_id, "purpose": "guide"}]))
    with pytest.raises(ValidationError):
        DeliveryInput(**repository_delivery(source_file_id=file_id, repository_url=None, source_commit=None, source_archive_ref=None,
                                             files=[{"file_id": file_id, "purpose": "source"}]))


@pytest.mark.parametrize("field,value", [("published", True), ("submitted_by", str(uuid4())), ("version", 99)])
def test_client_cannot_supply_publication_actor_or_server_version(field, value):
    with pytest.raises(ValidationError):
        DeliveryInput(**repository_delivery(**{field: value}))


def test_revision_requires_customer_feedback_and_acceptance_is_explicit():
    with pytest.raises(ValidationError):
        AcceptanceInput(expected_version=1, decision="revision_requested", feedback="  ")
    with pytest.raises(ValidationError):
        AcceptanceInput(expected_version=1, decision="auto_accepted")
    result = AcceptanceInput(expected_version=1, decision="revision_requested", feedback="  登录失败，请修正  ")
    assert result.feedback == "登录失败，请修正"
    assert AcceptanceInput(expected_version=1, decision="accepted").feedback == ""


def test_qa_has_evidence_and_cannot_impersonate_customer_acceptance():
    with pytest.raises(ValidationError):
        ReviewInput(expected_version=1, decision="approved", evidence="  ")
    with pytest.raises(ValidationError):
        ReviewInput(expected_version=1, decision="accepted", evidence="完成检查")


@pytest.mark.parametrize("amount", [-1, 1.5, True, 100000000000000])
def test_jpy_quote_rejects_negative_fractional_bool_or_out_of_range_amounts(amount):
    with pytest.raises(ValidationError):
        AgreementInput(expected_version=1, scope_version=1, terms="合作条款", reason="双方协商", quoted_amount=amount)


def test_agreement_datetime_must_include_timezone_and_cannot_override_currency():
    base = dict(expected_version=1, scope_version=1, terms="合作条款", reason="双方协商")
    with pytest.raises(ValidationError):
        AgreementInput(**base, due_at="2026-10-20T09:00:00")
    with pytest.raises(ValidationError):
        AgreementInput(**base, currency="USD")
    assert AgreementInput(**base, due_at="2026-10-20T09:00:00+09:00").due_at.utcoffset().total_seconds() == 32400


def test_initial_relationship_cannot_select_workflow_or_admin_actor():
    base = dict(expected_version=1, request_id=uuid4(), provider_id=uuid4(), terms="需要双方确认", reason="记录双方已明确的人选")
    for extras in ({"status": "executing"}, {"created_by": uuid4()}, {"certified": True}):
        with pytest.raises(ValidationError):
            CreateEngagement(**base, **extras)


@pytest.mark.parametrize("status", ["pending_confirmation", "internal_review", "awaiting_acceptance", "completed", "cancelled"])
def test_delivery_only_allowed_in_execution_or_revision(status):
    with pytest.raises(DomainError):
        require_state({"status": status, "closed_at": None}, "executing", "revision")


@pytest.mark.parametrize("status", ["executing", "revision"])
def test_allowed_delivery_states_still_refuse_closed_records(status):
    require_state({"status": status, "closed_at": None}, "executing", "revision")
    with pytest.raises(DomainError):
        require_state({"status": status, "closed_at": datetime.now(timezone.utc)}, "executing", "revision")


def test_old_or_future_business_version_cannot_replace_latest():
    require_latest(3, 3)
    for version in (0, 2, 4):
        with pytest.raises(DomainError):
            require_latest(3, version)


def test_confirmation_requires_current_distinct_parties_and_both_decisions():
    customer, provider, previous_provider = uuid4(), uuid4(), uuid4()
    assert parties_confirmed({"customer": customer, "provider": provider}, customer, provider)
    assert not parties_confirmed({"customer": customer}, customer, provider)
    assert not parties_confirmed({"customer": customer, "provider": previous_provider}, customer, provider)
    assert not parties_confirmed({"customer": provider, "provider": customer}, customer, provider)
    assert not parties_confirmed({"customer": customer, "provider": provider}, customer, None)
    assert not parties_confirmed({"customer": customer, "provider": customer}, customer, customer)
