#!/usr/bin/env bash
set +x
set -euo pipefail
IFS=$'\n\t'

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

detect_python() {
    if [ -n "${MATOS_PYTHON:-}" ]; then
        PYTHON_BIN="$MATOS_PYTHON"
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="python3"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_BIN="python"
    else
        die "Python 3.6+ is required"
    fi
    "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1 || die "Python 3.6+ is required"
import sys
raise SystemExit(0 if sys.version_info >= (3, 6) else 1)
PY
}

need curl

[ -n "${MATOS_PAT:-}" ] || die "MATOS_PAT is required"

GITHUB_API="https://api.github.com"
GITHUB_API_VERSION="2022-11-28"

MATOS_INSTALLER_REPO="elemynt-dist/matos"
MATOS_INSTALLER_PATH="installer.sh"


requested="${MATOS_VERSION:-}"
if [ "$#" -gt 0 ]; then
    case "$1" in
        -*) ;;
        *) requested="$1" ;;
    esac
fi
prev=""
for arg in "$@"; do
    if [ "$prev" = "--version" ]; then
        requested="$arg"
        break
    fi
    prev="$arg"
done

[ -n "$requested" ] && case "$requested" in v*) die "Version must not include the leading v: $requested" ;; esac

if [ -n "$requested" ]; then
    tag="v${requested}"
else
    detect_python
    tag=$(curl -fsSL --retry 3 --connect-timeout 15 \
        -H 'Accept: application/vnd.github+json' \
        -H "Authorization: Bearer ${MATOS_PAT}" \
        -H "X-GitHub-Api-Version: ${GITHUB_API_VERSION}" \
        "${GITHUB_API%/}/repos/${MATOS_INSTALLER_REPO}/releases/latest" \
        | "$PYTHON_BIN" -c '
import json, sys
data = json.load(sys.stdin)
tag = data.get("tag_name")
if not isinstance(tag, str) or not tag:
    raise SystemExit("release response missing tag_name")
print(tag)') || die "Failed to resolve latest release from ${MATOS_INSTALLER_REPO}"
fi

curl -fsSL --retry 3 --connect-timeout 15 \
    -H 'Accept: application/vnd.github.raw+json' \
    -H "Authorization: Bearer ${MATOS_PAT}" \
    -H "X-GitHub-Api-Version: ${GITHUB_API_VERSION}" \
    --get \
    --data-urlencode "ref=${tag}" \
    "${GITHUB_API%/}/repos/${MATOS_INSTALLER_REPO}/contents/${MATOS_INSTALLER_PATH}" \
    | MATOS_VERSION="${MATOS_VERSION:-${tag#v}}" \
      bash -s -- "$@"
