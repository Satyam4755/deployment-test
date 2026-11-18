#!/usr/bin/env bash
# Guardrail for ADR-026: the tracked repository must not reveal who runs this
# stack.
#
# Structural checks run everywhere and use no secret input:
#   1. every tracked environment vault is encrypted;
#   2. every vault_* variable referenced by tracked configuration is defined in
#      the example vaults, so CI can resolve it without a vault password;
#   3. the two example vaults define the same keys;
#   4. no private key material or live provider token is committed;
#   5. no .DS_Store is tracked.
#
# Value check (optional): set SENSITIVE_PATTERNS to a newline-separated list of
# real identifiers, or create an untracked .sensitive-patterns file. The list
# must never be committed, because publishing the denylist would publish the
# values it protects. In CI, provide it as a repository secret.
#
# Usage:
#   bash scripts/check-sensitive.sh
#   SENSITIVE_PATTERNS=$'real-domain.tld\nreal-org' bash scripts/check-sensitive.sh

set -euo pipefail

cd "$(dirname "$0")/.."

failed=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failed=1
}

info() {
  printf '%s\n' "$*"
}

# --- 1. Tracked environment vaults must be encrypted ---------------------
while IFS= read -r vault; do
  [ -n "$vault" ] || continue
  first_line=$(head -n 1 "$vault")
  case "$first_line" in
    '$ANSIBLE_VAULT'*) ;;
    *) fail "$vault is tracked but is not an encrypted Ansible vault" ;;
  esac
done < <(git ls-files 'group_vars/*/vault.yml')

# --- 2. Every referenced vault_* variable is defined in the examples -----
# Scan tracked configuration and templates, never the vaults or the docs (the
# docs contain illustrative names that do not have to exist).
# `vault_pass` and `vault_id` are file names and flags, not variables.
referenced=$(git grep -hoE 'vault_[A-Za-z0-9_]+' -- \
  'group_vars/**/*.yml' 'roles/**/*.yml' 'roles/**/*.j2' \
  'playbooks/**/*.yml' '.github/workflows/*.yml' \
  ':!group_vars/*/vault.yml' 2>/dev/null \
  | grep -vE '^vault_(pass|id)' | sort -u || true)
defined=$(grep -hoE '^vault_[A-Za-z0-9_]+' examples/vault.development.yml examples/vault.production.yml \
  | sort -u || true)

while IFS= read -r name; do
  [ -n "$name" ] || continue
  if ! grep -qxF "$name" <<<"$defined"; then
    fail "$name is referenced but missing from examples/vault.*.yml"
  fi
done <<<"$referenced"

# --- 3. The two example vaults define the same keys ----------------------
dev_keys=$(grep -oE '^vault_[A-Za-z0-9_]+' examples/vault.development.yml | sort)
prod_keys=$(grep -oE '^vault_[A-Za-z0-9_]+' examples/vault.production.yml | sort)
if [ "$dev_keys" != "$prod_keys" ]; then
  fail "examples/vault.development.yml and examples/vault.production.yml define different keys"
  diff <(printf '%s\n' "$dev_keys") <(printf '%s\n' "$prod_keys") >&2 || true
fi

# --- 4. No private keys or live provider tokens --------------------------
secret_patterns='-----BEGIN (OPENSSH|RSA|EC|DSA|PGP) PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}'
if git grep -nIE -- "$secret_patterns" -- . >/dev/null 2>&1; then
  git grep -nIE -- "$secret_patterns" -- . >&2 || true
  fail "private key material or live provider token found in tracked files"
fi

# --- 5. Editor droppings are not tracked ---------------------------------
if git ls-files | grep -qE '(^|/)\.DS_Store$'; then
  fail ".DS_Store is tracked"
fi

# --- 6. Optional denylist of real identifiers ---------------------------
patterns="${SENSITIVE_PATTERNS:-}"
if [ -z "$patterns" ] && [ -f .sensitive-patterns ]; then
  patterns=$(cat .sensitive-patterns)
fi

if [ -n "$patterns" ]; then
  info "Checking tracked files against the supplied sensitive-pattern list."
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    if git grep -nIF -- "$pattern" -- . >/dev/null 2>&1; then
      git grep -nIF -- "$pattern" -- . >&2 || true
      fail "a supplied sensitive pattern appears in tracked files"
    fi
  done <<<"$patterns"
else
  info "SENSITIVE_PATTERNS is not set; structural checks only."
  info "Set it locally or as a CI secret to check for real identifiers."
fi

if [ "$failed" -ne 0 ]; then
  printf '\nSensitive-data check failed. See docs/SECRETS.md and ADR-026.\n' >&2
  exit 1
fi

printf '\nSensitive-data check passed.\n'
