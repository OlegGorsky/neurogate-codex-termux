# Генерация изображений через NeuroGate Responses API

В репозитории есть helper-скрипт [scripts/responses_image.py](../scripts/responses_image.py). Он работает без OpenAI SDK: читает ключ из `OPENAI_API_KEY` или `~/.codex/auth.json`, а URL и модель берёт из `OPENAI_BASE_URL`/`OPENAI_MODEL` или из активного провайдера в `~/.codex/config.toml`.

После запуска основного установщика скрипт автоматически использует:

```toml
model_provider = "NeuroGate API"

[model_providers."NeuroGate API"]
base_url = "https://api.neurogate.space/v1"
wire_api = "responses"
```

## Установка helper-команды

В Termux нужен Python:

```bash
pkg install -y python
```

Можно скачать helper как отдельную команду:

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/OlegGorsky/neurogate-codex-termux/main/scripts/responses_image.py -o ~/.local/bin/responses-image
chmod +x ~/.local/bin/responses-image
```

Если `~/.local/bin` не добавлен в `PATH`, запускай так:

```bash
python3 ~/.local/bin/responses-image --list-presets
```

## Примеры

Сгенерировать изображение:

```bash
python3 scripts/responses_image.py generate "cinematic photo of a compact AI workstation" --size wide --quality high
```

Сохранить в конкретный файл:

```bash
python3 scripts/responses_image.py generate "minimal black terminal setup, realistic lighting" \
  --output output/imagegen/terminal.png \
  --size 1536x1024 \
  --quality high
```

Отредактировать изображение:

```bash
python3 scripts/responses_image.py edit "make the lighting warmer, keep composition" \
  --input input/source.png \
  --output output/imagegen/source-warm.png
```

Запустить через env-интерфейс:

```bash
IMAGE_PROMPT="clean product photo of a matte black notebook" \
IMAGE_OUTPUT="output/imagegen/notebook.png" \
IMAGE_SIZE="square" \
IMAGE_QUALITY="high" \
python3 scripts/responses_image.py
```

## Безопасность

- Скрипт не печатает API-ключ.
- HTTP-ошибки проходят через редактор, который скрывает `sk-...` и `Bearer ...`.
- В `.json`-метаданные сохраняются модель, URL, prompt и параметры генерации, но не ключ.
- Для masked edit файлы загружаются через `/files` с `purpose=vision`; обычные edit-запросы используют data URL и не требуют Files API.
