# NeuroGate Codex Termux Setup

Скрипт настраивает Codex CLI в Termux для работы через NeuroGate API.

Он создаёт или чинит:

- `~/.codex/config.toml`
- `~/.codex/auth.json`

После записи файлов скрипт проверяет ключ через `GET /v1/models` и показывает доступные модели.

## Быстрый запуск

```bash
pkg install -y curl bash
curl -fsSL https://raw.githubusercontent.com/OlegGorsky/neurogate-codex-termux/main/setup-neurogate-codex-termux.sh -o setup-neurogate-codex-termux.sh
bash setup-neurogate-codex-termux.sh
```

Скрипт попросит NeuroGate API key. Ввод скрыт, ключ в терминал не печатается.

## Что будет записано

`~/.codex/config.toml`:

```toml
model = "gpt-5.5"
model_provider = "NeuroGate API"
model_reasoning_effort = "medium"

[model_providers."NeuroGate API"]
name = "NeuroGate API"
base_url = "https://api.107.172.62.211.sslip.io/v1"
wire_api = "responses"
```

`~/.codex/auth.json`:

```json
{
  "auth_mode": "apikey",
  "OPENAI_API_KEY": "..."
}
```

## Без интерактива

```bash
NEUROGATE_API_KEY='sk-...' bash setup-neurogate-codex-termux.sh --non-interactive
```

Можно выбрать другую модель для Codex:

```bash
NEUROGATE_API_KEY='sk-...' bash setup-neurogate-codex-termux.sh --non-interactive --model gpt-5
```

## Безопасность

- API-ключ не выводится в терминал.
- `auth.json` создаётся с правами `600`.
- Перед изменением существующих файлов создаются `.bak-YYYYmmdd-HHMMSS` бэкапы.
- Существующие настройки в `config.toml` сохраняются, а блок NeuroGate приводится к правильному виду.

## Проверка

Локальные тесты:

```bash
bash tests/run.sh
```
