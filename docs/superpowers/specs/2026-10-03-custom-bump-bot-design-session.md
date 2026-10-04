# Custom dependency bot: design-session notes (parked)

**Date:** 2026-10-03
**Status:** Parked. Superseded for now by [ADR 0001](../../adr/0001-use-renovate-shared-preset.md): Renovate with a shared preset.
**Why keep this:** it records Eric's decisions and the design we reached for a custom bot. If Renovate's gaps (listed at the end) turn out to matter, start here instead of from scratch.

## Context

- The goal is a portable bot that bumps dependencies in repos with several package ecosystems, doing more than Dependabot. It replaces tmi's tmi-specific `.github/workflows/deps-bump.yml`, which runs the `deps:bump` skill headless in Claude Code.
- Inherited from the version-bump-bot spec (decisions 2, 3, 9, 10):
  - The bot is portable and independent of tmi, with one repo per bot.
  - Test repos are local `git init` only.
  - The `ericfitz-deps-bot` App is reused.
  - PRs are ordinary squash-merged `chore(deps): …` PRs that never edit version files; version-bump-bot applies a patch bump after merge.
- tmi's cutover needs (tmi agent, 2026-10-03):
  - Triggers: a daily alert poll, plus manual runs for one branch or all.
  - Branches: `main` and `dev/*`, one PR per branch.
  - Go: a root module and a `test/integration` module.
  - Node with pnpm 9 (no `packageManager` field), Python with uv, GitHub Actions, Docker.
  - Go toolchain floor: patch updates only, mirrored into `Dockerfile.server-oracle`.
  - Holds: go-sqlite3 stays below v2; golang/protobuf is ignored.
  - Validation: `make lint`, `make build-server`, `make test-unit`.
  - Auto-merge.

## Human-made decisions (Eric Fitzgerald, 2026-10-03)

1. **Engine: hybrid.** Deterministic updaters, validation, and bisection; an optional LLM only for triage and major-upgrade plans.
2. **Runtime:** a reusable workflow plus a CLI pinned `@v1`. The App is only a token identity; there is no hosted service. Alerts are polled daily.
3. **v1 ecosystems:** Go modules plus the toolchain floor; Node (pnpm, plus npm); Python (uv); GitHub Actions; Docker base images.
4. **Language:** Python + uv with a few small, pinned libraries (ruamel.yaml, tomlkit, packaging).
5. **PR grouping:** one PR per target branch, one commit per ecosystem, the whole tree validated together. Packages that fail bisection are dropped and listed in the PR body.
6. **Auto-merge:** squash auto-merge once the base's required checks pass, never an immediate merge. A config switch turns it off.
7. **LLM advisory only:** headless Claude Code with `CLAUDE_CODE_OAUTH_TOKEN`, read-only tools, and no GitHub write token. It writes into the PR body or an issue and never edits code.
8. **Dependabot:** the bot replaces Dependabot version updates and `dependabot-auto-merge.yml`. Dependabot alerts stay on as the trigger; `security-deps-gate.yml` stays.
9. **Approach A:** our own adapters built on native tools, plus a shared core. Rejected: Renovate as an engine inside the bot, and combining Dependabot's PRs.
10. **Pivot (later the same day):** park the custom bot. Use Renovate with a shared preset and ecosystem groups (ADR 0001).

## Design reached (Sections 1–6 approved; Section 7 presented)

### 1. Architecture and adoption

- **CLI `deps-bump`:** subcommands `discover`, `plan`, `apply`, `pr`, `doctor`. Code lives in `src/deps_bump/{adapters,core}`.
- **Workflow:** a reusable `bump.yml` (`workflow_call`) with a discover job, then four jobs per branch: plan → apply → advise → pr.
- **Releases:** `vX.Y.Z` plus a moving `v1` tag.
- **Secrets:** `DEPS_BOT_APP_ID` and `DEPS_BOT_APP_PRIVATE_KEY`, plus an optional `CLAUDE_CODE_OAUTH_TOKEN`.
- **App permissions:**
  - Contents read/write
  - Pull requests read/write
  - **Workflows read/write.** Needed to push edits to `.github/workflows`.
  - Dependabot alerts read
  - Metadata read

### 2. Config file `.github/deps-bump.toml`

