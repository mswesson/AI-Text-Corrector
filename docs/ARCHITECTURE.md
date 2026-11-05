# TextCorrect v4.0 — Архитектура

## Модули (ТЗ §23, упрощённо)

```
Sources/TextCorrectCore        # библиотека без UI
  Models/      Action, Provider, Settings, KeyCombination, ChatMessage, LLMError
  Stores/      JSONStore (generic), ActionStore, ProviderStore, SettingsStore
  AppState     композиция сторов + глобальная проверка конфликтов хоткеев
  Hotkeys/     HotkeyRegistry (чистая валидация, тестируемо)
  LLM/         LLMClient (URLSession), RequestBuilder (итерации)
  Security/    KeychainService

Sources/TextCorrect            # UI-таргет (AppKit/SwiftUI)
  AppDelegate, TextCorrectApp, MenuBarController
  Hotkeys/     HotkeyManager (Carbon RegisterEventHotKey), HotkeyRecorderView
  System/      PermissionManager (Accessibility/Mic/Screen Recording)
  MainWindow/  разделы: General, Actions, AI Providers, Speech Models, Voice Input, Shortcuts
```

Границы: Core не импортирует AppKit/SwiftUI; логика (валидация, построение запросов) — чистые структуры.

## Потоки данных

- **Transform-итерации** (ТЗ §9.4): первая — `[system, user=выделение]`; следующие — `[system, user=«<text>current_draft</text> <instruction>…</instruction>»]`. Всегда актуальный черновик, никогда исходник.
- **Chat** (ТЗ §9.2): `[system] + история сессии + новый user`. История только в памяти.
- **STT** (ТЗ §16): `Audio → STT → [LLM] → Insertion`. Постобработка опциональна.
- **Вставка/замена**: всегда через Accessibility по сохранённому контексту; при несоответствии — только Copy.

## Безопасность

- API-ключи — только Keychain; в файлах настроек — ссылки.
- Без истории текстов/диктовок; аудио — временно и удаляется.
- Не читать secure-поля; облачная LLM — однократное согласие.

## Расширение под Agent (ТЗ §24)

Единый интерфейс `InteractionEngine`; в MVP реализован только `DirectLLMEngine`. Agent Runtime (Tool Calling, Permission Layer) добавляется позже без переписывания UI.
