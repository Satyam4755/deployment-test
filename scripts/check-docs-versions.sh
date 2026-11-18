#!/usr/bin/env bash
# Keep documentation free of current runtime and package versions.
#
# Versions are configuration. They live in group_vars and role defaults, not
# in docs. If the same value is copied into a page, the page goes stale as soon
# as the pin is upgraded. This check rejects the patterns that caused that drift.
#
# Dated ADRs are historical records, so docs/DECISIONS.md is excluded.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mapfile -t files < <(
  find docs -type f -name '*.md' ! -name 'DECISIONS.md' -print
  printf '%s\n' README.md IMPLEMENTATION.md
)

# 1. Image references such as traefik:v3.7.13, mariadb:11.8 or
#    redis:6.2-alpine. A bare host:port such as socket-proxy:2375 is not a tag.
# 2. Operating-system release in prose.
# 3. A semantic version such as v1.8.1 or 1.0.8. The boundaries avoid matching
#    an IPv4 address (198.51.100.10) or protocol versions like TLS 1.2.
patterns=(
  '(^|[^[:alnum:]])[A-Za-z][A-Za-z0-9_.-]*(/[A-Za-z][A-Za-z0-9_.-]*)*:(v?[0-9]+(\.[0-9]+)+([-._][A-Za-z0-9]+)*|v?[0-9]+([-._][A-Za-z0-9]+)+)([^[:alnum:]]|$)'
  '(^|[^[:alnum:]])(ubuntu|debian|fedora|rocky|almalinux|centos|rhel)[[:space:]]+[0-9]+(\.[0-9])+([^[:alnum:]]|$)'
  '(^|[^0-9A-Za-z.])v?[0-9]+\.[0-9]+\.[0-9]+(([-_][A-Za-z0-9.-]+)|(\.[A-Za-z][A-Za-z0-9.-]*))?([^0-9A-Za-z.]|$)'
)

status=0

for pattern in "${patterns[@]}"; do
  if matches="$(grep -HInEi -- "$pattern" "${files[@]}")"; then
    printf '%s\n' "$matches"
    status=1
  else
    rc=$?
    if (( rc > 1 )); then
      printf 'docs version check: grep failed with status %s\n' "$rc" >&2
      exit 2
    fi
  fi
done

if (( status != 0 )); then
  cat <<'EOF'

Documentation must not contain current runtime or package versions.
Read the canonical pins from group_vars/all/main.yml and the role defaults,
and describe the component instead. See the "Version pins" section in
docs/ROLES.md.
EOF
  exit 1
fi

printf 'docs version check: no runtime or package versions found\n'
