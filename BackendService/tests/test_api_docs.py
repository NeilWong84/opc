"""Response documentation is available without PostgreSQL and matches route shapes."""

from copy import deepcopy
import json
from uuid import UUID

from fastapi.testclient import TestClient
import psycopg
import pytest

from app.api_docs import install_openapi, response_contracts
from app.config import Settings
from app.main import create_app


class OfflineDatabase:
    def transaction(self, *args, **kwargs):
        raise psycopg.OperationalError("intentional unavailable test database")


@pytest.fixture(scope="module")
def documented_app():
    app = create_app(Settings(database_url="postgresql://unused:secret-canary@127.0.0.1/unused"), database=OfflineDatabase())
    install_openapi(app)
    return app


@pytest.fixture(scope="module")
def schema(documented_app):
    return documented_app.openapi()


def resolve(schema, root):
    while "$ref" in schema:
        pieces = schema["$ref"].removeprefix("#/").split("/")
        schema = root
        for piece in pieces:
            schema = schema[piece]
    return schema


def assert_matches(value, schema, root):
    """Validate the JSON Schema subset used in responses without an extra runtime dependency."""
    schema = resolve(schema, root)
    if "anyOf" in schema:
        failures = []
        for option in schema["anyOf"]:
            try:
                assert_matches(value, option, root)
                return
            except AssertionError as exc:
                failures.append(exc)
        raise AssertionError(f"Value does not match any documented alternative: {failures}")
    kind = schema.get("type")
    if kind == "object":
        assert isinstance(value, dict)
        assert set(schema.get("required", [])) <= set(value)
        if schema.get("additionalProperties") is False:
            assert set(value) <= set(schema["properties"])
        for key, item in value.items():
            if key in schema.get("properties", {}):
                assert_matches(item, schema["properties"][key], root)
    elif kind == "array":
        assert isinstance(value, list)
        assert len(value) <= schema.get("maxItems", len(value))
        for item in value:
            assert_matches(item, schema["items"], root)
    elif kind in {"integer", "number"}:
        assert isinstance(value, int if kind == "integer" else (int, float)) and not isinstance(value, bool)
        assert value >= schema.get("minimum", value)
    elif kind == "string":
        assert isinstance(value, str)
        if schema.get("format") == "uuid":
            assert str(UUID(value)) == value
    elif kind == "boolean":
        assert isinstance(value, bool)
    elif kind == "null":
        assert value is None
    if "enum" in schema:
        assert value in schema["enum"]


def operation_schema(schema, method, path, status="200", media="application/json"):
    return resolve(schema["paths"][path][method]["responses"][status]["content"][media]["schema"], schema)


def test_all_current_routes_have_registered_nonempty_success_contracts(schema):
    actual = {(method, path) for path, methods in schema["paths"].items() for method in methods}
    assert len(schema["paths"]) == 74
    assert len(actual) == 90
    assert actual == set(response_contracts())
    for path, methods in schema["paths"].items():
        for operation in methods.values():
            for code, response in operation["responses"].items():
                if code.startswith("2"):
                    assert response["content"]
                    for content in response["content"].values():
                        assert "$ref" in content["schema"] or content["schema"].get("properties")
                        model = resolve(content["schema"], schema)
                        assert model.get("properties") or model.get("format") == "binary"


def test_every_internal_schema_reference_resolves(schema):
    def walk(node):
        if isinstance(node, dict):
            if "$ref" in node:
                assert node["$ref"].startswith("#/components/schemas/")
                assert resolve(node, schema)
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)
    walk(schema)


def test_all_response_examples_match_their_declared_types(schema):
    for methods in schema["paths"].values():
        for operation in methods.values():
            for response in operation["responses"].values():
                for content in response.get("content", {}).values():
                    if "example" in content:
                        assert_matches(content["example"], content["schema"], schema)


def test_real_error_envelope_is_nested_and_validation_does_not_echo_input(schema, documented_app):
    properties = schema["components"]["schemas"]["ErrorResponse"]["properties"]
    assert set(properties) == {"error", "request_id"}
    assert set(properties["error"]["properties"]) == {"code", "message", "details"}
    assert set(schema["components"]["schemas"]["ErrorDetail"]["properties"]) == {"field", "type"}
    with TestClient(documented_app) as client:
        response = client.get("/missing-resource-for-doc-test")
        assert response.status_code == 404
        assert_matches(response.json(), {"$ref": "#/components/schemas/ErrorResponse"}, schema)


def test_common_error_statuses_use_the_same_contract(schema):
    for methods in schema["paths"].values():
        for operation in methods.values():
            for status in ["401", "403", "409", "422", "503"]:
                response = operation["responses"][status]
                assert response["content"]["application/json"]["schema"] == {"$ref": "#/components/schemas/ErrorResponse"}


