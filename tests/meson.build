test_lsp_service_sources = [
    'test_lsp_service.vala',
    'LSPService.vala',
]

test_lsp_service_deps = [
    dependency('glib-2.0'),
    dependency('gio-2.0'),
    dependency('json-glib-1.0'),
    dependency('gee-0.8'),
]

test_lsp_service = executable(
    'test_lsp_service',
    test_lsp_service_sources,
    dependencies: test_lsp_service_deps,
    install: false,
)

test(
    'lsp_service',
    test_lsp_service,
    protocol: 'exitcode',
)
