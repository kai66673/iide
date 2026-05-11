#!/bin/bash

# Находим реальный путь к директории, где лежит этот скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Переходим в корень проекта (на один уровень выше папки scripts)
cd "$SCRIPT_DIR/.." || exit

echo "Текущая директория для Doxygen: $(pwd)"

# 1. Генерируем документацию
doxygen Doxyfile

# 2. Проверяем успех
if [ $? -eq 0 ]; then
    echo "Документация сгенерирована."
    
    # Путь к HTML (теперь точно относительно корня)
    # Если в Doxyfile OUTPUT_DIRECTORY = build/docs, то путь такой:
    DOC_PATH="./build/docs/html"
    
    if [ -d "$DOC_PATH" ]; then
        echo "Запуск сервера..."
        xdg-open "http://localhost:8080/index.html" &
        cd "$DOC_PATH" && python3 -m http.server 8080
    else
        echo "Ошибка: Директория $DOC_PATH не найдена. Проверьте OUTPUT_DIRECTORY в Doxyfile."
    fi
else
    echo "Ошибка при работе Doxygen."
    exit 1
fi
