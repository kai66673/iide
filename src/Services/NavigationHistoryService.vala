using Gee;


public class Iide.NavigationPoint : Object {
    public File file { get; construct; }
    public int line { get; construct; }
    public int column { get; construct; }

    public NavigationPoint (File file, int line, int column) {
        Object (file: file, line: line, column: column);
    }
}

public class Iide.NavigationHistoryService : Object {
    public weak Window window;

    // В libgee LinkedList — основная реализация Deque
    private Deque<NavigationPoint> back_stack = new LinkedList<NavigationPoint> ();
    private Deque<NavigationPoint> forward_stack = new LinkedList<NavigationPoint> ();
    private const int MAX_HISTORY = 50;
    private bool is_navigate = true;

    public NavigationHistoryService (Window window) {
        this.window = window;
    }

    public void start_navigation () {
        is_navigate = false;
    }

    /**
     * Сохраняет новую точку в историю.
     * Вызывайте перед прыжком (Go to Definition) или при смене файла.
     */
    public void push_point (File file, int line, int column) {
        if (is_navigate)
            return;

        var point = new NavigationPoint (file, line, column);

        // Согласно доке: push = offer_head
        back_stack.offer_head (point);

        // При совершении нового действия история "вперед" всегда очищается
        forward_stack.clear ();

        // Ограничиваем размер истории
        if (back_stack.size > MAX_HISTORY) {
            back_stack.poll_tail ();
        }
    }

    public void navigate_back () {
        if (back_stack.size < 2) // Нужно иметь хотя бы (Текущая + Куда вернуться)
            return;

        is_navigate = true;

        while (back_stack.size >= 2) {
            // 1. Снимаем текущую позицию и отправляем её в будущее
            var current = back_stack.poll_head ();
            forward_stack.offer_head (current);

            // 2. Теперь на вершине лежит то, что было "предпоследним"
            var target = back_stack.peek_head ();

            // 3. Переходим (тихо)
            if (this.window.document_manager.navigate_to (target)) {
                break;
            }
            // Если не смогли перейти, значит эта точка битая — удаляем её.
            back_stack.poll_head ();
        }

        is_navigate = false;
    }

    public void navigate_forward () {
        is_navigate = true;

        while (!forward_stack.is_empty) {
            var point = forward_stack.poll_head ();

            if (this.window.document_manager.navigate_to (point)) {
                back_stack.offer_head (point);
                break;
            }
            // Битая точка молча удаляется из истории
        }

        is_navigate = false;
    }
}