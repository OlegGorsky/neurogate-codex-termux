$ErrorActionPreference = "Stop"

$setupUrl = if ($env:NEUROGATE_CODEX_DESKTOP_SETUP_URL) {
    $env:NEUROGATE_CODEX_DESKTOP_SETUP_URL
} else {
    "https://raw.githubusercontent.com/OlegGorsky/neurogate-codex-termux/main/setup-neurogate-codex-desktop.ps1"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("neurogate-codex-desktop-" + [System.Guid]::NewGuid().ToString("N") + ".ps1")

try {
    Invoke-WebRequest -UseBasicParsing -Uri $setupUrl -OutFile $tmp
    try {
        Unblock-File -Path $tmp -ErrorAction SilentlyContinue
    } catch {
    }

    $powershell = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    & $powershell -NoProfile -ExecutionPolicy Bypass -File $tmp @args
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    if ($exitCode -ne 0) {
        throw "Setup failed with exit code $exitCode."
    }
} finally {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
}
