# AGENTS.md — iide (Intelligent IDE)

## What is this

A native Linux IDE written in **Vala** (GTK4 + Libadwaita + Libpanel). Tree-sitter for syntax, LSP for semantics, DAP for debugging (WIP). Meson build system.

Note: code comments, the README, and commit messages are largely in **Russian** — don't rewrite them.

## Build & Run

```bash
git submodule update --init --recursive   # required: parsers/ + vendor/ are submodules; build fails without them
meson setup builddir
meson compile -C builddir
./builddir/src/iide
```

Reconfigure an existing build dir:
```bash
meson setup builddir --reconfigure
meson compile -C builddir
```

There is no test suite, linter, or typecheck step — **compilation is the only verification**.

## System dependencies

`meson` (>= 1.0.0), `valac` (>= 0.56), `gtk4`, `libadwaita-1` (>= 1.4), `gtksourceview-5`, `libpanel-1` (>= 1.7), `gee-0.8`, `json-glib-1.0`, `jsonrpc-glib-1.0`, `vte-2.91-gtk4` (>= 0.75.0), plus `python3` (icon codegen). All `-dev` packages required.

## Project structure

- `src/` — all Vala source, entrypoint at `src/main.vala`
- `src/Services/` — backend logic (LSP, Tree-sitter, DAP, Bookmarks, JSON-RPC, etc.)
- `src/Widgets/` — UI components (TextView, Panels, Find, Preferences)
- `parsers/` — tree-sitter grammar submodules (C source compiled via `meson.build`)
- `vendor/tree-sitter/` — vendored tree-sitter runtime (git submodule, use the `albfan` fork)
- `vapi/libtreesitter.vapi` — Vala bindings for tree-sitter C API
- `data/` — GSchema, desktop file, metainfo, icons
- `symbols/` — icon/symbol resources (generated at build time, see Build quirks)
- `src/icons/`, `src/fonts/` — embedded mimetype icons / font, bundled via `src/iide.gresource.xml` (distinct from `symbols/`)
- `po/` — gettext translations
- `.iide/` — per-project session config: `workspace.json` (tabs/session, written by `ProjectManager`) and `lsp.json` (per-project LSP overrides, deep-merged over the default matrix in `LanguageRegistry.load_project_lsp_matrix`). Bookmarks are **in-memory only** — not persisted (the README's claim of a `bookmarks.json` is stale; no code writes it).

## Build directory naming

README examples use `builddir/`; the `.vscode` tasks (`Build Iide` / `Run Iide` — the latter compiles then launches `build/src/iide`) use `build/`. Only `build/` currently exists on disk — use it unless told otherwise. Meson auto-generates a `build/.gitignore` containing `*`; the repo-root `.gitignore` is empty and `git check-ignore` will not explain this. `.cache/` is a self-ignored clangd index.

## Conventions

- All source is Vala (namespace `Iide.*`). New files must be added to `src/meson.build` `iide_sources` array.
- Tree-sitter parser C sources are listed explicitly in the root `meson.build` — adding a new language parser requires updating that list. Grammars are git submodules under `parsers/`. Most compile into the shared `tree-sitter-runtime` static lib, but XML, C, TypeScript, and PHP are built as **separate** static libs due to their nested repo layout (`parsers/xml/xml/src/…`, etc.). Highlighters (when needed) live in `src/Services/TreeSitter/<lang>/` and are instantiated in `TreeSitterManager`.
- Actions are defined as private subclasses of `Iide.AppAction` in `src/application.vala`, registered via `AppActionsManager`.
- Only two GtkBuilder UI files exist — `src/window.ui`, `src/shortcuts-dialog.ui` (at `src/` root, not next to widgets); most other UI is built in Vala code. GResource XML is `src/iide.gresource.xml`.
- App ID: `org.github.kai66673.iide`.

## Gotchas

- `GSK_RENDERER` is force-set to `ngl` in `main.vala:22` — do not remove this.
- Flatpak manifest (`org.github.kai66673.iide.json`) hardcodes `file:///home/kai/Projects` as the source URL — needs updating if you move the repo.
- Doxygen docs are optional: the `docs` run target only exists if `doxygen` was found at *configure* time — install it, then `meson setup --reconfigure`. `scripts/gen-docs.sh` hardcodes the output to `build/docs/html` and serves it on `localhost:8080`.
- `repomix-output.md` / `repomix-output.pdf` (tracked, ~800KB) are generated full-repo dumps with compressed/lossy code blocks — **never grep or read them as source**; they pollute every search with stale duplicates. `test_temp/test.c` is tracked scratch too.
- `vendor/tree-sitter` is a fork (`albfan/tree-sitter`), not upstream — respect this when updating.
- The repo's own `.iide/lsp.json` is committed and overrides the default LSP matrix: clangd runs as `clangd --header-insertion=never` for `*.cpp`/`*.hpp`.

## Build quirks

- `symbols/` icons are **generated at build time**: `symbols/export_glyph.py` (meson `custom_target`) turns `symbols/icons.json` + `symbols/fonts/SYMBOLIC.ttf` into SVGs and a gresource (`symbols_res`), which is wired into the executable in `src/meson.build`. Requires `python3`.
- `meson install` (prefix `/usr/local`, needs sudo — the script handles `SUDO_USER`) runs a generated install script (`scripts/install-local-settings.sh.in`) that also copies the GSettings schema and icons into `~/.local/share` **without** sudo semantics; the source XML/SVGs are read from the source tree via `@SOURCE_DATA_DIR@` (build dir contains no sources). GIO picks up `~/.local/share/glib-2.0/schemas` automatically — no `XDG_DATA_DIRS` needed (verified).
- Run-without-install works out of the box: `gnome.compile_schemas(build_by_default: true)` in `data/meson.build` emits `build/data/gschemas.compiled`, and `SettingsService.load_settings()` (Vala) self-locates it — search order: default source → `gschemas.compiled` in `builddir/data` (exe-relative via `/proc/self/exe`) → `Config.DATADIR/glib-2.0/schemas`. So plain `./builddir/src/iide` works with nothing installed. Note: the GResource schema trick (`/glib/schemas` blobs) **does not work on glib >= 2.90** — that mechanism was removed from both libgio and glib-compile-resources (`--schemalang`, `preprocess="glib-compile-schemas"` are gone). The previously tracked `data/gschemas.compiled` was a stale leftover of that old pattern and was deleted.
