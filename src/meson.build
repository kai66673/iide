iide_sources = [
    'main.vala',
    'application.vala',
    'window.vala',
    'Widgets/TextView.vala',
    'Widgets/ToolViews/ProjectView.vala',
    'Widgets/ToolViews/TerminalView.vala',
    'Services/Utils.vala',
    'Services/DocumentManager.vala',
    'Services/IconProvider.vala',
    'Services/TreeSitter/TreeSitterManager.vala',
    'Services/TreeSitter/model/AstItem.vala',
    'Services/TreeSitter/model/AstModel.vala',
]

iide_deps = [
    config_dep,
    dependency('gtk4'),
    dependency('gio-2.0', version: '>= 2.50'),
    dependency('libadwaita-1', version: '>= 1.4'),
    dependency('libpanel-1', version: '>= 1.7'),
    dependency('gtksourceview-5'),
    dependency('vte-2.91-gtk4', version: '>= 0.75.0'),
    dependency('gee-0.8'),
]

iide_sources += gnome.compile_resources('iide-resources', 'iide.gresource.xml', c_name: 'iide')

executable(
    'iide',
    iide_sources,
    dependencies: [iide_deps, tree_sitter_dep],
    include_directories: config_inc,
    install: true,
)
