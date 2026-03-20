.PHONY: help build up down logs test lint check pipelines shell clean deps compile release

COMPOSE := docker compose
MQ_DIR  := openclaw_mq

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ── Docker (zero-install) ───────────────────

build: ## Build all containers
	$(COMPOSE) build

up: ## Start services (detached)
	$(COMPOSE) up -d

down: ## Stop services
	$(COMPOSE) down

logs: ## Tail service logs
	$(COMPOSE) logs -f

shell: ## Open a shell in the service container
	$(COMPOSE) exec iamq /bin/sh

# ── Elixir (local development) ──────────────

deps: ## Fetch Elixir dependencies
	cd $(MQ_DIR) && mix deps.get

compile: ## Compile the Elixir project
	cd $(MQ_DIR) && mix compile

test: ## Run Elixir tests
	cd $(MQ_DIR) && mix test

release: ## Build a production release
	cd $(MQ_DIR) && MIX_ENV=prod mix release

run: ## Run the service locally (foreground)
	cd $(MQ_DIR) && mix run --no-halt

# ── Python tools ─────────────────────────────

lint: ## Lint Python pipeline tools
	cd tools && ruff check .

fmt: ## Auto-format Python tools
	cd tools && ruff format .

check: lint test ## Run all checks

# ── Pipelines ────────────────────────────────

pipelines: ## Run pipeline runner CLI (pass ARGS="...")
	python3 -m tools.pipeline_runner.cli $(ARGS)

# ── Cleanup ──────────────────────────────────

clean: ## Remove build artifacts
	$(COMPOSE) down -v --rmi local 2>/dev/null || true
	cd $(MQ_DIR) && mix clean 2>/dev/null || true
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
