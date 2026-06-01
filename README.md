# NeuroGate Codex Setup

Один репозиторий для двух сценариев:

- Codex Desktop на Ubuntu/Linux, macOS и Windows.
- Codex CLI в Termux.

Скрипты прописывают NeuroGate API в Codex config, сохраняют ключ в `auth.json`, проверяют `/v1/models` и не печатают API-ключ в терминал.

## Что выбрать

Для Codex Desktop на Ubuntu/Linux или macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/OlegGorsky/ng/main/d | bash
```

Для Codex Desktop на Windows открой PowerShell:

```powershell
irm https://raw.githubusercontent.com/OlegGorsky/ng/main/d.ps1 | iex
```

Если на Windows уже установлен и инициализирован WSL, эта же команда дополнительно пропишет NeuroGate в default WSL-дистрибутив.

Для Codex CLI в Termux:

```bash
pkg install -y curl bash && curl -fsSL https://raw.githubusercontent.com/OlegGorsky/ng/main/i | bash
```

Если `curl` в Termux уже установлен:

```bash
curl -fsSL https://raw.githubusercontent.com/OlegGorsky/ng/main/i | bash
```

## Что будет по шагам

1. Скрипт найдёт Codex config directory.
2. Если ключа ещё нет, попросит вставить NeuroGate API key скрытым вводом.
3. Если `auth.json` уже есть, ключ повторно вводить не нужно.
4. Скрипт обновит `config.toml` на NeuroGate provider.
5. Скрипт проверит ключ через `GET https://api.neurogate.space/v1/models`.
6. Для Codex Desktop дополнительно поставит helper для генерации картинок.
7. Windows-скрипт проверит WSL и, если default distro готов, запишет туда тот же `config.toml`, `auth.json` и image helper.
8. После Desktop-настройки перезапусти Codex Desktop.

Короткие `curl ... | bash` команды тоже умеют спрашивать ключ: bash-скрипты читают ввод с терминала, а не из pipe.

## Что записывается

`config.toml`:

```toml
model = "gpt-5.5"
model_provider = "NeuroGate API"
model_reasoning_effort = "medium"

[model_providers."NeuroGate API"]
name = "NeuroGate API"
base_url = "https://api.neurogate.space/v1"
wire_api = "responses"
```

`auth.json`:

```json
{
  "auth_mode": "apikey",
  "OPENAI_API_KEY": "..."
}
```

Пути:

- Ubuntu/Linux/macOS/Termux: `~/.codex/config.toml` и `~/.codex/auth.json`
- Windows: `%USERPROFILE%\.codex\config.toml` и `%USERPROFILE%\.codex\auth.json`
- WSL при запуске Windows-скрипта: `~/.codex/config.toml` и `~/.codex/auth.json` внутри default WSL-дистрибутива

Перед изменением существующих файлов создаются `.bak-YYYYmmdd-HHMMSS` бэкапы.

## Обновление

Запусти ту же команду, что и при установке. Если ключ уже сохранён, скрипт не спросит его заново.

Desktop Ubuntu/Linux/macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/OlegGorsky/ng/main/d | bash
```

Desktop Windows:

```powershell
irm https://raw.githubusercontent.com/OlegGorsky/ng/main/d.ps1 | iex
```

Termux:

```bash
curl -fsSL https://raw.githubusercontent.com/OlegGorsky/ng/main/i | bash
```

## Генерация изображений

Desktop-setup ставит helper для `/responses` + `image_generation`.

Ubuntu/Linux/macOS:

```bash
~/.local/bin/responses-image --list-presets
~/.local/bin/responses-image generate "cinematic photo of a compact AI workstation" --size wide --quality high
```

Windows:

```powershell
python "$env:USERPROFILE\.local\bin\responses-image.py" --list-presets
python "$env:USERPROFILE\.local\bin\responses-image.py" generate "cinematic photo of a compact AI workstation" --size wide --quality high
```

WSL после Windows-установки:

```bash
~/.local/bin/responses-image --list-presets
~/.local/bin/responses-image generate "cinematic photo of a compact AI workstation" --size wide --quality high
```

Termux или локальный запуск из репозитория:

```bash
python3 scripts/responses_image.py generate "cinematic photo of a compact AI workstation" --size wide --quality high
```

Helper читает ключ из Codex `auth.json`, а `base_url` и модель из активного `model_provider`, поэтому картинки идут через NeuroGate после настройки.

Подробности: [docs/responses-image-generation.md](docs/responses-image-generation.md).

## Локальный запуск из клона

Desktop Ubuntu/Linux/macOS:

```bash
bash setup-neurogate-codex-desktop.sh
```

Desktop Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-neurogate-codex-desktop.ps1
powershell -ExecutionPolicy Bypass -File .\setup-neurogate-codex-desktop.ps1 -WslDistro Ubuntu
powershell -ExecutionPolicy Bypass -File .\setup-neurogate-codex-desktop.ps1 -NoWsl
```

Termux:

```bash
bash setup-neurogate-codex-termux.sh
```

Без интерактива с переменной окружения:

```bash
NEUROGATE_API_KEY='...' bash setup-neurogate-codex-desktop.sh --non-interactive
NEUROGATE_API_KEY='...' bash setup-neurogate-codex-termux.sh --non-interactive
```

Выбрать другую модель:

```bash
NEUROGATE_API_KEY='...' bash setup-neurogate-codex-desktop.sh --non-interactive --model gpt-5
NEUROGATE_API_KEY='...' bash setup-neurogate-codex-termux.sh --non-interactive --model gpt-5
```

Документация по Desktop: [docs/codex-desktop.md](docs/codex-desktop.md).

## Проверка

Локальные тесты:

```bash
bash tests/run.sh
```
