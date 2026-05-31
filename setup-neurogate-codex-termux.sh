#!/usr/bin/env bash
set -euo pipefail

PROVIDER_NAME='NeuroGate API'
BASE_URL='https://api.neurogate.space/v1'
DEFAULT_MODEL='gpt-5.5'
DEFAULT_REASONING_EFFORT='medium'

NON_INTERACTIVE=0
MODEL="$DEFAULT_MODEL"
API_KEY="${NEUROGATE_API_KEY:-${OPENAI_API_KEY:-}}"

usage() {
  cat <<USAGE
NeuroGate API setup for Codex in Termux.

Usage:
  bash setup-neurogate-codex-termux.sh [options]

Options:
  --non-interactive     Do not prompt. Requires an env key or existing auth.json.
  --model MODEL         Codex model to write to config.toml. Default: gpt-5.5.
  -h, --help            Show this help.

Environment:
  NEUROGATE_API_KEY     Preferred way to pass the key in non-interactive mode.
  OPENAI_API_KEY        Fallback key variable for OpenAI-compatible tooling.
                         If neither is set, an existing auth.json key is reused.
  CODEX_HOME            Optional Codex config directory. Default: ~/.codex.
USAGE
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'Внимание: %s\n' "$*" >&2
}

die() {
  printf 'Ошибка: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    --model)
      [[ $# -ge 2 ]] || die '--model требует значение'
      MODEL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "неизвестный аргумент: $1"
      ;;
  esac
done

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_DIR/config.toml"
AUTH_FILE="$CODEX_DIR/auth.json"

is_termux() {
  [[ "${PREFIX:-}" == *'/com.termux/'* ]] && return 0
  [[ "${TERMUX_VERSION:-}" != '' ]] && return 0
  [[ "$(uname -o 2>/dev/null || true)" == 'Android' ]] && return 0
  return 1
}

maybe_install_curl() {
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    die 'curl не найден. Установи его в Termux: pkg install curl'
  fi

  if ! command -v pkg >/dev/null 2>&1; then
    die 'curl не найден, а pkg недоступен. Установи curl и запусти скрипт снова'
  fi

  printf 'curl не найден. Установить через pkg install curl? [Y/n] '
  local answer
  IFS= read -r answer
  case "${answer:-Y}" in
    y|Y|yes|YES|д|Д|да|ДА)
      pkg install -y curl
      ;;
    *)
      die 'curl нужен для проверки API'
      ;;
  esac
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/}"
  value="${value//$'\r'/}"
  printf '%s' "$value"
}

toml_escape() {
  json_escape "$1"
}

trim_key() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

read_existing_api_key() {
  [[ -f "$AUTH_FILE" ]] || return 1

  local existing_key=''
  if command -v python3 >/dev/null 2>&1; then
    existing_key="$(AUTH_FILE_PATH="$AUTH_FILE" python3 - <<'PY'
import json
import os

try:
    with open(os.environ["AUTH_FILE_PATH"], encoding="utf-8") as fh:
        payload = json.load(fh)
except Exception:
    raise SystemExit(0)

for key in ("OPENAI_API_KEY", "openai_api_key", "api_key"):
    value = payload.get(key)
    if isinstance(value, str) and value.strip():
        print(value.strip())
        break
PY
)"
  elif command -v node >/dev/null 2>&1; then
    existing_key="$(AUTH_FILE_PATH="$AUTH_FILE" node -e '
const fs = require("fs");
try {
  const payload = JSON.parse(fs.readFileSync(process.env.AUTH_FILE_PATH, "utf8"));
  for (const key of ["OPENAI_API_KEY", "openai_api_key", "api_key"]) {
    const value = payload[key];
    if (typeof value === "string" && value.trim()) {
      process.stdout.write(value.trim());
      break;
    }
  }
} catch (_) {}
')"
  elif command -v jq >/dev/null 2>&1; then
    existing_key="$(jq -r '.OPENAI_API_KEY // .openai_api_key // .api_key // empty' "$AUTH_FILE" 2>/dev/null || true)"
  else
    existing_key="$(sed -n 's/^[[:space:]]*"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$AUTH_FILE" | head -n 1)"
  fi

  existing_key="$(trim_key "$existing_key")"
  [[ -n "$existing_key" ]] || return 1
  printf '%s' "$existing_key"
}

read_api_key() {
  API_KEY="$(trim_key "$API_KEY")"
  if [[ -n "$API_KEY" ]]; then
    return 0
  fi

  if API_KEY="$(read_existing_api_key)"; then
    return 0
  fi

  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    die 'API-ключ не найден. Передай NEUROGATE_API_KEY=sk-... или запусти без --non-interactive'
  fi

  printf 'Вставь NeuroGate API key (ввод скрыт): '
  IFS= read -rs API_KEY
  printf '\n'
  API_KEY="$(trim_key "$API_KEY")"

  [[ -n "$API_KEY" ]] || die 'API-ключ не найден'
}

