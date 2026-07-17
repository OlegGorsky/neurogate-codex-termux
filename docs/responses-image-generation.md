# Генерация изображений через NeuroGate Responses API

В репозитории есть helper-скрипт [scripts/responses_image.py](../scripts/responses_image.py). Он работает без OpenAI SDK: читает ключ из `OPENAI_API_KEY` или `~/.codex/auth.json`, а URL и модель берёт из `OPENAI_BASE_URL`/`OPENAI_MODEL` или из активного провайдера в `~/.codex/config.toml`.

Нужен Python 3.10 или новее. Для автоматического чтения `~/.codex/config.toml` нужен Python 3.11+; на Python 3.10 задай URL явно, например `OPENAI_BASE_URL=https://api.neurogate.space/v1 python3 scripts/responses_image.py --list-presets`.

После запуска Termux или Desktop установщика скрипт автоматически использует:

```toml
model_provider = "NeuroGate API"

[model_providers."NeuroGate API"]
base_url = "https://api.neurogate.space/v1"
wire_api = "responses"
```

Если ошибка Codex содержит `https://api.vibemod.pro/v1/responses`, запрос выполняет старый provider, а не этот helper через NeuroGate. Повторно запусти Termux-установщик, проверь напечатанный `API base URL`, полностью перезапусти Codex и при доступной команде выполни `codex doctor`: эффективный provider должен быть `NeuroGate API`.

## Установка helper-команды

В Termux:

```bash
pkg install -y python
```

В Ubuntu/Linux:

```bash
sudo apt update && sudo apt install -y python3 curl
```

В macOS:

```bash
brew install python
```

В Windows нужен Python в `PATH`.

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

Windows desktop setup ставит helper сюда:

```powershell
python "$env:USERPROFILE\.local\bin\responses-image.py" --list-presets
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
