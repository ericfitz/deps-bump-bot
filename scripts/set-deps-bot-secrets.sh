#!/usr/bin/env bash
# Set the ericfitz-deps-bot App secrets on a repo (default: the Renovate runner repo).
#
# Values come from ~/.keys and go straight into `gh secret set` on stdin, so they never
# appear in argv, the terminal, or shell history.
#
# Usage: scripts/set-deps-bot-secrets.sh [OWNER/REPO]
set -euo pipefail

REPO="${1:-ericfitz/deps-bump-bot}"
KEYS="${HOME}/.keys"
ID_FILE="${KEYS}/DEPS_BOT_APP_ID"

# Newest ericfitz-deps-bot private key (names carry the generation date, so a lexical sort works).
PEM="$(find "$KEYS" -maxdepth 1 -name 'ericfitz-deps-bot.*.private-key.pem' | sort | tail -1)"

die() { echo "error: $*" >&2; exit 1; }

command -v gh >/dev/null || die "gh is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated"
[ -f "$ID_FILE" ] || die "missing $ID_FILE"
[ -n "$PEM" ] && [ -f "$PEM" ] || die "no ericfitz-deps-bot.*.private-key.pem in $KEYS"
head -1 "$PEM" | grep -q -- '-----BEGIN .*PRIVATE KEY-----' || die "$PEM does not look like a PEM private key"

# Load DEPS_BOT_APP_ID without echoing it.
# shellcheck source=/dev/null
source "$ID_FILE"
[ -n "${DEPS_BOT_APP_ID:-}" ] || die "$ID_FILE did not export DEPS_BOT_APP_ID"
[[ "$DEPS_BOT_APP_ID" =~ ^[0-9]+$ ]] || die "DEPS_BOT_APP_ID is not numeric"

echo "Setting secrets on ${REPO} (key file: $(basename "$PEM"))"
printf '%s' "$DEPS_BOT_APP_ID" | gh secret set DEPS_BOT_APP_ID --repo "$REPO"
gh secret set DEPS_BOT_APP_PRIVATE_KEY --repo "$REPO" < "$PEM"

echo "Done. Secrets now on ${REPO}:"
gh secret list --repo "$REPO" | grep -E '^DEPS_BOT_APP_(ID|PRIVATE_KEY)\b' || die "secrets not listed after set"
