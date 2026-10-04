# ADR 0001: Use Renovate with a shared preset instead of a custom dependency bot

**Date:** 2026-10-03
**Status:** Accepted
**Decision maker:** Eric Fitzgerald (human-made decision)

## Context

We designed a custom multi-ecosystem bump bot (see
`docs/superpowers/specs/2026-10-03-custom-bump-bot-design-session.md`). A gap analysis then showed
that Renovate, configured with config alone, covers about 80% of that design: Go modules and
toolchain, pnpm, uv, GitHub Actions digests, Docker digests, per-branch PRs, holds, Dependabot-alert
PRs, auto-merge, and semantic commits. It does this with no code for us to maintain. The main thing
it lacks is isolating the failing package inside one combined PR.

## Decision (Eric, 2026-10-03)

- Use **Renovate** with a **shared preset** that lives in this repo. Each adopting repo `extends` the
  preset and adds only its own settings, such as its holds.
- Updates are **grouped by ecosystem**, so one failing package blocks only its own ecosystem's PR.
- **Patch and minor only** are applied automatically. Majors need approval on the Dependency
  Dashboard.
- **Terraform and Kubernetes manifests (kustomize/helm) also get ecosystem groups**, with the same rules. Eric decided this after the tmi dry run found them.
- **Self-hosted** with `renovatebot/github-action` in this repo, authenticated as the ericfitz-deps-bot App. The Mend-hosted app was rejected.
- **No LLM triage workflow for now.** Add one only if failing Renovate PRs become a burden.
- The custom bot is parked, not abandoned.

## Consequences

- No CLI, adapters, or release process to maintain.
- Validation comes from each repo's existing required PR checks.
- A failing update blocks its ecosystem's group until a human fixes it or adds a hold.
- Revisit this decision if blocked groups become common.
