# Рекомендации по проекту iide

## P0 — Нужно исправить сейчас

### 1. ~~`DocumentManager.documents` пересоздаёт HashMap на каждом обращении~~ ✅ Исправлено

Переиспользование одного `HashMap` вместо аллокации нового на каждом вызове. Геттер всегда пересобирает содержимое из текущего состояния grid, но `_documents.clear()` + повторное заполнение дешевле `new HashMap`. Кэширование невозможно — Panel не предоставляет надёжных сигналов об изменении набора вкладок.

### 2. Утечки сигналов: нет `disconnect` в деструкторах

- `SourceView` (строки 189-251) — подключает 6+ сигналов, нигде не отключает.
- `SourceDocument` (строки 21-36) — подключает `buffer.insert_text` и `buffer.delete_range`, нет отключения.
- `BaseTreeSitterHighlighter` — нет отключения `buffer.changed` и `buffer.notify["style-scheme"]` в деструкторе.

При пересоздании объектов (закрытие/открытие вкладки) старые обработчики могут сработать.

**Решение:** Добавить `disconnect_signals()` в деструкторы всех трёх классов.

---

## P1 — Важно для стабильности

### 3. Дублирование кода: `RpcProcess` vs `TcpProcess`

`src/Services/JsonRpc/RpcProcess.vala` и `src/Services/JsonRpc/TcpProcess.vala` — ~80% идентичного кода: очередь записи, парсинг `Content-Length`, барьер завершения. Единственное отличие — канал I/O (subprocess vs socket). Общий интерфейс `RpcTransport` уже введён, но фрейминг и очередь в каждом классе продублированы (236 и 209 строк).

**Решение:** Вынести общую логику в `BaseRpcTransport` (реализующий `RpcTransport`), оставив подклассам только канал I/O — `init_channel()`.

### 4. Дублирование: `LspClient` и `DapClient`

Оба класса реализуют одинаковый паттерн `Promise + pending_requests HashMap + cancellable`. `LspClient` — 1200+ строк, `DapClient` — почти идентичная структура запросов.

**Решение:** Общий базовый класс `RpcClient` с транспортом, промисами и диспетчеризацией ответов.

### 5. Toggle-действия не синхронизируются с диалогом настроек

4 одинаковых TODO в `src/application.vala:288, 587, 617, 647` — переключатели minimap/номеров строк/диагностики/folding не обновляются при изменении настроек из Preferences.

**Решение:** Подключить сигнал `SettingsService` к каждому toggle-action, обновлять `state` при изменении.

---

## P2 — Качество кода

### 6. God-класс: `BaseTreeSitterHighlighter` (924 строки)

`src/Services/TreeSitter/BaseTreeSitterHighlighter.vala` — парсинг, рендеринг, фолдинг, селекция, хлебные крошки, скобочные пары, оглавление. Auto-pairing живёт здесь, а не в `SourceView`.

**Решение:** Разделить на `TreeSitterParser`, `TreeSitterRenderer`, `TreeSitterFolding`. Auto-pairing перенести в `SourceView` или отдельный `InputHandler`.

### 7. God-класс: `LspClient` (1800+ строк)

`src/Services/LSP/LspClient.vala` — жизненный цикл процесса, JSON-RPC фрейминг, парсинг capabilities, diagnostics, completion, hover, definition, formatting, code actions, pull diagnostics.

**Решение:** Разбить на транспорт + протокол + фичи-модули.

### 8. Hardcoded параметры форматирования

`src/Services/LSP/LspDocumentClient.vala:329-330` — `tab_width = 4`, `use_spaces = true` захардкожены вместо чтения из `SettingsService` или конфига языка.

**Решение:** Добавить чтение из `SettingsService` с fallback на значение по умолчанию.

### 9. `LspDocumentClient` — нет дедупликации syncer'ов

`src/Services/LSP/LspDocumentClient.vala:33-37` — `register_lsp_clients()` создаёт новые `LspClientSyncer` без проверки на дубли. Повторный вызов = дублирование syncer'ов.

