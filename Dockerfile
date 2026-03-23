# Multi-stage Dockerfile for OpenClaw MQ (Elixir service + Python tools)

# ── Stage 1: Build Elixir release ────────────────────────────────────────────
FROM elixir:1.15-otp-26-slim AS elixir-build

WORKDIR /app/openclaw_mq

ENV MIX_ENV=prod

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy mix files first (layer caching)
COPY openclaw_mq/mix.exs openclaw_mq/mix.lock* ./
RUN mix deps.get --only prod && mix deps.compile

# Copy source and build release
COPY openclaw_mq/config/ config/
COPY openclaw_mq/lib/ lib/
RUN mix compile && mix release

# ── Stage 2: Python tools ────────────────────────────────────────────────────
FROM python:3.12-slim AS python-tools

WORKDIR /tools

RUN pip install --no-cache-dir poetry==2.1.1 && \
    poetry config virtualenvs.create false

COPY pyproject.toml poetry.lock* ./
RUN poetry install --no-interaction --no-root --only main 2>/dev/null || \
    poetry install --no-interaction --no-root

COPY tools/ tools/

# ── Stage 3: Runtime ─────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libstdc++6 openssl ca-certificates curl python3 python3-pip && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Elixir release
COPY --from=elixir-build /app/openclaw_mq/_build/prod/rel/openclaw_mq ./release/

# Copy Python tools
COPY --from=python-tools /tools/ ./tools-env/
COPY tools/ tools/
COPY pyproject.toml ./

# Copy entrypoint
COPY scripts/entrypoint.sh ./
RUN chmod +x entrypoint.sh

EXPOSE 18790 18793

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:18790/status || exit 1

ENTRYPOINT ["./entrypoint.sh"]
CMD ["serve"]
