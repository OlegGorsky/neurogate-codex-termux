#!/usr/bin/env bash
set -euo pipefail

SETUP_URL="${NEUROGATE_CODEX_SETUP_URL:-https://raw.githubusercontent.com/OlegGorsky/neurogate-codex-termux/main/setup-neurogate-codex-termux.sh}"

tmp_parent="${TMPDIR:-${PREFIX:-}/tmp}"
if [[ -z "$tmp_parent" || ! -d "$tmp_parent" ]]; then
  tmp_parent="${HOME:-.}"
fi

tmp="$(mktemp "$tmp_parent/neurogate-codex-setup.XXXXXX")"
cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT

curl -fsSL "$SETUP_URL" -o "$tmp"
bash "$tmp" "$@"
