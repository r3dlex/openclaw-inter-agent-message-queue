# Learnings

Operational lessons, post-mortems, and insights captured during development and operation.

> Add entries in reverse chronological order. Each entry should capture **what happened**, **why**, and **what we changed**.

---

## 2026-03-21 — Architecture Decisions

**Context**: Setting up the inter-agent message queue for OpenClaw.

**Decisions made**:
- Chose Elixir/OTP for the queue service — fault-tolerant supervision, built-in PubSub, ETS for fast in-memory storage.
- Python pipeline runner for operational tooling — practical for CI/CD scripts, `gh` CLI integration, and monitoring.
- ETS (in-memory) for message storage in v0.1; persistence via disk or Redis planned for production.
- Gateway token and local paths extracted to environment variables — never hardcoded in source.
- Agent nicknames resolved at the queue level so agents can address each other informally.

**Rationale**: Elixir's OTP model is a natural fit for a message broker — processes are cheap, supervision restarts failed components, and PubSub is built-in. Python tools complement this for operational automation.

---

*Add new entries above this line.*
