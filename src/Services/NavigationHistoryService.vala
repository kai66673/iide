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
    private static NavigationHistoryService? _instance = null;

    // В libgee LinkedList — основная реализация Deque
    private Deque<NavigationPoint> back_stack = new LinkedList<NavigationPoint> ();
    private Deque<NavigationPoint> forward_stack = new LinkedList<NavigationPoint> ();
    private const int MAX_HISTORY = 50;
    private bool is_navigate = true;

    public static NavigationHistoryService get_instance () {
        if (_instance == null) {
            _instance = new NavigationHistoryService ();
        }
        return _instance;
    }

    private NavigationHistoryService () {}

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
        if (back_stack.size < 2)// Нужно иметь хотя бы (Текущая + Куда вернуться)
            return;

        // 1. Снимаем текущую позицию и отправляем её в будущее
        var current = back_stack.poll_head ();
        forward_stack.offer_head (current);

        // 2. Теперь на вершине лежит то, что было "предпоследним"
        var target = back_stack.peek_head ();

        is_navigate = true;

        // 3. Переходим (тихо)
        if (!DocumentManager.get_instance ().navigate_to (target)) {
            // Если не смогли перейти, значит эта точка битая.
            // Удаляем её и пробуем еще раз.
            back_stack.poll_head ();
            navigate_back ();
        }

        is_navigate = false;
    }

    public void navigate_forward () {
        if (forward_stack.is_empty)
            return;

        var point = forward_stack.poll_head ();

        is_navigate = true;

        if (DocumentManager.get_instance ().navigate_to (point)) {
            back_stack.offer_head (point);
        } else {
            navigate_forward ();
        }

        is_navigate = false;
    }
}