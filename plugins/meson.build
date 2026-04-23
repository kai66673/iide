# Список плагинов
plugin_folders = [
    'python_search',
]

foreach folder : plugin_folders
    # 1. Установка в систему (как и было)
    install_subdir(folder, install_dir: get_option('libdir') / 'iide' / 'plugins')

    # 2. Копирование для локальной разработки
    # Нам нужно скопировать каждый файл отдельно
    plugin_files = ['search.plugin', 'search.py']

    foreach f : plugin_files
        configure_file(
            input: folder / f,
            output: f, # Здесь только имя файла
            copy: true,
            # Эта строка магии: она положит файл в build/plugins/название_папки/
            install: false,
            install_dir: folder,
        )
    endforeach
endforeach
