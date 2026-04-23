import gi

# Указываем версию вашего Core, которую мы прописали в Meson
gi.require_version("IideCore", "1.0")

from gi.repository import GLib, GObject, IideCore


class PythonSearchPlugin(GObject.Object, IideCore.SearchExtension):
    def do_activate(self):
        print("Плагин поиска активирован")

    def do_deactivate(self):
        print("Плагин поиска деактивирован")

    def do_run_search(self, query, callback, cancellable):
        # Логика поиска...
        results = []
        # Пример результата:
        # res = IideCore.SearchResult(
        #     file_path="main.vala",
        #     line_number=5,
        #     line_content="void main()",
        #     icon_name="text-x-vala"
        # )
        # results.append(res)

        # Передаем пачку результатов в основной поток
        GLib.idle_add(callback, results)
