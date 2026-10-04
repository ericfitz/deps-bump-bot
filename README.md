# deps-bump-bot

Automated dependency updates for ericfitz repos that use several package ecosystems at once (Go, Node, Python/uv, GitHub Actions, Docker).

It is self-hosted [Renovate](https://docs.renovatebot.com/), running as the `ericfitz-deps-bot` GitHub App, plus a shared preset:

- `default.json`: the shared preset. Repos adopt it with `{ "extends": ["github>ericfitz/deps-bump-bot"] }`.
- `.github/workflows/renovate.yml`: the runner (daily at 13:00 UTC, or run manually).
- `renovate-global.json`: the runner's own config.

See [docs/adoption.md](docs/adoption.md) to adopt a repo and [ADR 0001](docs/adr/0001-use-renovate-shared-preset.md) for why this uses Renovate instead of a custom bot.
