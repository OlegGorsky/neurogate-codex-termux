param(
    [switch]$NonInteractive,
    [string]$Model = "gpt-5.5",
    [switch]$SkipApiCheck,
    [switch]$NoImageHelper,
    [switch]$NoWsl,
    [string]$WslDistro,
    [string]$ImageHelperPath
)

$ErrorActionPreference = "Stop"

$ProviderName = "NeuroGate API"
$BaseUrl = "https://api.neurogate.space/v1"
$DefaultReasoningEffort = "medium"
$ImageHelperUrl = if ($env:NEUROGATE_IMAGE_HELPER_URL) {
    $env:NEUROGATE_IMAGE_HELPER_URL
} else {
    "https://raw.githubusercontent.com/OlegGorsky/neurogate-codex-termux/main/scripts/responses_image.py"
}

$CodexDir = if ($env:CODEX_HOME) {
    $env:CODEX_HOME
} else {
    Join-Path $HOME ".codex"
}
$ConfigFile = Join-Path $CodexDir "config.toml"
$AuthFile = Join-Path $CodexDir "auth.json"
if (-not $ImageHelperPath) {
    $ImageHelperPath = Join-Path (Join-Path $HOME ".local\bin") "responses-image.py"
}

function Log([string]$Message) {
    Write-Host $Message
}

function Warn([string]$Message) {
    Write-Warning $Message
}

function Die([string]$Message) {
    Write-Error $Message
    exit 1
}

