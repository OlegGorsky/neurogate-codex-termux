$ErrorActionPreference = "Stop"

$setupUrl = if ($env:NEUROGATE_CODEX_DESKTOP_SETUP_URL) {
    $env:NEUROGATE_CODEX_DESKTOP_SETUP_URL
} else {
    "https://raw.githubusercontent.com/OlegGorsky/neurogate-codex-termux/main/setup-neurogate-codex-desktop.ps1"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("neurogate-codex-desktop-" + [System.Guid]::NewGuid().ToString("N") + ".ps1")

try {
    Invoke-WebRequest -UseBasicParsing -Uri $setupUrl -OutFile $tmp
    & $tmp @args
} finally {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
}
