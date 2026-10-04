# Adopting deps-bump-bot (Renovate)

deps-bump-bot is a self-hosted Renovate setup:

- **Preset** (`default.json`): the shared rules that every repo pulls in with `extends`.
- **Runner** (`.github/workflows/renovate.yml`): runs daily at 13:00 UTC as the **ericfitz-deps-bot** GitHub App.

See [ADR 0001](adr/0001-use-renovate-shared-preset.md) for why.

## What the preset does

- **One PR per ecosystem per base branch.** The groups are `go modules`, `go toolchain`, `node packages`, `python packages` (including PEP 723 inline scripts), `github actions`, `docker images`, `terraform` and `kubernetes manifests`.
- **Paths:** test modules are included (`config:recommended` would skip `**/test/**`). Only `node_modules`, `vendor`, `testdata` and `fixtures` directories are ignored.
- **PR titles look like `chore(deps): update <group>`.** Repos are squash-only, so version-bump-bot reads the title as the commit subject and applies a patch bump.
- **Patch, minor, pin and digest updates merge automatically** once required checks pass. Majors, and Go toolchain jumps to a new minor line, wait for approval on the Dependency Dashboard issue.
- **Routine updates run Mondays before 06:00 UTC.** A release must also be at least 3 days old (`minimumReleaseAge`). Releases with no timestamp, which is common for Docker registries such as Oracle's or ECR Public, skip the 3-day wait instead of being blocked forever (`minimumReleaseAgeBehaviour: timestamp-optional`).
- **Indirect Go dependencies are not updated** (Renovate's default).
- **Dependabot alerts open fix PRs right away.** These skip both the schedule and the release-age wait.
- **Go:** `go mod tidy` runs after updates. The `go` directive is never raised.

## One-time App setup (Eric)

**ericfitz-deps-bot** needs these repository permissions:

| Permission | Access | Why |
|---|---|---|
| Contents | Read and write | Push `renovate/*` branches |
| Pull requests | Read and write | Open, update and merge PRs |
| Issues | Read and write | Dependency Dashboard issue |
| Workflows | Read and write | Commits that edit `.github/workflows/*` (Actions updates) |
| Checks | Read | Decide when auto-merge is safe |
| Commit statuses | Read and write | Renovate's own status checks |
| Dependabot alerts | Read | Vulnerability-fix PRs |
| Metadata | Read | Required |

- **Secrets on ericfitz/deps-bump-bot:** `DEPS_BOT_APP_ID` and `DEPS_BOT_APP_PRIVATE_KEY`.
- **Install the App** on ericfitz/deps-bump-bot and on each adopting repo.
- **Never** make it a ruleset bypass actor. Its changes always go through PRs.

## Adopting a repo

1. Install ericfitz-deps-bot on the repo.
2. Add `renovate.json`, or `.github/renovate.json` if the repo's `.gitignore` is an allowlist (tmi's is):
   ```json
   { "extends": ["github>ericfitz/deps-bump-bot"] }
   ```
   Add repo-specific holds, base branches and custom managers next to the `extends` line. `examples/tmi/renovate.json` shows a full example.
3. Make sure required status checks are set on the base branches, since auto-merge waits for them.
   - If GitHub auto-merge is **disabled** on the repo, add `"platformAutomerge": false`. Renovate then merges the PR itself on a later run, once every check is green.
4. Stop Dependabot version updates: delete the `updates:` entries in `.github/dependabot.yml` and any Dependabot auto-merge workflow. Leave Dependabot **alerts** on.
5. Trigger a first run from deps-bump-bot's Actions tab: **Renovate** → Run workflow, with `repositories: ericfitz/<repo>`. Use `dryRun: full` first to preview.

## Notes

- `pep723` (uv inline-script metadata) has no default file pattern. Point it at your scripts, for example `"pep723": { "managerFilePatterns": ["/^scripts/.+\\.py$/"] }`.
- Go modules satisfied by a local `replace` (for example a test module that replaces the root module) need `enabled: false` on that module path. Otherwise the pseudo-version shows up as a major update.
- `postUpgradeTasks` commands must match the runner's `allowedCommands` in `renovate-global.json`. Today that is only `go -C <dir> mod tidy`.
- Dry-run any preset change locally against a copy of a repo:
  ```bash
  renovate --platform=local --dry-run=lookup
  ```
  Inline the preset into the copy's config, because `github>` presets resolve from `main`.
