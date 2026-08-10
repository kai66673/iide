using TreeSitter;

/**
 * Отвечает за парсинг кода и управление деревом синтаксических узлов.
 * Инкапсулирует всю логику работы с Tree-sitter parser.
 */
public class Iide.TreeSitterParser : Object {
    protected Parser parser;
    protected TreeSitter.Tree? tree;
    
    public signal void tree_updated ();
    
    public TreeSitterParser (unowned Language lang) {
        parser = new Parser ();
        parser.set_language (lang);
    }
    
    public unowned TreeSitter.Tree? get_tree () {
        return tree;
    }
    
    public TreeSitter.Node get_root_node () {
        if (tree == null || tree.root_node ().is_null ()) {
            return TreeSitter.Node ();
        }
        return tree.root_node ();
    }
    
    public bool has_tree () {
        return tree != null && !tree.root_node ().is_null ();
    }
    
    /**
     * Выполняет полный репарсинг всего документа.
     */
    public TreeSitter.Tree? parse_full (string text) {
        tree = parser.parse_string (null, text.data);
        if (tree != null) {
            tree_updated ();
        }
        return tree;
    }
    
    /**
     * Выполняет инкрементальный парсинг с использованием старого дерева.
     */
    public TreeSitter.Tree? parse_incremental (string text) {
        tree = parser.parse_string (tree, text.data);
        if (tree != null) {
            tree_updated ();
        }
        return tree;
    }
    
    /**
     * Уведомляет парсер об изменениях в тексте для инкрементального обновления.
     */
    public void notify_edit (InputEdit edit) {
        if (tree != null) {
            tree.edit (edit);
        }
    }
    
    /**
     * Создает InputEdit для операции вставки текста.
     */
    public static InputEdit create_insert_edit (uint32 start_byte, uint32 start_row, uint32 start_col, 
                                                 string text, int len_bytes) {
        uint32 lines_added = 0;
        uint32 last_line_bytes = 0;
        int last_nl_idx = -1;

        for (int i = 0; i < len_bytes; i++) {
            if (text[i] == '\n') {
                lines_added++;
                last_nl_idx = i;
            }
        }

        if (lines_added > 0) {
            last_line_bytes = (uint32) (len_bytes - 1 - last_nl_idx);
        } else {
            last_line_bytes = (uint32) len_bytes;
        }

        InputEdit edit = {};
        edit.start_byte = start_byte;
        edit.start_point = { start_row, start_col };
        edit.old_end_byte = start_byte;
        edit.old_end_point = { start_row, start_col };
        edit.new_end_byte = start_byte + (uint32) len_bytes;
        edit.new_end_point = Point () {
            row = start_row + lines_added,
            column = (lines_added > 0) ? last_line_bytes : start_col + last_line_bytes
        };
        
        return edit;
    }
    
    /**
     * Создает InputEdit для операции удаления текста.
     */
    public static InputEdit create_delete_edit (uint32 start_byte, uint32 start_row, uint32 start_col,
                                                 uint32 end_byte, uint32 end_row, uint32 end_col) {
        InputEdit edit = {};
        edit.start_byte = start_byte;
        edit.start_point = { start_row, start_col };
        edit.old_end_byte = end_byte;
        edit.old_end_point = { end_row, end_col };
        edit.new_end_byte = start_byte;
        edit.new_end_point = edit.start_point;
        
        return edit;
    }
    
    ~TreeSitterParser () {
        parser = null;
        tree = null;
    }
}
