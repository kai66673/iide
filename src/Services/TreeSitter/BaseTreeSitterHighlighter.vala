using TreeSitter;

/**
 * Базовый класс для подсветки синтаксиса на основе Tree-sitter.
 * 
 * ДЕКОМПОЗИЦИЯ (P2):
 * Этот класс теперь делегирует задачи специализированным модулям:
 * - TreeSitterParser: парсинг и управление деревом
 * - TreeSitterRenderer: рендеринг подсветки
 * - TreeSitterFolding: вычисление блоков сворачивания
 * 
 * Оставшаяся ответственность:
 * - Управление сигналами GTK
 * - Auto-pairing (скобки, кавычки)
 * - Breadcrumbs и навигация по AST
 * - Выделение узлов (expand/shrink selection)
 */
public abstract class Iide.BaseTreeSitterHighlighter : Object {
    // Модули (делегированная ответственность)
    protected TreeSitterParser ts_parser;
    protected TreeSitterRenderer ts_renderer;
    protected TreeSitterFolding ts_folding;
    
    // GTK объекты
    protected GtkSource.Buffer buffer;
    public SourceView view;
    
    // Стиль
    protected StyleService style_service;
    private int current_theme_index = 0;
    
    // Debounce для скролла
    private uint highlight_timeout_id = 0;
    private const uint DEBOUNCE_MS = 150;
    
    // Selection stack для expand/shrink
    private Gee.ArrayQueue<TreeSitter.Range?> selection_stack = new Gee.ArrayQueue<TreeSitter.Range?> ();
    private bool is_internal_selection_change = false;
    
    // Breadcrumbs
    private Gee.List<SourceNodeItem?> last_crumbs = null;
    public signal void breadcrumbs_changed (Gee.List<SourceNodeItem?> crumbs);
    
    // Сигнал, сообщающий UI-компонентам, что структура блоков изменилась
    public signal void folding_structure_updated (Gee.List<IndentBlock?> blocks);
    
    public void force_full_reparse () {
        set_color_theme ();
    }
    
    private void set_color_theme () {
        var color_scheme = SettingsService.get_instance ().color_scheme;
        current_theme_index = color_scheme != ColorScheme.LIGHT ? 1 : 0;
        ts_renderer.set_theme_index (current_theme_index);
        
        if (highlight_timeout_id > 0) {
            Source.remove (highlight_timeout_id);
        }
        initial_rehighlight ();
    }
    
    protected BaseTreeSitterHighlighter (SourceView view) {
        base ();
    }
    
    ~BaseTreeSitterHighlighter () {
        ts_parser = null;
        ts_renderer = null;
        ts_folding = null;
    }
}
