param(
    [switch]$NonInteractive,
    [string]$Model = "gpt-5.5",
    [switch]$SkipApiCheck,
    [switch]$NoImageHelper,
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
    $escapedKey = JsonEscape $ApiKey
    $body = "{`n  `"auth_mode`": `"apikey`",`n  `"OPENAI_API_KEY`": `"$escapedKey`"`n}`n"
    Write-IfChanged $AuthFile $body
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

$apiKey = Read-ApiKey

Log "Codex Desktop config dir: $CodexDir"
Write-Config
Write-Auth $apiKey
Install-ImageHelper

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
