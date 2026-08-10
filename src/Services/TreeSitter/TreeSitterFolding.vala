using TreeSitter;

/**
 * Отвечает за вычисление и управление блоками сворачивания кода (folding).
 * Инкапсулирует логику анализа дерева для определения foldable регионов.
 */
public class Iide.TreeSitterFolding : Object {
    // Кэш блоков сворачивания
    protected Gee.List<IndentBlock?> cached_blocks;
    
    public signal void folding_structure_updated (Gee.List<IndentBlock?> blocks);
    
    public TreeSitterFolding () {
        cached_blocks = new Gee.ArrayList<IndentBlock?> ();
    }
    
    /**
     * Обновляет структуру фолдинга на основе текущего дерева.
     */
    public void update_structure (TreeSitter.Node root) {
        cached_blocks.clear ();
        
        if (root.is_null ()) {
            return;
        }
        
        collect_foldable_blocks (root, 0);
        folding_structure_updated (cached_blocks);
    }
    
    /**
     * Возвращает закэшированные блоки сворачивания.
     */
    public Gee.List<IndentBlock?> get_cached_blocks () {
        return cached_blocks;
    }
    
    /**
     * Рекурсивно собирает сворачиваемые блоки из дерева.
     */
    protected void collect_foldable_blocks (TreeSitter.Node parent, int current_indent) {
        for (uint32 i = 0; i < parent.named_child_count (); i++) {
            var child = parent.named_child (i);
            
            if (child.is_null ()) {
                continue;
            }
            
            string type = child.type ();
            bool is_foldable = false;
            
            if (is_foldable_node_type (type)) {
                var start_point = get_body_start_point (child);
                var end_point = child.end_point ();
                
                if (end_point.row > start_point.row) {
                    var block = IndentBlock () {
                        start_line = (int) start_point.row,
                        end_line = (int) end_point.row,
                        indent_level = current_indent
                    };
                    
                    cached_blocks.add (block);
                    is_foldable = true;
                }
            }
            
            int next_indent = is_foldable ? current_indent + 1 : current_indent;
            
            if (child.named_child_count () > 0) {
                collect_foldable_blocks (child, next_indent);
            }
        }
    }
    
    /**
     * Определяет, является ли тип узла сворачиваемым.
     * Может быть переопределен в подклассах для конкретных языков.
     */
    protected virtual bool is_foldable_node_type (string type) {
        return type == "compound_statement" || 
               type == "function_definition" || 
               type == "class_definition" ||
               type == "block";
    }
    
    /**
     * Возвращает точку начала тела узла для сворачивания.
     * Может быть переопределен для языков со специфичной структурой (например, Python).
     */
    protected virtual TreeSitter.Point get_body_start_point (TreeSitter.Node foldable_node) {
        return foldable_node.start_point ();
    }
    
    /**
     * Проверяет, существует ли блок с указанным номером строки начала.
     */
    public bool block_exists_at_line (int line_number) {
        foreach (var block in cached_blocks) {
            if (block.start_line == line_number) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * Находит блок по номеру строки начала.
     */
    public IndentBlock? find_block_by_start_line (int line_number) {
        foreach (var block in cached_blocks) {
            if (block.start_line == line_number) {
                return block;
            }
        }
        return null;
    }
}