def test_auth_response_documents_no_profile_in_token_or_private_credentials_in_account(schema):
    token = operation_schema(schema, "post", "/api/v1/mobile/auth/login")
    assert set(token["properties"]) == {"access_token", "token_type", "audience", "expires_at"}
    account = operation_schema(schema, "get", "/api/v1/mobile/auth/me")
    assert {"roles", "internally_authorized", "opc_certified", "row_version"} <= set(account["properties"])
    assert not {"password_hash", "password", "access_token", "token_hash"} & set(account["properties"])
    for audience in ["mobile", "admin"]:
        example = schema["paths"][f"/api/v1/{audience}/auth/login"]["post"]["responses"]["200"]["content"]["application/json"]["example"]
        assert example["audience"] == audience
        assert example["access_token"] == "<登录接口生成的访问令牌>"
    assert "secret-canary" not in json.dumps(schema)


def test_pagination_total_only_exists_where_runtime_returns_it(schema):
    for path in ["/api/v1/mobile/requests", "/api/v1/admin/requests", "/api/v1/mobile/hall"]:
        assert set(operation_schema(schema, "get", path)["properties"]) == {"items", "total", "limit", "offset"}
    for path in ["/api/v1/mobile/engagements", "/api/v1/admin/accounts", "/api/v1/mobile/threads", "/api/v1/mobile/notifications"]:
        assert set(operation_schema(schema, "get", path)["properties"]) == {"items", "limit", "offset"}
    assert set(operation_schema(schema, "get", "/api/v1/admin/audit-events")["properties"]) == {"items"}


def test_mobile_request_and_hall_contracts_exclude_internal_fields(schema):
    request = operation_schema(schema, "get", "/api/v1/mobile/requests/{request_id}")
    assert not {"customer_id", "updated_usr", "highest_activated_scope_version"} & set(request["properties"])
    review = resolve(request["properties"]["reviews"]["items"], schema)
    assert "reason" not in review["properties"] and "reviewer_id" not in review["properties"]
    hall = operation_schema(schema, "get", "/api/v1/mobile/hall/{request_id}")
    assert "references" in hall["properties"]
    assert not {"original_description", "customer_id", "private_files", "reviews"} & set(hall["properties"])


def test_mobile_engagement_internal_history_arrays_are_explicitly_empty(schema):
    mobile = operation_schema(schema, "get", "/api/v1/mobile/engagements/{engagement_id}")
    admin = operation_schema(schema, "get", "/api/v1/admin/engagements/{engagement_id}")
    for key in ["assignments", "reviews", "publications"]:
        assert mobile["properties"][key]["maxItems"] == 0
        assert "maxItems" not in admin["properties"][key]
    mutation = operation_schema(schema, "post", "/api/v1/admin/engagements", status="201")
    assert set(mutation["required"]) == {"engagement_id", "row_version", "status"}


def test_file_download_is_binary_and_preview_has_real_media_alternatives(schema):
    for audience in ["mobile", "admin"]:
        binary = schema["paths"][f"/api/v1/{audience}/files/{{file_id}}/download"]["get"]["responses"]
        assert set(binary["200"]["content"]) == {"application/octet-stream"}
        assert "206" in binary
        preview = schema["paths"][f"/api/v1/{audience}/files/{{file_id}}/preview"]["get"]["responses"]["200"]["content"]
        assert {"application/json", "image/png", "image/jpeg", "image/webp", "video/mp4",
                "audio/mpeg", "audio/wav", "application/pdf"} <= set(preview)
        metadata = operation_schema(schema, "get", f"/api/v1/{audience}/files/{{file_id}}")
        assert "storage_key" not in metadata["properties"]


def test_docs_and_live_status_work_without_database_and_ready_returns_real_503(documented_app, schema):
    with TestClient(documented_app) as client:
        for path in ["/docs", "/redoc", "/openapi.json"]:
            assert client.get(path).status_code == 200
        live = client.get("/health/live")
        assert live.status_code == 200
        assert_matches(live.json(), operation_schema(schema, "get", "/health/live"), schema)
        capabilities = client.get("/api/v1/capabilities")
        assert_matches(capabilities.json(), operation_schema(schema, "get", "/api/v1/capabilities"), schema)
        unavailable = client.get("/health/ready")
        assert unavailable.status_code == 503
        assert_matches(unavailable.json(), {"$ref": "#/components/schemas/ErrorResponse"}, schema)


def test_install_is_idempotent_and_preserves_request_and_auth_contracts():
    app = create_app(database=OfflineDatabase())
    baseline = deepcopy(app.openapi())
    install_openapi(app)
    enriched = app.openapi()
    install_openapi(app)
    assert app.openapi() is enriched
    for path, methods in baseline["paths"].items():
        for method, operation in methods.items():
            for key in ["operationId", "parameters", "requestBody", "security"]:
                assert enriched["paths"][path][method].get(key) == operation.get(key)
    app.openapi_schema = None
    rebuilt = app.openapi()
    assert rebuilt == enriched
