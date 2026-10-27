"""Prepare/revoke local Android integration-test credentials without printing secrets.

Only test APKs use the generated define file. Normal APP builds must use their
own API URL arguments. Generated customer/provider records remain in local PG
as inspection evidence; the administrator token is revoked after the run.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import secrets
from urllib.parse import urlsplit
from uuid import uuid4

import httpx


BACKEND = Path(__file__).resolve().parents[1]
CONFIG = BACKEND / ".local" / "mobile-e2e.json"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "revoke"])
    parser.add_argument("--base-url", default="http://127.0.0.1:8001")
    args = parser.parse_args()
    url = urlsplit(args.base_url)
    if url.hostname not in {"127.0.0.1", "localhost"} or url.username or url.password:
        parser.error("Only a local integration backend is supported")
    with httpx.Client(base_url=args.base_url, timeout=20) as client:
        if args.action == "revoke":
            if CONFIG.exists():
                config = json.loads(CONFIG.read_text(encoding="utf-8"))
                if not config.get("OPC_E2E_ADMIN_TOKEN"):
                    print("Test administrator session already revoked")
                    return
                response = client.post("/api/v1/admin/auth/logout", headers={"Authorization": "Bearer " + config["OPC_E2E_ADMIN_TOKEN"]})
                if response.status_code not in {200, 401}:
                    raise RuntimeError(f"Token revoke failed: HTTP {response.status_code}")
                config.pop("OPC_E2E_ADMIN_TOKEN", None)
                CONFIG.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
                print("Test administrator session revoked; local define file token removed")
            return
        if CONFIG.exists():
            prior = json.loads(CONFIG.read_text(encoding="utf-8"))
            if prior.get("OPC_E2E_ADMIN_TOKEN"):
                result = client.post("/api/v1/admin/auth/logout", headers={"Authorization": "Bearer " + prior["OPC_E2E_ADMIN_TOKEN"]})
                if result.status_code not in {200, 401}:
                    raise RuntimeError("Cannot revoke previous test session")
        manifest = json.loads((BACKEND / ".local" / "demo-credentials.json").read_text(encoding="utf-8"))
        if manifest["database"]["marker"] not in {"opc.local-integration.v1", "opc.local-development.v1"}:
            raise RuntimeError("A marked local demo database is required")
        response = client.get("/health/ready")
        response.raise_for_status()
        capabilities = client.get("/api/v1/capabilities").json()
        if capabilities["assignment_mode"] != "record_confirmed":
            raise RuntimeError("This test server must explicitly enable record_confirmed for synthetic test relationships")
        admin = manifest["accounts"]["admin"]
        response = client.post("/api/v1/admin/auth/login", json={"email": admin["email"], "password": admin["password"]})
        response.raise_for_status()
        token = response.json()["access_token"]
        headers = {"Authorization": "Bearer " + token}
        run_id = uuid4().hex[:12]
        password = secrets.token_urlsafe(24)
        email = f"mobile-provider-{run_id}@example.jp"
        try:
            response = client.post("/api/v1/admin/accounts", headers=headers, json={"email": email, "password": password, "display_name": f"Android member {run_id}"})
            response.raise_for_status()
            provider_id = response.json()["id"]
            response = client.post(f"/api/v1/admin/accounts/{provider_id}/roles", headers=headers, json={"role": "provider", "reason": "Synthetic Android integration test"})
            response.raise_for_status()
            response = client.post(f"/api/v1/admin/accounts/{provider_id}/provider-authorization", headers=headers, json={"reason": "Synthetic Android test authorization, not certification"})
            response.raise_for_status()
            config = {"APP_ENV": "api", "OPC_API_BASE_URL": args.base_url, "OPC_ALLOW_INSECURE_HTTP": "true", "OPC_E2E_RUN": run_id,
                      "OPC_E2E_CUSTOMER_EMAIL": f"mobile-customer-{run_id}@example.jp", "OPC_E2E_CUSTOMER_PASSWORD": secrets.token_urlsafe(24),
                      "OPC_E2E_PROVIDER_EMAIL": email, "OPC_E2E_PROVIDER_PASSWORD": password, "OPC_E2E_PROVIDER_ID": provider_id,
                      "OPC_E2E_ADMIN_TOKEN": token}
            CONFIG.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception:
            client.post("/api/v1/admin/auth/logout", headers=headers)
            raise
        print(f"Prepared Android integration run {run_id}; secrets saved only to {CONFIG}")


if __name__ == "__main__":
    main()
