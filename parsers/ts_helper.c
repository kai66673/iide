#include <tree_sitter/api.h>
#include <stdlib.h>

// Реальное тело функции, которая делает "мостик"
TSTreeCursor* ts_tree_cursor_new_as_ptr(TSNode node) {
    TSTreeCursor cursor = ts_tree_cursor_new(node);
    TSTreeCursor *result = malloc(sizeof(TSTreeCursor));
    *result = cursor;
    return result;
}
