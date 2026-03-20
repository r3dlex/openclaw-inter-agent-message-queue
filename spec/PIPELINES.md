# Pipelines

Operational and CI/CD pipelines for the IAMQ service. Pipelines are Python scripts in `tools/pipeline_runner/`.

## Running Pipelines

```bash
# Via Docker (zero-install)
make pipelines ARGS="health"
make pipelines ARGS="ci"
make pipelines ARGS="deploy"
make pipelines ARGS="monitor"

# Via Poetry (local, requires Python 3.11+)
poetry install
poetry run iamq-pipeline health

# Direct
python3 -m tools.pipeline_runner.cli health

# List all pipelines
python3 -m tools.pipeline_runner.cli list
```

## Available Pipelines

### `health` — Service Health Check

Verifies the Elixir service and tools are available.

| Check          | What it does                       |
|----------------|------------------------------------|
| MQ Status      | `GET /status` on port 18790        |
| Agent Registry | `GET /agents` on port 18790        |
| Docker         | `docker --version`                 |
| GitHub CLI     | `gh --version`                     |
| Elixir/Mix     | `mix --version`                    |

### `ci` — Continuous Integration

Runs the full quality gate:

1. `mix deps.get` — fetch Elixir dependencies
2. `mix compile --warnings-as-errors` — compile with strict warnings
3. `mix test` — run Elixir tests
4. `ruff check tools/` — lint Python tools
5. `ruff format --check tools/` — format check Python tools

### `deploy` — Build & Push Container

Builds the Docker image (multi-stage: Elixir release + Python tools).

| Env Var         | Default          | Purpose         |
|-----------------|------------------|-----------------|
| `IAMQ_IMAGE`   | `openclaw-iamq`  | Image name      |
| `IAMQ_TAG`     | `latest`         | Image tag       |
| `IAMQ_REGISTRY`| (empty)          | Registry prefix |

### `monitor` — Queue Monitor

Fetches `/status` and flags anomalies.

| Env Var                  | Default | Purpose                    |
|--------------------------|---------|----------------------------|
| `IAMQ_ALERT_MAX_UNREAD` | `100`   | Alert if total unread > N  |

Exit codes: `0` = healthy, `1` = alerts, `2` = service unreachable.

## GitHub Actions

- **CI** (`.github/workflows/ci.yml`): Elixir compile + test, Python lint, Docker build.
- **Deploy** (`.github/workflows/deploy.yml`): Build and push to `ghcr.io` on release.

## Adding New Pipelines

1. Create `tools/pipeline_runner/pipelines/your_pipeline.py` with a `run_your_pipeline() -> int` function.
2. Register it in `tools/pipeline_runner/cli.py` in the `PIPELINES` dict.
3. Document it here.
