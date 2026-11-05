# TextCorrect

Нативное macOS-приложение (menu bar utility) для быстрого доступа к AI из любого приложения:
LLM-чат, пользовательские сценарии обработки текста, скриншоты, локальный голосовой ввод (Whisper)
и Push-to-Talk. macOS 14+, Apple Silicon, Swift + SwiftUI + AppKit.

## Статус

Этап 1 (фундамент) в разработке. Реализованы модели, хранение, LLM-клиент, menu bar, главное окно
и разрешения. Полный план — [`docs/PLAN.md`](docs/PLAN.md), архитектура — [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Сборка

```bash
# Один раз после установки Xcode (требует пароля администратора):
sudo xcodebuild -license accept

# Собрать и запустить через SwiftPM:
swift run TextCorrect

# Или собрать .app:
Scripts/build_app.sh
```

## Разрешения

Приложение запрашивает по мере необходимости:
- **Accessibility** — чтение и замена выделенного текста.
- **Microphone** — голосовой ввод.
- **Screen Recording** — скриншоты.

## Лицензия

MIT. Сторонние компоненты и веса моделей — по их собственным лицензиям.
