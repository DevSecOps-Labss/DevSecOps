# syntax=docker/dockerfile:1

########################
# Stage 1: Builder
# Compiles/installs dependencies into an isolated venv.
# Build tools never make it into the final image.
########################
FROM python:3.12-slim-trixie AS builder

ARG srcDir=src

# Build deps needed only to compile C-extension wheels (e.g. psutil) if no
# prebuilt wheel exists for the target platform. Removed after use.
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY $srcDir/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

########################
# Stage 2: Runtime
# Minimal final image: no compilers, no package manager cache, non-root user.
########################
FROM python:3.12-slim-trixie AS runtime

LABEL Name="Python Flask Demo App" Version=1.4.2
LABEL org.opencontainers.image.source="https://github.com/benc-uk/python-demoapp"

ARG srcDir=src

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Dedicated non-root, non-login system user to run the app as
RUN groupadd --gid 1000 appuser \
    && useradd --uid 1000 --gid appuser --shell /usr/sbin/nologin --no-create-home appuser

WORKDIR /app

# Bring in only the installed packages from the builder stage
COPY --from=builder /opt/venv /opt/venv

# Copy app code with correct ownership baked in (avoids an extra chown layer)
COPY --chown=appuser:appuser $srcDir/run.py .
COPY --chown=appuser:appuser $srcDir/app ./app

# Drop root privileges before the app ever runs
USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/', timeout=2)" || exit 1

CMD ["gunicorn", "-b", "0.0.0.0:5000", "--workers", "2", "run:app"]
