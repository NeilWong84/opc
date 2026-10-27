# Build from the OPC root: docker build -f BackendService/Dockerfile .
FROM python:3.14-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    HOME=/tmp OPC_STORAGE_ROOT=/var/lib/opc/files \
    OPC_PREVIEW_ROOT=/var/lib/opc/previews OPC_OFFICE_BINARY=/usr/bin/soffice
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       libreoffice-writer libreoffice-calc libreoffice-impress fonts-noto-cjk \
       fonts-liberation fontconfig ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 opc \
    && useradd --uid 10001 --gid opc --no-create-home --shell /usr/sbin/nologin opc \
    && mkdir -p /var/lib/opc/files /var/lib/opc/previews \
    && chown -R opc:opc /var/lib/opc
WORKDIR /app
COPY BackendService/requirements.lock.txt BackendService/requirements.runtime.txt ./
RUN pip install --no-cache-dir -r requirements.runtime.txt -c requirements.lock.txt
COPY BackendService/app ./app
COPY DB/migrations ./migrations
COPY Tools/Deployment/container ./deployment
USER 10001:10001
EXPOSE 8000
ENTRYPOINT ["python", "/app/deployment/entrypoint.py"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--proxy-headers", "--forwarded-allow-ips", "172.30.0.2", "--timeout-keep-alive", "15"]
