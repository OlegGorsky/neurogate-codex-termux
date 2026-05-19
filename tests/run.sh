#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/setup-neurogate-codex-termux.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf 'ok - %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_file() {
  local path="$1"
  local label="$2"
  if [[ -f "$path" ]]; then
    pass "$label"
  else
    fail "$label"
  fi
}

assert_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "$needle" "$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

assert_not_contains_text() {
  local text="$1"
  local needle="$2"
  local label="$3"
  if [[ "$text" == *"$needle"* ]]; then
    fail "$label"
  else
    pass "$label"
  fi
}

assert_count() {
  local path="$1"
  local needle="$2"
  local expected="$3"
  local label="$4"
  local actual
  actual="$(grep -F "$needle" "$path" | wc -l | tr -d ' ')"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    printf 'expected %s occurrences, got %s\n' "$expected" "$actual" >&2
    fail "$label"
  fi
}

make_fake_curl() {
  local bin_dir="$1"
  cat > "$bin_dir/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
cat <<'JSON'
{
  "object": "list",
  "data": [
    { "id": "gpt-5.5" },
    { "id": "gpt-5" },
    { "id": "gpt-4.1" }
  ]
}
JSON
FAKE_CURL
  chmod +x "$bin_dir/curl"
}

run_setup() {
  local home_dir="$1"
  local bin_dir="$2"
  NEUROGATE_API_KEY='sk-test-secret' \
    HOME="$home_dir" \
    PATH="$bin_dir:$PATH" \
    bash "$SCRIPT" --non-interactive 2>&1
}

test_creates_files_and_reports_models() {
  local tmp bin output
  tmp="$(mktemp -d)"
  bin="$tmp/bin"
  mkdir -p "$bin"
  make_fake_curl "$bin"

  if ! output="$(run_setup "$tmp/home" "$bin")"; then
    printf '%s\n' "$output" >&2
    fail 'script exits successfully with env API key'
    rm -rf "$tmp"
    return
  fi
  pass 'script exits successfully with env API key'

  assert_file "$tmp/home/.codex/config.toml" 'creates config.toml'
  assert_file "$tmp/home/.codex/auth.json" 'creates auth.json'
  assert_contains "$tmp/home/.codex/config.toml" 'model = "gpt-5.5"' 'writes default model'
  assert_contains "$tmp/home/.codex/config.toml" 'model_provider = "NeuroGate API"' 'selects NeuroGate provider'
  assert_contains "$tmp/home/.codex/config.toml" 'base_url = "https://api.107.172.62.211.sslip.io/v1"' 'writes NeuroGate base URL'
  assert_contains "$tmp/home/.codex/auth.json" '"OPENAI_API_KEY": "sk-test-secret"' 'writes API key to auth.json'
  assert_not_contains_text "$output" 'sk-test-secret' 'does not print API key'
  assert_not_contains_text "$output" 'Authorization: Bearer' 'does not print bearer header'
  assert_not_contains_text "$output" 'gho_' 'does not print unrelated tokens'

  if [[ "$output" == *'API готов'* && "$output" == *'gpt-5.5'* && "$output" == *'gpt-5'* ]]; then
    pass 'prints ready message and available models'
  else
    printf '%s\n' "$output" >&2
    fail 'prints ready message and available models'
  fi

  rm -rf "$tmp"
}

test_repairs_config_idempotently() {
  local tmp bin config output
  tmp="$(mktemp -d)"
  bin="$tmp/bin"
  config="$tmp/home/.codex/config.toml"
  mkdir -p "$bin" "$(dirname "$config")"
  make_fake_curl "$bin"

  cat > "$config" <<'TOML'
model = "old-model"
model_provider = "Old Provider"
model_reasoning_effort = "high"
approval_policy = "never"

[model_providers."NeuroGate API"]   
name = "broken"
base_url = "https://wrong.example/v1"
wire_api = "chat"

[profiles.termux]
sandbox_mode = "workspace-write"
TOML

  if ! output="$(run_setup "$tmp/home" "$bin")"; then
    printf '%s\n' "$output" >&2
    fail 'script repairs existing config'
    rm -rf "$tmp"
    return
  fi
  pass 'script repairs existing config'

  if ! output="$(run_setup "$tmp/home" "$bin")"; then
    printf '%s\n' "$output" >&2
    fail 'script is idempotent on second run'
    rm -rf "$tmp"
    return
  fi
  pass 'script is idempotent on second run'

  assert_contains "$config" 'approval_policy = "never"' 'preserves unrelated root settings'
  assert_contains "$config" '[profiles.termux]' 'preserves unrelated tables'
  assert_contains "$config" 'sandbox_mode = "workspace-write"' 'preserves unrelated table content'
  assert_count "$config" 'model = "gpt-5.5"' '1' 'keeps one model key'
  assert_count "$config" 'model_provider = "NeuroGate API"' '1' 'keeps one provider key'
  assert_count "$config" '[model_providers."NeuroGate API"]' '1' 'keeps one NeuroGate provider table'
  assert_count "$config" 'base_url = "https://api.107.172.62.211.sslip.io/v1"' '1' 'keeps one correct base URL'

  rm -rf "$tmp"
}

test_requires_key_when_non_interactive() {
  local tmp bin output status
  tmp="$(mktemp -d)"
  bin="$tmp/bin"
  mkdir -p "$bin"
  make_fake_curl "$bin"

  set +e
  output="$(HOME="$tmp/home" PATH="$bin:$PATH" bash "$SCRIPT" --non-interactive 2>&1)"
  status="$?"
  set -e

  if [[ "$status" != '0' ]]; then
    pass 'non-interactive mode fails without API key'
  else
    fail 'non-interactive mode fails without API key'
  fi

  if [[ "$output" == *'API-ключ не найден'* ]]; then
    pass 'explains missing API key'
  else
    printf '%s\n' "$output" >&2
    fail 'explains missing API key'
  fi

  rm -rf "$tmp"
}

test_creates_files_and_reports_models
test_repairs_config_idempotently
test_requires_key_when_non_interactive

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT" >&2
  exit 1
fi

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
