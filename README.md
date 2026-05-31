# NeuroGate Codex Termux Setup

Скрипт настраивает Codex CLI в Termux для работы через NeuroGate API.

Он создаёт или чинит:

- `~/.codex/config.toml`
- `~/.codex/auth.json`

После записи файлов скрипт проверяет ключ через `GET /v1/models` и показывает доступные модели.

## Быстрый запуск

```bash
pkg install -y curl bash && bash -c "$(curl -fsSL https://raw.githubusercontent.com/OlegGorsky/ng/main/i)"
```

Скрипт попросит NeuroGate API key. Ввод скрыт, ключ в терминал не печатается.

Если `curl` уже установлен:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/OlegGorsky/ng/main/i)"
```

`OlegGorsky/ng` — короткий GitHub-алиас. Он скачивает основной скрипт из этого репозитория и запускает его.

## Обновление

Если Codex уже настроен и `~/.codex/auth.json` существует, ключ заново вводить не нужно:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/OlegGorsky/ng/main/i)" -- --non-interactive
```

Если проект склонирован локально:

```bash
git pull --ff-only
bash setup-neurogate-codex-termux.sh --non-interactive
```

## Что будет записано

`~/.codex/config.toml`:

```toml
model = "gpt-5.5"
model_provider = "NeuroGate API"
model_reasoning_effort = "medium"

[model_providers."NeuroGate API"]
name = "NeuroGate API"
base_url = "https://api.neurogate.space/v1"
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

Если `~/.codex/auth.json` уже есть, можно запустить без переменных окружения:

```bash
bash setup-neurogate-codex-termux.sh --non-interactive
```

Для первичной настройки без ввода с клавиатуры передай ключ через переменную окружения:

```bash
NEUROGATE_API_KEY='sk-...' bash setup-neurogate-codex-termux.sh --non-interactive
```

Можно выбрать другую модель для Codex:

```bash
NEUROGATE_API_KEY='sk-...' bash setup-neurogate-codex-termux.sh --non-interactive --model gpt-5
```

## Генерация изображений

В репозитории есть helper для `/responses` + `image_generation`:

```bash
python3 scripts/responses_image.py generate "cinematic photo of a compact AI workstation" --size wide --quality high
```

Подробности и команда установки helper в Termux: [docs/responses-image-generation.md](docs/responses-image-generation.md).

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
