# NeuroGate для Codex Desktop

Этот контур настраивает Codex Desktop на Windows, macOS и Ubuntu/Linux через тот же конфиг, который использует локальный Codex:

- `~/.codex/config.toml` на macOS/Linux
- `%USERPROFILE%\.codex\config.toml` на Windows
- `auth.json` рядом с `config.toml`

Если `auth.json` уже есть, ключ повторно вводить не нужно. Скрипт обновит provider и переиспользует существующий ключ.

## Ubuntu/Linux

```bash
curl -fsSL https://raw.githubusercontent.com/OlegGorsky/ng/main/d | bash
```

Если `curl` не установлен:

```bash
sudo apt update && sudo apt install -y curl python3
curl -fsSL https://raw.githubusercontent.com/OlegGorsky/ng/main/d | bash
```

## macOS

```bash
curl -fsSL https://raw.githubusercontent.com/OlegGorsky/ng/main/d | bash
```

Если Python не установлен, поставь его через Homebrew:

```bash
brew install python
```

## Windows

Открой PowerShell:

```powershell
irm https://raw.githubusercontent.com/OlegGorsky/ng/main/d.ps1 | iex
```

Для работы helper-команды генерации изображений нужен Python в `PATH`.

## Что меняется

В `config.toml` выставляется NeuroGate provider:

```toml
model = "gpt-5.5"
model_provider = "NeuroGate API"
model_reasoning_effort = "medium"

[model_providers."NeuroGate API"]
name = "NeuroGate API"
base_url = "https://api.neurogate.space/v1"
wire_api = "responses"
```

В `auth.json` записывается или сохраняется:

```json
{
  "auth_mode": "apikey",
  "OPENAI_API_KEY": "..."
}
```

После обновления перезапусти Codex Desktop, чтобы приложение перечитало provider config.

## Картинки

Linux/macOS setup скачивает helper в:

```bash
~/.local/bin/responses-image
```

Windows setup скачивает helper в:

```powershell
%USERPROFILE%\.local\bin\responses-image.py
```

Рядом создаётся wrapper:

```powershell
%USERPROFILE%\.local\bin\responses-image.cmd
```

Проверка:

```bash
~/.local/bin/responses-image --list-presets
```

Windows:

```powershell
python "$env:USERPROFILE\.local\bin\responses-image.py" --list-presets
```

Пример генерации:

```bash
~/.local/bin/responses-image generate "cinematic photo of a compact AI workstation" --size wide --quality high
```

Helper читает `OPENAI_API_KEY` из Codex `auth.json`, а `base_url` и модель из активного `model_provider`, поэтому после desktop setup картинки идут через NeuroGate.

## Локальный запуск из клона

Linux/macOS:

```bash
bash setup-neurogate-codex-desktop.sh
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-neurogate-codex-desktop.ps1
```

Полезные опции:

```bash
bash setup-neurogate-codex-desktop.sh --non-interactive --model gpt-5
bash setup-neurogate-codex-desktop.sh --skip-api-check
bash setup-neurogate-codex-desktop.sh --no-image-helper
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-neurogate-codex-desktop.ps1 -NonInteractive -Model gpt-5
powershell -ExecutionPolicy Bypass -File .\setup-neurogate-codex-desktop.ps1 -SkipApiCheck
powershell -ExecutionPolicy Bypass -File .\setup-neurogate-codex-desktop.ps1 -NoImageHelper
```
