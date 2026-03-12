iide_sources = [
    'main.vala',
    'application.vala',
    'window.vala',
    'interfaces/PaneSwitcher.vala',
    'Widgets/SourceList/SourceList.vala',
    'Widgets/TextDocument.vala',
    'Widgets/Terminal.vala',
]

iide_deps = [
    config_dep,
    dependency('gtk4'),
    dependency('gio-2.0', version: '>= 2.50'),
    dependency('libadwaita-1', version: '>= 1.4'),
    dependency('libpanel-1', version: '>= 1.7'),
    dependency('gtksourceview-5'),
    dependency('vte-2.91-gtk4', version: '>= 0.75.0'),
]

iide_sources += gnome.compile_resources('iide-resources', 'iide.gresource.xml', c_name: 'iide')

executable(
    'iide',
    iide_sources,
    dependencies: iide_deps,
    include_directories: config_inc,
    install: true,
)
