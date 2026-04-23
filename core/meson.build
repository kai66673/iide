gnome = import('gnome')

core_sources = files(
    'SearchExtension.vala',
    'SearchResult.vala',
)

# Зависимости для core
core_deps = [
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gio-2.0'),
    dependency('gee-0.8'),
    dependency('gtk4'),
]

# 1. Собираем саму библиотеку
core_lib = shared_library(
    'iide-core',
    core_sources,
    dependencies: core_deps,
    install: true,
    # Meson сам создаст .vapi и .h файлы
    vala_vapi: 'iide-core-1.0.vapi',
    vala_header: 'iide-core.h',
)

# 2. Генерируем GObject Introspection (.gir и .typelib)
# Это то, что позволит Python делать "from gi.repository import IideCore"
iide_gir = gnome.generate_gir(
    core_lib,
    sources: core_sources,
    namespace: 'IideCore',
    nsversion: '1.0',
    identifier_prefix: 'Iide',
    symbol_prefix: 'iide',
    export_packages: 'iide-core',
    includes: ['GObject-2.0', 'Gio-2.0', 'Gtk-4.0'],
    install: true,
)

# 3. Создаем зависимость для основного проекта
core_dep = declare_dependency(
    link_with: core_lib,
    include_directories: include_directories('.'),
    sources: [iide_gir] # Прикрепляем GIR к зависимости,,,,,,,,,,,,,,,,
)
