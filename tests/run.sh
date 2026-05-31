#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/setup-neurogate-codex-termux.sh"
BOOTSTRAP="$ROOT_DIR/i"

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

make_fake_bootstrap_curl() {
  local bin_dir="$1"
  cat > "$bin_dir/curl" <<'FAKE_BOOTSTRAP_CURL'
#!/usr/bin/env bash
output_path=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output_path="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -z "$output_path" ]]; then
  printf 'missing -o\n' >&2
  exit 2
fi

cat > "$output_path" <<'DOWNLOADED_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'downloaded setup ran'
for arg in "$@"; do
  printf ' [%s]' "$arg"
done
printf '\n'
DOWNLOADED_SCRIPT
FAKE_BOOTSTRAP_CURL
  chmod +x "$bin_dir/curl"
}

run_setup() {
  local home_dir="$1"
  local bin_dir="$2"
  NEUROGATE_API_KEY='test-api-key' \
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
  assert_contains "$tmp/home/.codex/config.toml" 'base_url = "https://api.neurogate.space/v1"' 'writes NeuroGate base URL'
  assert_contains "$tmp/home/.codex/auth.json" '"OPENAI_API_KEY": "test-api-key"' 'writes API key to auth.json'
  assert_not_contains_text "$output" 'test-api-key' 'does not print API key'
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
  assert_count "$config" 'base_url = "https://api.neurogate.space/v1"' '1' 'keeps one correct base URL'

  rm -rf "$tmp"
}

test_reuses_existing_auth_key_non_interactive() {
  local tmp bin output auth
  tmp="$(mktemp -d)"
  bin="$tmp/bin"
  auth="$tmp/home/.codex/auth.json"
  mkdir -p "$bin" "$(dirname "$auth")"
  make_fake_curl "$bin"

  cat > "$auth" <<'JSON'
{
  "auth_mode": "apikey",
  "OPENAI_API_KEY": "existing-test-api-key"
}
JSON

  if ! output="$(HOME="$tmp/home" PATH="$bin:$PATH" bash "$SCRIPT" --non-interactive 2>&1)"; then
    printf '%s\n' "$output" >&2
    fail 'non-interactive mode reuses existing auth.json key'
    rm -rf "$tmp"
    return
  fi
  pass 'non-interactive mode reuses existing auth.json key'

  assert_contains "$auth" '"OPENAI_API_KEY": "existing-test-api-key"' 'keeps existing API key'
  assert_not_contains_text "$output" 'existing-test-api-key' 'does not print reused API key'

  rm -rf "$tmp"
}

test_image_helper_static_checks() {
  local output
  if ! command -v python3 >/dev/null 2>&1; then
    pass 'image helper checks skipped without python3'
    return
  fi

  if python3 -m py_compile "$ROOT_DIR/scripts/responses_image.py"; then
    pass 'image helper compiles'
  else
    fail 'image helper compiles'
  fi

  if output="$(python3 "$ROOT_DIR/scripts/responses_image.py" --list-presets 2>&1)" \
    && [[ "$output" == *$'wide\t1536x1024'* ]]; then
    pass 'image helper CLI lists presets without API key'
  else
    printf '%s\n' "$output" >&2
    fail 'image helper CLI lists presets without API key'
  fi
}

test_image_helper_reads_selected_codex_provider() {
  local tmp codex output
  if ! command -v python3 >/dev/null 2>&1; then
    pass 'image helper Codex config check skipped without python3'
    return
  fi
  if ! python3 -c 'import tomllib' >/dev/null 2>&1; then
    pass 'image helper Codex config check skipped without tomllib'
    return
  fi

  tmp="$(mktemp -d)"
  codex="$tmp/home/.codex"
  mkdir -p "$codex"
  cat > "$codex/auth.json" <<'JSON'
{
  "auth_mode": "apikey",
  "OPENAI_API_KEY": "existing-test-api-key"
}
JSON
  cat > "$codex/config.toml" <<'TOML'
model = "gpt-5.5"
model_provider = "NeuroGate API"

[model_providers."Wrong Provider"]
base_url = "https://wrong.example/v1"

[model_providers."NeuroGate API"]
base_url = "https://api.neurogate.space/v1"
wire_api = "responses"
TOML

  if output="$(CODEX_HOME="$codex" python3 - "$ROOT_DIR/scripts/responses_image.py" <<'PY' 2>&1
import importlib.util
import sys

script_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("responses_image", script_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
config = module.resolve_config()
assert config.api_key == "existing-test-api-key"
assert config.base_url == "https://api.neurogate.space/v1"
assert config.model == "gpt-5.5"
tool = module.build_tool(module.ImageJob(prompt="p", output="out.png", compression="80"))
assert tool["output_compression"] == 80
try:
    module.build_tool(module.ImageJob(prompt="p", output="out.png", compression="bad"))
except module.ImageGenerationError:
    pass
else:
    raise AssertionError("bad compression should fail")
print("config-ok")
PY
)"; then
    pass 'image helper reads selected Codex provider'
  else
    printf '%s\n' "$output" >&2
    fail 'image helper reads selected Codex provider'
  fi

  assert_not_contains_text "$output" 'existing-test-api-key' 'image helper config check does not print API key'
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

test_bootstrap_downloads_and_runs_setup() {
  local tmp bin output
  tmp="$(mktemp -d)"
  bin="$tmp/bin"
  mkdir -p "$bin"
  make_fake_bootstrap_curl "$bin"

  if ! output="$(HOME="$tmp/home" PATH="$bin:$PATH" bash "$BOOTSTRAP" --model gpt-5 2>&1)"; then
    printf '%s\n' "$output" >&2
    fail 'short bootstrap exits successfully'
    rm -rf "$tmp"
    return
  fi
  pass 'short bootstrap exits successfully'

  if [[ "$output" == 'downloaded setup ran [--model] [gpt-5]' ]]; then
    pass 'short bootstrap runs downloaded setup with arguments'
  else
    printf '%s\n' "$output" >&2
    fail 'short bootstrap runs downloaded setup with arguments'
  fi

  rm -rf "$tmp"
}

test_creates_files_and_reports_models
test_repairs_config_idempotently
test_reuses_existing_auth_key_non_interactive
test_requires_key_when_non_interactive
test_bootstrap_downloads_and_runs_setup
test_image_helper_static_checks
test_image_helper_reads_selected_codex_provider

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT" >&2
  exit 1
fi

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
