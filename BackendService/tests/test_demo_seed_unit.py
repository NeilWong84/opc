import pytest

from app.demo_seed import validate_target


def identity(marker="opc.local-integration.v1", **overrides):
    return {"marker": marker, "superuser": False, "createdb": False, "createrole": False, **overrides}


@pytest.mark.parametrize("url,info", [
    ("postgresql://opc_app@remote.example.com:55440/opc_integration", identity()),
    ("postgresql://opc_app@127.0.0.1:5432/Accounts", identity()),
    ("postgresql://opc_app@127.0.0.1:55440/opc_integration", identity(marker="production")),
    ("postgresql://postgres@127.0.0.1:55440/opc_integration", identity(superuser=True)),
    ("postgresql://opc_app@127.0.0.1:55440/opc_integration", identity(createdb=True)),
    ("postgresql://opc_app@127.0.0.1:55440/opc_integration", identity(createrole=True)),
])
def test_seed_refuses_unmarked_remote_or_privileged_database(url, info):
    with pytest.raises(ValueError):
        validate_target(url, info)


def test_seed_accepts_only_local_project_database_without_exposing_password():
    actual = validate_target("postgresql://opc_app:secret@127.0.0.1:55440/opc_integration", identity())
    assert actual == {"host": "127.0.0.1", "port": 55440, "name": "opc_integration", "marker": "opc.local-integration.v1"}
    assert "secret" not in str(actual)
