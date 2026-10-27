from uuid import uuid4
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.auth import RegisterInput, LoginLimiter, hash_password, verify_password
from app.config import Settings
from app.deps import Actor, ensure_admin, ensure_mobile
from app.errors import DomainError
from app.files import safe_name, storage_path, file_kind
from app.idempotency import payload_hash
from app.main import create_app


def test_password_hash_salted_and_verifies_without_plaintext():
    secret = "safe-test-password-2026!"
    first, second = hash_password(secret), hash_password(secret)
    assert first != second and secret not in first and first.startswith("$argon2id$")
    assert verify_password(first, secret)
    assert not verify_password(first, "wrong")
    assert not verify_password("broken", secret)


@pytest.mark.parametrize("roles,audience,allowed", [({"administrator"}, "mobile", False), ({"customer"}, "admin", False), ({"quality_reviewer"}, "admin", False), ({"operator"}, "admin", True), ({"administrator"}, "admin", True)])
def test_role_and_audience_both_required(roles, audience, allowed):
    actor = Actor(uuid4(), audience, frozenset(roles))
    if allowed:
        ensure_admin(actor, "operator")
    else:
        with pytest.raises(DomainError):
            ensure_admin(actor, "operator")


def test_admin_cannot_use_mobile_session_helper():
    with pytest.raises(DomainError):
        ensure_mobile(Actor(uuid4(), "admin", frozenset({"administrator"})))


@pytest.mark.parametrize("name", ["../key", "C:\\private", "bad\r\nname", "a\x00b", "", " "])
def test_invalid_filenames(name):
    with pytest.raises(DomainError):
        safe_name(name)


def test_storage_path_does_not_accept_arbitrary_keys(tmp_path):
    with pytest.raises(DomainError):
        storage_path(tmp_path, "../../secret")
    assert storage_path(tmp_path, uuid4().hex).parent == tmp_path.resolve()
    assert file_kind("資料.PDF") == "pdf"


def test_register_rejects_privilege_injection_and_weak_password():
    base = {"email": "person@example.com", "password": "long-enough-password", "display_name": "客户"}
    with pytest.raises(ValidationError):
        RegisterInput(**base, roles=["administrator"])
    with pytest.raises(ValidationError):
        RegisterInput(**{**base, "password": "short"})


def test_limiter_and_idempotency_hash_semantics():
    limiter = LoginLimiter()
    limiter.check("key", limit=1)
    with pytest.raises(DomainError) as error:
        limiter.check("key", limit=1)
    assert error.value.status == 429
    assert payload_hash({"a": 1, "b": "原文"}) == payload_hash({"b": "原文", "a": 1})
    assert payload_hash({"a": 1}) != payload_hash({"a": 2})


def test_docs_health_and_openapi_without_database():
    client = TestClient(create_app(Settings(_env_file=None)))
    assert client.get("/health/live").json()["status"] == "ok"
    assert client.get("/docs").status_code == 200
    assert client.get("/redoc").status_code == 200
    schema = client.get("/openapi.json").json()
    assert len(schema["paths"]) >= 60
    assert schema["components"]["securitySchemes"]["HTTPBearer"]["scheme"] == "bearer"
    assert client.get("/api/v1/capabilities").json()["assignment_mode"] == "disabled"
    hidden = TestClient(create_app(Settings(_env_file=None, docs_enabled=False)))
    assert hidden.get("/docs").status_code == 404
    assert hidden.get("/openapi.json").status_code == 404