function JsonEscape([string]$Value) {
    return $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", "").Replace("`n", "")
}

function TomlEscape([string]$Value) {
    return JsonEscape $Value
}

function Write-TextNoBom([string]$Path, [string]$Text) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function To-Base64([string]$Text) {
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function Read-ExistingApiKey {
    if (-not (Test-Path -LiteralPath $AuthFile)) {
        return $null
    }

    try {
        $payload = Get-Content -LiteralPath $AuthFile -Raw | ConvertFrom-Json
    } catch {
        return $null
    }

    foreach ($name in @("OPENAI_API_KEY", "openai_api_key", "api_key")) {
        $property = $payload.PSObject.Properties[$name]
        if ($property -and $property.Value -is [string] -and $property.Value.Trim()) {
            return $property.Value.Trim()
        }
    }

    return $null
}

function Read-ApiKey {
    $apiKey = if ($env:NEUROGATE_API_KEY) { $env:NEUROGATE_API_KEY } else { $env:OPENAI_API_KEY }
    if ($apiKey -and $apiKey.Trim()) {
        return $apiKey.Trim()
    }

    $existingKey = Read-ExistingApiKey
    if ($existingKey) {
        return $existingKey
    }

    if ($NonInteractive) {
        Die "API key not found. Set NEUROGATE_API_KEY or run interactively once."
    }

    $secure = Read-Host -Prompt "Paste NeuroGate API key" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }

    if (-not $plain -or -not $plain.Trim()) {
        Die "API key not found."
    }
    return $plain.Trim()
}

function Backup-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = "$Path.bak-$stamp"
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    Log "Backup: $backup"
}

function Set-PrivateFilePermissions([string]$Path) {
    if ($IsWindows -eq $false -and $PSVersionTable.PSEdition -eq "Core") {
        return
    }

    $icacls = Get-Command icacls.exe -ErrorAction SilentlyContinue
    if (-not $icacls) {
        return
    }

    try {
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        & $icacls.Source $Path /inheritance:r /grant:r "${user}:F" | Out-Null
    } catch {
        Warn "Could not set private ACL on $Path"
    }
}

function Write-IfChanged([string]$Target, [string]$Body, [int]$Mode = 600) {
    $tmp = [System.IO.Path]::GetTempFileName()
    Write-TextNoBom $tmp $Body

    $same = $false
    if (Test-Path -LiteralPath $Target) {
        $same = ((Get-Content -LiteralPath $Target -Raw) -eq (Get-Content -LiteralPath $tmp -Raw))
    }

    if ($same) {
        Remove-Item -LiteralPath $tmp -Force
    } else {
        Backup-File $Target
        Move-Item -LiteralPath $tmp -Destination $Target -Force
    }

    if ($Target -eq $AuthFile) {
        Set-PrivateFilePermissions $Target
    }
}

function Build-ConfigBody {
    $escapedModel = TomlEscape $Model
    $escapedProvider = TomlEscape $ProviderName
    $escapedUrl = TomlEscape $BaseUrl
    $escapedEffort = TomlEscape $DefaultReasoningEffort
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add("model = `"$escapedModel`"")
    $lines.Add("model_provider = `"$escapedProvider`"")
    $lines.Add("model_reasoning_effort = `"$escapedEffort`"")
    $lines.Add("")

    if (Test-Path -LiteralPath $ConfigFile) {
        $inRoot = $true
        $skipProvider = $false
        $providerHeader = "[model_providers.`"$ProviderName`"]"

        foreach ($line in [System.IO.File]::ReadAllLines($ConfigFile)) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\[') {
                $inRoot = $false
                if ($trimmed -eq $providerHeader) {
                    $skipProvider = $true
                    continue
                }
                $skipProvider = $false
            }

            if ($skipProvider) {
                continue
            }
            if ($inRoot -and $line -match '^\s*model\s*=') {
                continue
            }
            if ($inRoot -and $line -match '^\s*model_provider\s*=') {
                continue
            }
            if ($inRoot -and $line -match '^\s*model_reasoning_effort\s*=') {
                continue
            }

            $lines.Add($line)
        }
        $lines.Add("")
    }

    $lines.Add("")
    $lines.Add("[model_providers.`"$escapedProvider`"]")
    $lines.Add("name = `"$escapedProvider`"")
    $lines.Add("base_url = `"$escapedUrl`"")
    $lines.Add('wire_api = "responses"')

    return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

function Write-Config {
    New-Item -ItemType Directory -Force -Path $CodexDir | Out-Null
    Write-IfChanged $ConfigFile (Build-ConfigBody)
}

function Write-Auth([string]$ApiKey) {
    New-Item -ItemType Directory -Force -Path $CodexDir | Out-Null
    Write-IfChanged $AuthFile (Build-AuthBody $ApiKey)
}

function Build-AuthBody([string]$ApiKey) {
    $escapedKey = JsonEscape $ApiKey
    return "{`n  `"auth_mode`": `"apikey`",`n  `"OPENAI_API_KEY`": `"$escapedKey`"`n}`n"
}

function Check-Models([string]$ApiKey) {
    try {
        $response = Invoke-RestMethod -Method Get -Uri "$BaseUrl/models" -Headers @{ Authorization = "Bearer $ApiKey" } -TimeoutSec 60
    } catch {
        Die "Failed to check /v1/models. Check the key, internet connection, and NeuroGate API availability."
    }

    $models = @()
    if ($response.data) {
        foreach ($item in $response.data) {
            if ($item.id) {
                $models += [string]$item.id
            }
        }
    }

    if (-not $models.Count) {
        Die "API responded, but no models were found."
    }

    return $models | Select-Object -Unique
}

function Install-ImageHelper {
    if ($NoImageHelper) {
        return
    }

    $helperDir = Split-Path -Parent $ImageHelperPath
    New-Item -ItemType Directory -Force -Path $helperDir | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $ImageHelperUrl -OutFile $ImageHelperPath

    $cmdPath = Join-Path $helperDir "responses-image.cmd"
    $helperName = Split-Path -Leaf $ImageHelperPath
    $cmdBody = "@echo off`r`npython `"%~dp0$helperName`" %*`r`n"
    Write-TextNoBom $cmdPath $cmdBody
    Log "Image helper: $ImageHelperPath"
    Log "Image helper wrapper: $cmdPath"
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Warn "python was not found in PATH. Install Python before using responses-image."
    }
}

function Get-WslCommand {
    return Get-Command wsl.exe -ErrorAction SilentlyContinue
}

function Get-WslBaseArgs {
    $wslArgs = @()
    if ($WslDistro) {
        $wslArgs += @("--distribution", $WslDistro)
    }
    return $wslArgs
}

function Test-WslReady {
    $wsl = Get-WslCommand
    if (-not $wsl) {
        return $false
    }

    $wslArgs = @(Get-WslBaseArgs) + @("--", "sh", "-lc", "printf ready")
    $output = & $wsl.Source @wslArgs 2>$null
    return ($LASTEXITCODE -eq 0 -and ($output -join "") -eq "ready")
}

function Install-WslConfig([string]$ApiKey) {
    if ($NoWsl) {
        Log "Skipped WSL setup"
        return
    }

    $wsl = Get-WslCommand
    if (-not $wsl) {
        Log "WSL not found, skipped WSL setup"
        return
    }

    if (-not (Test-WslReady)) {
        if ($WslDistro) {
            Warn "WSL distro '$WslDistro' is not ready, skipped WSL setup"
        } else {
            Warn "WSL is installed but no default distro is ready, skipped WSL setup"
        }
        return
    }

    $helperB64 = ""
    if (-not $NoImageHelper -and (Test-Path -LiteralPath $ImageHelperPath)) {
        $helperB64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($ImageHelperPath))
    }

    $providerB64 = To-Base64 $ProviderName
    $baseUrlB64 = To-Base64 $BaseUrl
    $modelB64 = To-Base64 $Model
    $effortB64 = To-Base64 $DefaultReasoningEffort
    $authB64 = To-Base64 (Build-AuthBody $ApiKey)

    $wslScript = @'
set -euo pipefail

decode() {
  printf '%s' "$1" | base64 -d
}

toml_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/}"
  value="${value//$'\r'/}"
  printf '%s' "$value"
}

provider="$(decode '__PROVIDER_B64__')"
base_url="$(decode '__BASE_URL_B64__')"
model="$(decode '__MODEL_B64__')"
reasoning_effort="$(decode '__EFFORT_B64__')"
auth_body_b64='__AUTH_B64__'
helper_body_b64='__HELPER_B64__'

codex_dir="$HOME/.codex"
config_file="$codex_dir/config.toml"
auth_file="$codex_dir/auth.json"
mkdir -p "$codex_dir"
chmod 700 "$codex_dir"

backup_file() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  local stamp backup
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="$path.bak-$stamp"
  cp "$path" "$backup"
  chmod 600 "$backup" 2>/dev/null || true
}

write_if_changed() {
  local target="$1"
  local body_b64="$2"
  local tmp
  tmp="$(mktemp "$codex_dir/$(basename "$target").tmp.XXXXXX")"
  printf '%s' "$body_b64" | base64 -d > "$tmp"
  if [[ -f "$target" ]] && cmp -s "$target" "$tmp"; then
    rm -f "$tmp"
  else
    backup_file "$target"
    mv "$tmp" "$target"
  fi
  chmod 600 "$target"
}

build_config_body() {
  local escaped_model escaped_provider escaped_url escaped_effort
  escaped_model="$(toml_escape "$model")"
  escaped_provider="$(toml_escape "$provider")"
  escaped_url="$(toml_escape "$base_url")"
  escaped_effort="$(toml_escape "$reasoning_effort")"

  printf 'model = "%s"\n' "$escaped_model"
  printf 'model_provider = "%s"\n' "$escaped_provider"
  printf 'model_reasoning_effort = "%s"\n' "$escaped_effort"
  printf '\n'

  if [[ -f "$config_file" ]]; then
    awk -v provider="$provider" '
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
    ' "$config_file"
    printf '\n'
  fi

  printf '\n[model_providers."%s"]\n' "$escaped_provider"
  printf 'name = "%s"\n' "$escaped_provider"
  printf 'base_url = "%s"\n' "$escaped_url"
  printf 'wire_api = "responses"\n'
}

config_b64="$(build_config_body | base64 | tr -d '\n')"
write_if_changed "$config_file" "$config_b64"
write_if_changed "$auth_file" "$auth_body_b64"

if [[ -n "$helper_body_b64" ]]; then
  mkdir -p "$HOME/.local/bin"
  printf '%s' "$helper_body_b64" | base64 -d > "$HOME/.local/bin/responses-image"
  chmod +x "$HOME/.local/bin/responses-image"
fi

printf '%s\n' "$HOME/.codex"
'@

    $wslScript = $wslScript.Replace('__PROVIDER_B64__', $providerB64)
    $wslScript = $wslScript.Replace('__BASE_URL_B64__', $baseUrlB64)
    $wslScript = $wslScript.Replace('__MODEL_B64__', $modelB64)
    $wslScript = $wslScript.Replace('__EFFORT_B64__', $effortB64)
    $wslScript = $wslScript.Replace('__AUTH_B64__', $authB64)
    $wslScript = $wslScript.Replace('__HELPER_B64__', $helperB64)

    $wslArgs = @(Get-WslBaseArgs) + @("--", "bash", "-s")
    $output = $wslScript | & $wsl.Source @wslArgs 2>&1
    if ($LASTEXITCODE -eq 0) {
        $target = ($output | Select-Object -Last 1)
        if ($WslDistro) {
            Log "WSL Codex config dir ($WslDistro): $target"
        } else {
            Log "WSL Codex config dir: $target"
        }
        if ($helperB64) {
            Log "WSL image helper: ~/.local/bin/responses-image"
        }
    } else {
        Warn "WSL setup failed: $($output -join ' ')"
    }
}

$apiKey = Read-ApiKey

Log "Codex Desktop config dir: $CodexDir"
Write-Config
Write-Auth $apiKey
Install-ImageHelper
Install-WslConfig $apiKey

if ($SkipApiCheck) {
    Log "Skipped /v1/models check"
} else {
    Log "Checking NeuroGate API through /v1/models..."
    $models = Check-Models $apiKey
    Log ""
    Log "API ready"
    Log "Available models:"
    foreach ($item in $models) {
        Log " - $item"
    }
}

Log ""
Log "Restart Codex Desktop to make sure it reloads the provider config."
Log "Image generation helper example: python `"$ImageHelperPath`" --list-presets"
