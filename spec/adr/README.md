# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the IAMQ project.

ADRs document significant technical decisions with context, alternatives considered, and consequences.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [001](001-message-queue-design.md) | Message Queue Design | Accepted |

## Creating a New ADR

Use [archgate](https://github.com/archgate-io/archgate-cli) or create manually:

```bash
# With archgate CLI
archgate adr new "Your Decision Title"

# Manual: copy the template
cp 001-message-queue-design.md NNN-your-decision.md
```

Follow the format: `NNN-short-title.md` with Status, Date, Context, Decision, Alternatives, Consequences.
