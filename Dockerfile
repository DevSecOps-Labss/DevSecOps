# syntax=docker/dockerfile:1

########################
# Stage 1: Builder
########################
FROM python:3.12-slim-trixie AS builder

ARG srcDir=src

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY $srcDir/requirements.txt .
RUN python -m pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# 2. DELETE and PURGE the vulnerable packages entirely from the venv
RUN pip uninstall -y setuptools msgpack

# 3. Clean-download ONLY the safe, verified versions
RUN pip install --no-cache-dir "setuptools==84.0.0" "msgpack==1.2.2"

########################
# Stage 2: Runtime
########################
FROM python:3.12-slim-trixie AS runtime

LABEL Name="Python Flask Demo App" Version=1.4.2
LABEL org.opencontainers.image.source="https://github.com/benc-uk/python-demoapp"

ARG srcDir=src

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    WORKERS=2

RUN groupadd --gid 1000 appuser \
    && useradd --uid 1000 --gid appuser --shell /usr/sbin/nologin --no-create-home appuser

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=appuser:appuser $srcDir/run.py .
COPY --chown=appuser:appuser $srcDir/app ./app

# 150-byte entrypoint. 'exec' makes gunicorn replace the shell as PID 1.
RUN printf '#!/bin/sh\nexec gunicorn -b 0.0.0.0:5000 --workers "${WORKERS}" --access-logfile - --error-logfile - run:app\n' > /app/entrypoint.sh \
    && chmod +x /app/entrypoint.sh

USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/', timeout=2)" || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
