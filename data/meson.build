desktop_file = i18n.merge_file(
        input: 'org.github.kai66673.iide.desktop.in',
       output: 'org.github.kai66673.iide.desktop',
         type: 'desktop',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'applications'
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils, args: [desktop_file])
endif

appstream_file = i18n.merge_file(
        input: 'org.github.kai66673.iide.metainfo.xml.in',
       output: 'org.github.kai66673.iide.metainfo.xml',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'metainfo'
)

appstreamcli = find_program('appstreamcli', required: false, disabler: true)
test('Validate appstream file', appstreamcli,
     args: ['validate', '--no-net', '--explain', appstream_file])

install_data('org.github.kai66673.iide.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

# компилируем gschemas.compiled в build/data/ — при запуске из каталога сборки
# приложение само находит её рядом с бинарником (см. SettingsService.load_settings);
# в glib >= 2.90 поиск схем из GResource (/glib/schemas) удалён, поэтому так
gnome.compile_schemas(build_by_default: true)

compile_schemas = find_program('glib-compile-schemas', required: false, disabler: true)
test('Validate schema file',
     compile_schemas,
     args: ['--strict', '--dry-run', meson.current_source_dir()])


service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'org.github.kai66673.iide.service.in',
  output: 'org.github.kai66673.iide.service',
  configuration: service_conf,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

subdir('icons')