backup_file() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  local stamp backup
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="$path.bak-$stamp"
  cp "$path" "$backup"
  chmod 600 "$backup" 2>/dev/null || true
  log "Бэкап: $backup"
}

write_if_changed() {
  local target="$1"
  local tmp="$2"
  local mode="$3"

  if [[ -f "$target" ]] && cmp -s "$target" "$tmp"; then
    rm -f "$tmp"
    chmod "$mode" "$target"
    return 0
  fi

  backup_file "$target"
  mv "$tmp" "$target"
  chmod "$mode" "$target"
}

build_config_body() {
  local escaped_model escaped_provider escaped_url escaped_effort
  escaped_model="$(toml_escape "$MODEL")"
  escaped_provider="$(toml_escape "$PROVIDER_NAME")"
  escaped_url="$(toml_escape "$BASE_URL")"
  escaped_effort="$(toml_escape "$DEFAULT_REASONING_EFFORT")"

  printf 'model = "%s"\n' "$escaped_model"
  printf 'model_provider = "%s"\n' "$escaped_provider"
  printf 'model_reasoning_effort = "%s"\n' "$escaped_effort"
  printf '\n'

  if [[ -f "$CONFIG_FILE" ]]; then
    awk -v provider="$PROVIDER_NAME" '
      BEGIN {
        in_root = 1
        skip_provider = 0
        provider_header = "[model_providers.\"" provider "\"]"
      }
      /^[[:space:]]*\[/ {
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        in_root = 0
        if (line == provider_header) {
          skip_provider = 1
          next
        }
        skip_provider = 0
      }
      skip_provider { next }
      in_root && /^[[:space:]]*model[[:space:]]*=/ { next }
      in_root && /^[[:space:]]*model_provider[[:space:]]*=/ { next }
      in_root && /^[[:space:]]*model_reasoning_effort[[:space:]]*=/ { next }
      { print }
    ' "$CONFIG_FILE"
    printf '\n'
  fi

  printf '\n[model_providers."%s"]\n' "$escaped_provider"
  printf 'name = "%s"\n' "$escaped_provider"
  printf 'base_url = "%s"\n' "$escaped_url"
  printf 'wire_api = "responses"\n'
}

write_config() {
  mkdir -p "$CODEX_DIR"
  chmod 700 "$CODEX_DIR"

  local tmp
  tmp="$(mktemp "$CODEX_DIR/config.toml.tmp.XXXXXX")"
  build_config_body > "$tmp"
  write_if_changed "$CONFIG_FILE" "$tmp" 600
}

write_auth() {
  mkdir -p "$CODEX_DIR"
  chmod 700 "$CODEX_DIR"

  local tmp escaped_key
  tmp="$(mktemp "$CODEX_DIR/auth.json.tmp.XXXXXX")"
  escaped_key="$(json_escape "$API_KEY")"
  cat > "$tmp" <<JSON
{
  "auth_mode": "apikey",
  "OPENAI_API_KEY": "$escaped_key"
}
JSON
  write_if_changed "$AUTH_FILE" "$tmp" 600
}

extract_models() {
  local json="$1"

  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for item in payload.get("data", []):
    model_id = item.get("id")
    if model_id:
        print(model_id)
' <<< "$json"
    return 0
  fi

  if command -v node >/dev/null 2>&1; then
    node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  try {
    const payload = JSON.parse(input);
    for (const item of payload.data || []) {
      if (item && item.id) console.log(item.id);
    }
  } catch (_) {}
});
' <<< "$json"
    return 0
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -r '.data[]?.id // empty' <<< "$json"
    return 0
  fi

  sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$json"
}

check_models() {
  local response models
  if ! response="$(curl -fsS --connect-timeout 20 --max-time 60 \
    "$BASE_URL/models" \
    -H "Authorization: Bearer $API_KEY")"; then
    die 'не удалось проверить /v1/models. Проверь ключ, интернет и доступность NeuroGate API'
  fi

  models="$(extract_models "$response" | awk 'NF && !seen[$0]++')"
  [[ -n "$models" ]] || die 'API ответил, но список моделей не удалось прочитать'

  printf '%s\n' "$models"
}

main() {
  if ! is_termux; then
    warn 'это не похоже на Termux. Скрипт продолжит работу, потому что формат Codex-конфига такой же'
  fi

  maybe_install_curl
  read_api_key

  log "Папка Codex: $CODEX_DIR"
  write_config
  write_auth

  log 'Проверяю NeuroGate API через /v1/models...'
  local models
  models="$(check_models)"

  log ''
  log 'API готов'
  log 'Доступные модели:'
  while IFS= read -r model_id; do
    [[ -n "$model_id" ]] && printf ' - %s\n' "$model_id"
  done <<< "$models"

  if command -v codex >/dev/null 2>&1; then
    log ''
    log "Codex CLI найден: $(codex --version 2>/dev/null || printf 'version unavailable')"
    log 'Теперь можно запускать: codex'
  else
    log ''
    warn 'codex CLI не найден в PATH. Конфиг готов, но сам Codex нужно установить отдельно'
  fi
}

main "$@"
