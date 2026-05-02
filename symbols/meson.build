gnome = import('gnome')
python = import('python').find_installation('python3')

icons_json = files('icons.json')
font_file = files('fonts/SYMBOLIC.ttf')
script = files('export_glyph.py')

# Папка для SVG (внутри build/symbols/gen_icons)
gen_dir = meson.current_build_dir() / 'gen_icons'

symbols_gen = custom_target(
    'symbols-gen',
    input: [icons_json, font_file],
    # Meson сам подставит путь к этим файлам в @OUTPUT0@ и @OUTPUT1@
    output: ['symbols.gresource.xml', 'gen_icons'], 
    command: [
        python, script, 
        '@INPUT0@', # json
        '@INPUT1@', # ttf
        gen_dir,    # куда класть SVG
        '@OUTPUT0@' # куда положить XML (Meson даст путь build/symbols/symbols.gresource.xml)
    ],
    build_by_default: true
)

symbols_res = gnome.compile_resources(
    'symbols-resources',
    symbols_gen[0], # Ссылаемся на первый элемент output (XML)
    source_dir: gen_dir,
    dependencies: symbols_gen
)
