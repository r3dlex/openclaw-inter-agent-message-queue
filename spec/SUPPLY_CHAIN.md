# Supply-Chain Pins

> Tracks the pinned digests of base Docker images that
> `openclaw-inter-agent-message-queue` builds against. The pin is to a
> content-addressable digest, not a floating tag, so the build is
> reproducible and immune to upstream image re-pushes or silent rebuilds.

## Current Pins

| Component | Version label | Digest | Source |
|---|---|---|---|
| `elixir:1.15-otp-26-slim` | Elixir 1.15 / OTP 26 (slim, debian) | `sha256:88149b50cd689d78e17fa84a5f0e68615a0aa1173a7e19352b1a06d2eda3fdd3` | `docker pull elixir:1.15-otp-26-slim` + `docker images --digests elixir:1.15-otp-26-slim` |
| `python:3.12-slim` | Python 3.12 (slim) | `sha256:090ba77e2958f6af52a5341f788b50b032dd4ca28377d2893dcf1ecbdfdfe203` | `docker pull python:3.12-slim` + `docker images --digests python:3.12-slim` |
| `debian:bookworm-slim` | Debian Bookworm (slim) | `sha256:0104b334637a5f19aa9c983a91b54c89887c0984081f2068983107a6f6c21eeb` | `docker pull debian:bookworm-slim` + `docker images --digests debian:bookworm-slim` |

> The version label is human-readable; the digest is the integrity guarantee.
> The digest in the `Dockerfile` and the value recorded here must always match.

## Where the Pins Live in the Code

| File | Line(s) | What it pins |
|---|---|---|
| `Dockerfile` | line 4 `FROM` (elixir-build) | `elixir:1.15-otp-26-slim` digest |
| `Dockerfile` | line 33 `FROM` (python-tools) | `python:3.12-slim` digest |
| `Dockerfile` | line 47 `FROM` (runtime) | `debian:bookworm-slim` digest |

## Bump Procedure

For each pin: `docker pull` + `docker images --digests` to discover the new digest, update the `FROM` line in the `Dockerfile`, update the **Current Pins** table, add a row to the **History** table. PR title: `chore(supply-chain): bump <image>:<tag> digest`.

## Pre-Merge Checklist

- [ ] `docker build -t iamq:pin-test .` succeeds locally.
- [ ] `spec/SUPPLY_CHAIN.md` is updated and committed in the **same** PR.

## Out of Scope (for this file)

- The `sidecar/` directory at the repo root is an orphan from a prior v0.1.0 era
  that has since been migrated to `openclaw-shared-base/iamq_sidecar`. It is
  scheduled for retirement in a separate workstream and is NOT pinned by this
  PR.
- `openclaw-shared-base` SHA pin: not consumed by this repo's Dockerfiles (the
  path-dep lives in consumer agents, not the IAMQ backbone itself). The Wave 2
  `openclaw-shared-base` v0.2.0/v0.2.1 fleet-wide pin wave is tracked in
  `r3dlex/openclaw-gitrepo-agent/spec/SUPPLY_CHAIN.md`.

## History

| Date | Component | Old pin | New pin | PR |
|---|---|---|---|---|
| 2026-06-06 | `elixir:1.15-otp-26-slim` | floating tag | `sha256:88149b50cd689d78e17fa84a5f0e68615a0aa1173a7e19352b1a06d2eda3fdd3` | (this PR, initial pin) |
| 2026-06-06 | `python:3.12-slim` | floating tag | `sha256:090ba77e2958f6af52a5341f788b50b032dd4ca28377d2893dcf1ecbdfdfe203` | (this PR, initial pin) |
| 2026-06-06 | `debian:bookworm-slim` | floating tag | `sha256:0104b334637a5f19aa9c983a91b54c89887c0984081f2068983107a6f6c21eeb` | (this PR, initial pin) |