**Решение:** Проверять наличие существующего syncer перед созданием нового.

---

## P3 — Чистота кода

### 10. Остаточный debug-логging в продакшене

- `SourceView.vala:530` — `message ("MIME: _ " + mime_type);`

> `application.vala:512` (MIME) и `LspClient.vala:436` (`!!!handle_incoming_notification`) — исправлены: лог от `handle_incoming_notification` заменён на JSON-RPC диспетчер `handle_payload`/`handle_server_request` (LspClient.vala:411-457).

**Решение:** Заменить на `LoggerService` или удалить.

---

## Знания — LSP: уроки clangd / code actions

Накоплено в ходе отладки code actions (clangd, ruff, basedpyright). Компиляция — единственная верификация, поэтому поведение серверов проверялось отдельными харнессами (Python-скрипт: `initialize` + `didOpen` + `codeAction` поверх stdio).

### 1. clangd шлёт code actions не только как `edit`

Часть действий («Apply fix: remove #include directive») clangd возвращает как **Command**: `{command: "clangd.applyFix", arguments: [{changes: {...}}]}`, где готовый WorkspaceEdit лежит в `arguments[0]`, а поле `edit` отсутствует. Такое поведение — следствие того, что iide **не объявляет** `codeActionLiteralSupport`/`resolveSupport` в initialize (шаблон в `LanguageRegistry.DEFAULT_LANGUAGES_JSON`).

- `parse_code_action` (LspClient.vala:1634) покрывает **три** формата правок: `edit.changes`, `edit.documentChanges` и `command.arguments[0]` как WorkspaceEdit (`parse_workspace_edit_into`, LspClient.vala:1678), плюс сохраняет `data` для `codeAction/resolve`.
- **При написании тест-харнесса копируй точный initialize-шаблон из `LanguageRegistry`, а не «идеальный» по спецификации.** Ранний харнесс объявлял `codeActionLiteralSupport`/`resolveSupport` — clangd присылал правки инлайн в `edit`, что вводило в заблуждение и не соответствовало реальному клиенту.

### 2. На запросы сервера (id + method) отвечать обязательно

По JSON-RPC клиент обязан ответить даже на неизвестный запрос. Диспетчер `handle_payload`/`handle_server_request` (LspClient.vala:411-457): `workspace/applyEdit` → `session.document_manager.apply_edits_to_file`, `workspace/configuration`/`workspace/workspaceFolders` → дефолты, остальное — ack `null`. Новые обработчики не должны бросать запрос без ответа.

### 3. `completionItem/resolve` — только при наличии `data`

Спецификация разрешает resolve лишь для элементов, у которых есть поле `data`. Gate `has_member ("data")` перед вызовом сохраняется.

### 4. Попап code actions

`Gtk.ListBox.row_activated` может не срабатывать по клику — активация продублирована `Gtk.GestureClick.released` на каждой строке (CodeActionsPopup.vala). Guard `applied` защищает от двойного применения; `Esc` и focus-leave закрывают попап.

### 5. Отладка

Домены логов: `LCA` — получение/применение правок (LspClient.vala/`SourceView.show_code_actions_menu`), `LCA-POPUP` — активация действия (CodeActionsPopup.vala). Файл лога — `~/.local/share/iide/iide.log`.

### 6. Известное ограничение: гейт «нет диагностик на строке»

`show_code_actions_menu` (SourceView.vala:918-921) ранне-возвращается, если на текущей строке нет диагностик. Из-за этого **source/refactor-действия не показываются**, если сервер отдаёт их и с пустыми диагностиками — например, ruff всегда отвечает «Fix all auto-fixable problems» и «Organize imports». Проверено харнессом: при `context.diagnostics: []` ruff возвращает 2 source-действия, clangd — 0 (регрессии нет).

**Решение (когда понадобится):** слать запрос с пустым массивом диагностик, если `collect_raw_diagnostics_for_line` вернул `null`.
