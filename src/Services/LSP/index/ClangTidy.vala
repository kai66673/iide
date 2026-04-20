using GLib;

public class Iide.ClangTidyRunner : Object {
    public struct Diagnostic {
        public string file;
        public string line;
        public string type; // "error", "warning", "note"
        public string message;
    }

    // Сигналы для связи с основным потоком
    public signal void diagnostic_found(Diagnostic diag);
    public signal void finished(bool success, int exit_code, int total_errors, int total_warnings);

    private Subprocess? current_process = null;
    private Cancellable? cancellable = null;

    // Счётчики
    private int error_count = 0;
    private int warning_count = 0;

    public void run_async(string[] command) {
        this.cancellable = new Cancellable();
        this.error_count = 0;
        this.warning_count = 0;

        new Thread<int> ("clang-tidy-worker", () => {
            bool success = false;
            int exit_code = -1;

            try {
                this.current_process = new Subprocess.newv(
                                                           command,
                                                           SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE
                );

                var data_stream = new DataInputStream(current_process.get_stdout_pipe());

                string? line;
                string current_file = "unknown";
                var regex_full = new Regex(@"^([^:\n\\[]+):(\\d+):(\\d+): (warning|error|note): (.+?)(?: \\[([^\\]]+)\\])?$$");
                var regex_short = new Regex(@"^(warning|error|note): (.+?)(?: \\[([^\\]]+)\\])?$$");

                while (!cancellable.is_cancelled()) {
                    line = data_stream.read_line(null, cancellable);
                    if (line == null)break;

                    process_line(line, regex_full, regex_short, ref current_file);
                }

                if (!cancellable.is_cancelled()) {
                    current_process.wait(cancellable);
                    success = current_process.get_successful();
                    exit_code = current_process.get_exit_status();
                }
            } catch (Error e) {
                if (!(e is IOError.CANCELLED))stderr.printf("Thread Error: %s\n", e.message);
            } finally {
                kill_process();
                // Отправляем финальную статистику в главный поток
                Idle.add(() => {
                    this.finished(success, exit_code, this.error_count, this.warning_count);
                    return Source.REMOVE;
                });
            }
            return 0;
        });
    }

    private void process_line(string line, Regex reg_f, Regex reg_s, ref string current_file) {
        var sline = line.strip();
        if (sline.has_prefix("["))return;

        MatchInfo match;
        Diagnostic? diag = null;

        if (reg_f.match(sline, 0, out match)) {
            diag = Diagnostic() {
                file = match.fetch(1),
                line = match.fetch(2),
                type = match.fetch(4),
                message = match.fetch(5)
            };
            current_file = diag.file;
        } else if (reg_s.match(sline, 0, out match)) {
            diag = Diagnostic() {
                file = current_file,
                line = "0",
                type = match.fetch(1),
                message = match.fetch(2)
            };
        }

        if (diag != null) {
            // Обновляем статистику
            if (diag.type == "error")error_count++;
            else if (diag.type == "warning")warning_count++;

            Idle.add(() => {
                this.diagnostic_found(diag);
                return Source.REMOVE;
            });
        }
    }

    public void stop() {
        if (cancellable != null)cancellable.cancel();
        kill_process();
    }

    private void kill_process() {
        if (current_process != null) {
            current_process.force_exit();
            current_process = null;
        }
    }
}

// Пример использования
// public static int main(string[] args) {
// var loop = new MainLoop();
// var runner = new ClangTidyRunner();

// runner.diagnostic_found.connect((d) => {
// stdout.printf("[%s] %s:%s -> %s\n", d.type.up(), d.file, d.line, d.message);
// });

// runner.finished.connect((ok, code, errors, warnings) => {
// stdout.printf("\n--- Итоги анализа ---\n");
// stdout.printf("Ошибок: %d\n", errors);
// stdout.printf("Предупреждений: %d\n", warnings);
// stdout.printf("Статус завершения: %s (код %d)\n", ok ? "Успешно" : "Ошибка/Прервано", code);
// loop.quit();
// });

// string[] cmd = { "run-clang-tidy", "-p", "build/", "-checks=-*,clang-diagnostic-*" };
// runner.run_async(cmd);

// return loop.run();
// }
