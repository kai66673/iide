# Рекомендации по проекту iide

## P0 — Нужно исправить сейчас

### 1. ~~`DocumentManager.documents` пересоздаёт HashMap на каждом обращении~~ ✅ Исправлено

Переиспользование одного `HashMap` вместо аллокации нового на каждом вызове. Геттер всегда пересобирает содержимое из текущего состояния grid, но `_documents.clear()` + повторное заполнение дешевле `new HashMap`. Кэширование невозможно — Panel не предоставляет надёжных сигналов об изменении набора вкладок.

### 2. Утечки сигналов: нет `disconnect` в деструкторах

- `SourceView` (строки 184-251) — подключает 6+ сигналов, нигде не отключает.
- `SourceDocument` (строки 21-36) — подключает `buffer.insert_text` и `buffer.delete_range`, нет отключения.
- `BaseTreeSitterHighlighter` — нет отключения `buffer.changed` и `buffer.notify["style-scheme"]` в деструкторе.

При пересоздании объектов (закрытие/открытие вкладки) старые обработчики могут сработать.

**Решение:** Добавить `disconnect_signals()` в деструкторы всех трёх классов.

---

## P1 — Важно для стабильности

### 3. Дублирование кода: `RpcProcess` vs `TcpProcess`

`src/Services/JsonRpc/RpcProcess.vala` и `src/Services/JsonRpc/TcpProcess.vala` — ~80% идентичного кода: очередь записи, парсинг `Content-Length`, барьер завершения. Единственное отличие — канал I/O (subprocess vs socket).

**Решение:** Вынести общую логику в `BaseRpcTransport`, оставив подклассам только `init_channel()`.

### 4. Дублирование: `LspClient` и `DapClient`

Оба класса реализуют одинаковый паттерн `Promise + pending_requests HashMap + cancellable`. `LspClient` — 1200+ строк, `DapClient` — почти идентичная структура запросов.

**Решение:** Общий базовый класс `RpcClient` с транспортом, промисами и диспетчеризацией ответов.

### 5. Toggle-действия не синхронизируются с диалогом настроек

4 одинаковых TODO в `src/application.vala:287, 586, 616, 646` — переключатели minimap/номеров строк/диагностики/folding не обновляются при изменении настроек из Preferences.

**Решение:** Подключить сигнал `SettingsService` к каждому toggle-action, обновлять `state` при изменении.

---

## P2 — Качество кода

### 6. God-класс: `BaseTreeSitterHighlighter` (925 строк)

`src/Services/TreeSitter/BaseTreeSitterHighlighter.vala` — парсинг, рендеринг, фолдинг, селекция, хлебные крошки, скобочные пары, оглавление. Auto-pairing живёт здесь, а не в `SourceView`.

**Решение:** Разделить на `TreeSitterParser`, `TreeSitterRenderer`, `TreeSitterFolding`. Auto-pairing перенести в `SourceView` или отдельный `InputHandler`.

### 7. God-класс: `LspClient` (1200+ строк)

`src/Services/LSP/LspClient.vala` — жизненный цикл процесса, JSON-RPC фрейминг, парсинг capabilities, diagnostics, completion, hover, definition, formatting, code actions, pull diagnostics.

**Решение:** Разбить на транспорт + протокол + фичи-модули.

### 8. Hardcoded параметры форматирования

`src/Services/LSP/LspDocumentClient.vala:214-215` — `tab_width = 4`, `use_spaces = true` захардкожены вместо чтения из `SettingsService` или конфига языка.

**Решение:** Добавить чтение из `SettingsService` с fallback на значение по умолчанию.

### 9. `LspDocumentClient` — нет дедупликации syncer'ов

`src/Services/LSP/LspDocumentClient.vala:33-37` — `register_lsp_clients()` создаёт новые `LspClientSyncer` без проверки на дубли. Повторный вызов = дублирование syncer'ов.

**Решение:** Проверять наличие существующего syncer перед созданием нового.

---

## P3 — Чистота кода

### 10. Остаточный debug-логging в продакшене

- `application.vala:512` — `message ("MIME: _ " + mime_type);`
- `LspClient.vala:436` — `message ("!!!handle_incoming_notification ...")`
- `SourceView.vala:512` — `message ("MIME: _ " + mime_type);`

**Решение:** Заменить на `LoggerService` или удалить.
