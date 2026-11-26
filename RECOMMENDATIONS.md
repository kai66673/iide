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

---

## Срез ревизии 26.11.2026

### Закрыто в этом срезе

- Предупреждения valac уровня Vala — нулевые (коммит «Чистка предупреждений valac»):
  null-гейты в DocumentManager, удалён мёртвый LspWriteWaiter и недостижимый catch в
  workspace/applyEdit (json-glib в vapi не бросает GLib.Error — проверка структуры через
  get_node_type вместо try/catch), marks_service → get_mark_services() (массив не может
  быть GObject-свойством), Predicate вместо экспериментальной локальной функции,
  удалены мёртвый on_ui_cursor_changed (DapCallStack) и неиспользуемая переменная
  (LspServerRow), убран debug `message("MIME: ...")` (SourceView:530, п3-P3#10 закрыт).
- CI: `.github/workflows/build.yml` (Fedora:latest: vala 0.56, gtk4 4.24, libpanel 1.10.4).
  Нюанс окружения: openh264 (weak-dep gstreamer) не качается с некоторых зеркал →
  `--setopt=install_weak_deps=False --exclude="openh264*"`.
- Репозиторий: .gitignore заполнен; repomix-output.* и test_temp/ сняты с трекинга
  (файлы на диске). История не переписана: в истории остаются blob'ы .cache/clangd
  до 23 МБ (~.git 843 МБ) — очистка только через git filter-repo + force-push.
- A/B смоук: стартовые Gtk-CRITICAL (6× box_append, 6× create_pango_layout,
  1× image_set_from_icon_name) существовали ДО чистки — не регрессия, но и не норма:
  это баги инициализации виджетов (повторный append, layout на не-виджете), требующие
  отдельной починки.

### Открытое из старого (проверено глазом, ни один пункт не тронут)

- P0#2 утечки: во всём src/ ноль `connect_object`. Циклы: `SourceView.buffer.changed`
  (SourceView.vala:158), лямбды `SourceDocument` на `buffer.insert_text/delete_range`
  (держат сильный ref на документ; `~SourceView`/`~SourceDocument` нет вообще).
  Каждая закрытая вкладка = утёкший редактор с графом.
- P1#3: общая база `BaseRpcTransport` не сделана (RpcProcess/TcpProcess дублируют
  фрейминг Content-Length, очереди записи, барьеры завершения).
- P1#5: 4× TODO «handle changing state from preferences dialog» (application.vala).
- P2#6/#7 god-классы: LspClient ~1800 строк, BaseTreeSitterHighlighter 924.
- P2#8: захардкоженные tab_width=4/use_spaces=true (LspDocumentClient.vala:329).

### Новое открытое (26.11.2026)

- Deprecated-наследие GTK: Gtk.TreeView/TreeStore/CellRenderer целиком в
  DapVariablesWidget и DapCallStackWidget (~38 упоминаний, из GTK5 уйдут),
  gtk_widget_show/hide местами, translate_coordinates (ProjectView:316),
  gtk_source_gutter_lines_get_line_yrange (3 гаттера).
- metainfo.xml.in — нет, это пустой шаблон: example.org-URL, tld.vendor,
  "No description", summary-заглушка. Flatpak-манифест: url file:///home/kai/Projects.
  Для Flathub невалидно. po/LINGUAS пуст — переводов нет.
- LoggerService: iide.log без ротации и лимита (каждая строка — отдельный append_to).
- LspClientSyncer.add_change: пустой «TODO: merge changes» — неслиянные range-правки
  на каждый батч в INCREMENTAL-режиме.
- BaseTreeSitterHighlighter.vala:244 gcc: `result` may be used uninitialized —
  стоит проверить реальный путь инициализации.
- PythonIndenter.vala:94,101 и BaseTreeSitterHighlighter.vala:494-506 gcc:
  «statement with no effect» — вероятно, потерянные выражения (ожидались вызовы/присваивания).
