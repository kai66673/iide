# AGENTS.md — iide (Intelligent IDE)

## What is this

A native Linux IDE written in **Vala** (GTK4 + Libadwaita + Libpanel). Tree-sitter for syntax, LSP for semantics, DAP for debugging (WIP). Meson build system.

Note: code comments, the README, and commit messages are largely in **Russian** — don't rewrite them.

## Build & Run

```bash
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
- `.iide/` — per-project session config: `workspace.json` (tabs/session, written by `ProjectManager`) and `lsp.json` (per-project LSP overrides, deep-merged over the default matrix in `LanguageRegistry.load_project_lsp_matrix`). Bookmarks are **in-memory only** — not persisted.

## Multiple build directories

`build/`, `builddir/`, `rebuild/`, `run/` all exist. The README references `builddir/`; the VSCode tasks use `build/`. Pick one and be consistent — `builddir` is canonical per README.

## Conventions

- All source is Vala (namespace `Iide.*`). New files must be added to `src/meson.build` `iide_sources` array.
- Tree-sitter parser C sources are listed explicitly in the root `meson.build` — adding a new language parser requires updating that list. Grammars are git submodules under `parsers/`. Most compile into the shared `tree-sitter-runtime` static lib, but XML, C, TypeScript, and PHP are built as **separate** static libs due to their nested repo layout (`parsers/xml/xml/src/…`, etc.). Highlighters (when needed) live in `src/Services/TreeSitter/<lang>/` and are instantiated in `TreeSitterManager`.
- Actions are defined as private subclasses of `Iide.AppAction` in `src/application.vala`, registered via `AppActionsManager`.
- UI XML files live alongside their widgets; GResource XML is `src/iide.gresource.xml`.
- App ID: `org.github.kai66673.iide`.

## Gotchas

- `GSK_RENDERER` is force-set to `ngl` in `main.vala:22` — do not remove this.
- Flatpak manifest (`org.github.kai66673.iide.json`) hardcodes `file:///home/kai/Projects` as the source URL — needs updating if you move the repo.
- Doxygen docs are optional: `meson compile -C builddir docs` (requires `doxygen` installed). `scripts/gen-docs.sh` hardcodes the output to `build/docs/html` (not `builddir/`) and serves it on `localhost:8080`.
- `vendor/tree-sitter` is a fork (`albfan/tree-sitter`), not upstream — respect this when updating.
- The repo's own `.iide/lsp.json` is committed and overrides the default LSP matrix: clangd runs as `clangd --header-insertion=never` for `*.cpp`/`*.hpp`.

## Build quirks

- `symbols/` icons are **generated at build time**: `symbols/export_glyph.py` (meson `custom_target`) turns `symbols/icons.json` + `symbols/fonts/SYMBOLIC.ttf` into SVGs and a gresource (`symbols_res`), which is wired into the executable in `src/meson.build`. Requires `python3`.
- `meson install` runs `scripts/install-local-settings.sh`, which copies the GSettings schema and icons into `~/.local/share` for development. Runtime may need `XDG_DATA_DIRS="$HOME/.local/share:$XDG_DATA_DIRS"` to pick up the schema.
