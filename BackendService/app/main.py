import logging
from uuid import uuid4

import psycopg
from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
from starlette.exceptions import HTTPException

from .config import Settings
from .database import Database
from .deps import TxDep
from .errors import DomainError
from .auth import LoginLimiter
from . import auth, files, communication, requests, fulfillment, claims
from .api_docs import install_openapi

logger = logging.getLogger("opc.api")


def create_app(settings: Settings | None = None, database=None):
    settings = settings or Settings()
    app = FastAPI(title="OPC 统一后端 API", version="0.1.0",
                  description="日本国内开发服务。手机与管理会话隔离；内部授权不是正式 OPC 认证。\n\n"
                  "写操作按 expected_version 乐观并发；关键创建需 Idempotency-Key。\n\n"
                  "客户先确认发布范围与条款，承接者再自主承接；record_confirmed 仍只用于管理录入。报价、交付与验收不表示支付。\n\n"
                  "登录后复制 access_token 到 Authorize。数据库不可用时文档仍可浏览，业务返回 503。",
                  swagger_ui_parameters={"docExpansion": "none", "filter": True,
                                         "displayRequestDuration": True, "persistAuthorization": False},
                  docs_url="/docs" if settings.docs_enabled else None,
                  redoc_url="/redoc" if settings.docs_enabled else None,
                  openapi_url="/openapi.json" if settings.docs_enabled else None)
    app.state.settings = settings
    app.state.database = database or Database(settings.database_url)
    app.state.login_limiter = LoginLimiter()
    app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins,
                       allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
                       allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
                       expose_headers=["X-Request-ID"])

    @app.middleware("http")
    async def headers(request, call_next):
        request.state.correlation_id = str(uuid4())
        # Reject obviously oversized bodies before multipart parsing. Streaming request limits
        # must additionally be configured at the reverse proxy for production.
        length = request.headers.get("content-length")
        if length and (not length.isdigit() or int(length) > settings.upload_limit_bytes + 1024 * 1024):
            return error(request, 413, "BODY_TOO_LARGE", "请求体过大")
        response = await call_next(request)
        response.headers["X-Request-ID"] = request.state.correlation_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        return response

    def error(request, status, code, message, details=None):
        result = {"error": {"code": code, "message": message}, "request_id": getattr(request.state, "correlation_id", "")}
        if details:
            result["error"]["details"] = details
        return JSONResponse(result, status_code=status, headers={"WWW-Authenticate": "Bearer"} if status == 401 else None)

    @app.exception_handler(DomainError)
    async def domain_error(request, exc):
        return error(request, exc.status, exc.code, exc.message)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        # Never echo passwords, tokens, uploaded content, or full rejected input.
        details = [{"field": ".".join(str(x) for x in e["loc"]), "type": e["type"]} for e in exc.errors()]
        return error(request, 422, "VALIDATION_ERROR", "参数校验失败", details)

    @app.exception_handler(HTTPException)
    async def http_error(request, exc):
        return error(request, exc.status_code, "HTTP_ERROR", "请求无法处理")

    @app.exception_handler(psycopg.Error)
    async def database_error(request, exc):
        code = exc.sqlstate or ""
        if code in {"23505", "23503", "23514", "55000", "40001", "40P01", "55P03"}:
            return error(request, 409, "STATE_CONFLICT", "记录重复、版本已变化或业务条件不满足，请刷新后重试")
        logger.error("database request failed request_id=%s sqlstate=%s", request.state.correlation_id, code)
        return error(request, 503, "DATABASE_UNAVAILABLE", "数据库不可用，请检查后端连接配置")

    @app.exception_handler(Exception)
    async def unexpected_error(request, exc):
        logger.error("request failed request_id=%s type=%s", request.state.correlation_id, type(exc).__name__)
        return error(request, 500, "INTERNAL_ERROR", "服务暂时不可用，请提供请求编号以便排查")

    @app.get("/", include_in_schema=False)
    def index():
        return RedirectResponse("/docs" if settings.docs_enabled else "/health/live")

    @app.get("/health/live", tags=["运行状态"], summary="进程存活（不代表数据库已连接）")
    def live():
        return {"status": "ok", "service": "opc-backend"}

    @app.get("/health/ready", tags=["运行状态"], summary="数据库、基线与需求分类迁移就绪检查")
    def ready(conn: TxDep):
        row = conn.execute("SELECT count(*) AS count FROM opc.schema_migrations").fetchone()
        if row["count"] < 6:
            raise DomainError(503, "MIGRATIONS_REQUIRED", "需先执行数据库迁移")
        if not conn.execute("SELECT 1 FROM opc.schema_migrations WHERE version='008_request_classifications'").fetchone():
            raise DomainError(503, "MIGRATIONS_REQUIRED", "需先执行需求分类数据库迁移")
        identity = conn.execute("SELECT rolsuper FROM pg_roles WHERE rolname=current_user").fetchone()
        if identity["rolsuper"]:
            raise DomainError(503, "UNSAFE_DATABASE_ROLE", "请配置专用非超级用户应用连接角色")
        return {"status": "ready", "migrations": row["count"]}

    @app.get("/api/v1/capabilities", tags=["运行状态"], summary="实际能力及尚未接入的服务")
    def capabilities():
        return {"service_codes": ["development"], "locales": ["ja", "zh"], "currency": "JPY",
                "business_timezone": "Asia/Tokyo", "hall_audience": settings.hall_audience,
                "assignment_mode": settings.assignment_mode, "file_storage": "local_private",
                "file_inspection": "manual_evidence", "office_pdf_conversion": False,
                "email_push_delivery": False, "password_recovery": False, "email_verification": False,
                "ai_provider": False, "payments": False, "formal_certification": False}

    @app.get("/api/v1/services", tags=["运行状态"], summary="当前启用的开发服务字典")
    def services(conn: TxDep):
        return {"items": conn.execute("SELECT code,name_ja,name_zh FROM opc.service_types WHERE code='development' AND enabled").fetchall()}

    for router in (auth.router, requests.router, fulfillment.router, files.router, communication.router, claims.router):
        app.include_router(router)
    install_openapi(app)
    return app


app = create_app()