- `[[ecosystem]]` entries are declared explicitly: type plus `dirs` or `files`. Nothing is auto-detected.
- Other tables: `[branches] include` globs; `[validate] commands`, `setup` and `timeout_minutes`; `[pr]` with title, labels and `auto_merge`; `[llm] enabled`.
- `go-toolchain` takes `mirror` entries (file plus regex) and `policy = "patch"`.
- `[[hold]]` entries take `allow` (a version range) or `ignore`. Holds only narrow what's allowed, never widen it. Inline `# deps-bump: hold <range>` comments also count.
- Patch and minor updates are applied. A major, or a minor on 0.x, is only listed.

### 3. Run flow

1. Adapters apply **exact pins**, so any subset of updates can be rebuilt exactly.
2. Apply all candidates and validate.
3. On failure, validate the unmodified base once. If the base fails too, report "base is red" and open no PR.
4. Otherwise bisect: whole ecosystems first, then packages, halving the suspects each time. The budget is `max_validations` = 8 plus the job timeout. Leftover suspects are dropped as "not isolated". The final good set is validated once more.
5. Commit once per ecosystem.
6. `deps-bump-report.json` records what was applied, what was dropped (with log tails), what was held, and which majors are available.
7. The PR comes from a stable `deps-bump/<branch>` branch, force-pushed each run so it updates one PR. That PR is closed when nothing is left to apply.

### 4. Adapters

- **go:**
  - Direct requires only.
  - `go get` + `go mod tidy` in every module dir, with `GOTOOLCHAIN=local`.
  - An update that would raise the `go` line is dropped.
- **go-toolchain:** the go.dev feed, newest patch in the same minor line.
- **node:** pnpm or npm, chosen by lockfile. The `package.json` version is rewritten with its `^`/`~` prefix kept; the lockfile is updated with scripts off.
- **python:** `uv lock --upgrade-package`, within the existing `pyproject` ranges.
- **actions:**
  - Exact tags and SHA-plus-comment pins are updated.
  - Floating `@vN` tags are never changed.
- **docker:**
  - A `FROM` tag only moves to another tag with the same suffix.
  - `tag@sha256` digests are refreshed when the tag stays the same.
  - Lookups use anonymous registry v2 tokens.

### 5. Security and errors

- **plan:** a read-only token; runs no repo code.
- **apply:** `permissions: {}`, no secrets.
- **advise:** only the OAuth token.
- **pr:** the only job holding the App token. Before pushing, it checks that only adapter-declared files changed and that every commit's parent is the planned base.
- **Error handling:**
  - A lookup failure skips that ecosystem with a warning.
  - A red base fails the job.
  - If GitHub refuses auto-merge, the PR stays open.

### 6. Testing

- **Local only.** Unit tests cover the editors, holds, version comparison, bisection against a fake validator, and the pr job's bundle check.
- **Offline integration tests:**
  - Go: a `GOPROXY=file://` directory.
  - npm/pnpm: a stub registry over HTTP.
  - uv: a directory of wheels.
  - Actions, Docker, and the go.dev feed: fake HTTP servers.
- **End-to-end:** a polyglot `git init` fixture.
- **CI:** ruff, a type checker, pytest, and actionlint.

### 7. tmi cutover (presented, not approved)

- Each tmi need maps to a config entry.
- `[validate] setup` replaces a workflow input for installing lint tools.
- tmi deletes `dependabot-auto-merge.yml` and the Dependabot version-update entries; `security-deps-gate.yml` stays.
- tmi-ux has auto-merge turned off at the repo level.

## Why we pivoted: Renovate gap analysis

Renovate with config alone covers about 80% of the design above:

- **Managers:** gomod (with `gomodTidy` across modules), pnpm v9, uv.lock, github-actions (digest pins), dockerfile (digests).
- **Branches:** `baseBranches` produces one PR set per branch.
- **Go lines:** the `toolchain` line is updated by default and the `go` line is left alone.
- **Holds:** `packageRules` with `allowedVersions` or `enabled: false`.
- **Majors:** Dependency Dashboard approval.
- **Alerts:** `vulnerabilityAlerts` reads Dependabot alerts directly.
- **Merging:** auto-merge.
- **Commits:** semantic commit messages.
- **Sharing:** shared presets.
- **Validation:** the repo's existing PR checks.

What it lacks:

1. Bisecting a failing combined PR. Mitigation: group by ecosystem.
2. Detecting a red base branch.
3. LLM advice.
4. A hard guarantee that a dependency update never raises the `go` line. `constraints.go` only partly covers this.

Revisit the custom bot (or a small add-on that works on Renovate's PRs) if ecosystem groups that get blocked prove to be a real problem in practice.
