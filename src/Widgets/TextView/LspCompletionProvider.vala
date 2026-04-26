/*
 * LspCompletionProvider.vala
 *
 * Copyright 2026 kai
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;
using Gee;
using Gtk;
using GtkSource;

namespace Iide {

    public class LspCompletionProposal : GLib.Object, CompletionProposal {
        public IdeLspCompletionItem item { get; private set; }

        public LspCompletionProposal (IdeLspCompletionItem item) {
            this.item = item;
        }

        public string get_label () {
            return item.label;
        }

        public string ? get_markup () {
            return item.label;
        }

        public string get_text () {
            return item.insert_text;
        }

        public Icon ? get_icon () {
            return null;
        }

        public string ? get_info () {
            return item.documentation;
        }
    }

    public class LspCompletionProvider : GLib.Object, CompletionProvider {
        private weak SourceView source_view;
        private IdeLspService lsp_service;
        private GLib.ListStore base_store;
        private Gtk.FilterListModel filter_model;
        private string current_word = "";

        private bool filter_proposals (Object item) {
            var proposal = item as LspCompletionProposal;
            if (proposal == null)return false;

            // Используем поле filter_text из LSP, если оно есть, иначе label
            string haystack = proposal.get_label ();
            string needle = this.current_word;

            if (needle == "")return true;

            // Вызов статического метода из GtkSource.Completion
            uint priority;
            return GtkSource.Completion.fuzzy_match (haystack, needle, out priority);
        }

        public LspCompletionProvider (SourceView view) {
            this.source_view = view;
            this.lsp_service = IdeLspService.get_instance ();

            // 1. Создаем хранилище
            base_store = new GLib.ListStore (typeof (LspCompletionProposal));

            // 2. Создаем фильтр, который вызывает наш метод filter_proposals
            var custom_filter = new Gtk.CustomFilter (filter_proposals);

            // 3. Создаем модель-обертку
            filter_model = new Gtk.FilterListModel (base_store, custom_filter);
        }

        public virtual bool is_trigger (Gtk.TextIter iter, unichar ch) {
            // 1. Получаем клиент для текущего документа
            var client = IdeLspService.get_instance ().get_client_for_uri (this.source_view.uri);

            if (client == null || !client.is_initialized) {
                // Если сервер еще не готов, используем стандартный набор (на всякий случай)
                return ch == '.';
            }

            // 2. Проверяем, есть ли введенный символ в списке триггеров сервера
            string s = ch.to_string ();
            if (client.capabilities.completion_triggers.contains (s)) {
                return true;
            }

            return false;
        }

        public virtual CompletionActivation get_activation (CompletionContext context) {
            // По умолчанию: по Ctrl+Space или при наборе обычного текста
            return CompletionActivation.INTERACTIVE | CompletionActivation.USER_REQUESTED;
        }

        public virtual async GLib.ListModel populate_async (CompletionContext context, GLib.Cancellable? cancellable) throws GLib.Error {
            base_store.remove_all ();
            current_word = context.get_word ();

            if (source_view == null) {
                return filter_model;
            }

            yield source_view.sync_changes_async ();

            var buffer = source_view.buffer;
            var insert_mark = buffer.get_insert ();
            TextIter iter;
            buffer.get_iter_at_mark (out iter, insert_mark);

            int line = iter.get_line ();
            int character = iter.get_line_offset ();
            string uri = source_view.uri;

            string? trigger_char = null;
            var trigger_kind = CompletionTriggerKind.INVOKED; // Invoked по умолчанию

            TextIter prev = iter;
            if (prev.backward_char ()) {
                unichar ch = prev.get_char ();
                string s = ch.to_string ();

                var client = IdeLspService.get_instance ().get_client_for_uri (this.source_view.uri);
                if (client != null && client.capabilities.completion_triggers.contains (s)) {
                    trigger_char = s;
                    trigger_kind = CompletionTriggerKind.TRIGGER_CHARACTER;
                }
            }

            var result = yield lsp_service.request_completion (uri, line, character, trigger_char, trigger_kind);

            if (result == null || result.items.size == 0) {
                return filter_model;
            }

            foreach (var item in result.items) {
                var proposal = new LspCompletionProposal (item);
                base_store.append (proposal);
            }

            return filter_model;
        }

        public virtual void display (CompletionContext context, CompletionProposal proposal, CompletionCell cell) {
            var p = (LspCompletionProposal) proposal;

            switch (cell.column) {
            case CompletionColumn.ICON :
                cell.set_widget (SymbolIconFactory.create_for_completion (p.item.kind));
                break;
            case CompletionColumn.TYPED_TEXT:
                cell.text = p.get_label ();
                break;
            case CompletionColumn.DETAILS: {
                string? doc = p.item.documentation;
                if (doc != null && doc != "") {
                    cell.set_markup (doc);
                }
                break;
            }
            case CompletionColumn.COMMENT: {
                string? doc = p.item.detail;
                if (doc != null && doc != "") {
                    cell.set_markup (doc);
                }
                break;
            }
            default:
                break;
            }
        }

        // 2. Исправляем вставку (сдвиг)
        public virtual void activate (CompletionContext context, CompletionProposal proposal) {
            var view = context.get_view ();
            var buffer = view.get_buffer ();

            TextIter start, end;

            // Пытаемся получить границы, которые GSV уже определил как "слово под курсором"
            if (context.get_bounds (out start, out end)) {
                // Если границы найдены, просто удаляем этот участок
                buffer.delete (ref start, ref end);
            } else {
                // Если границ нет (редкий случай), используем старый метод, но аккуратно
                buffer.get_iter_at_mark (out start, buffer.get_insert ());
                end = start;
                string? word = context.get_word ();
                if (word != null && word != "") {
                    start.backward_chars (word.char_count ());
                    buffer.delete (ref start, ref end);
                }
            }

            // Вставляем слово
            var p = (LspCompletionProposal) proposal;
            buffer.insert (ref start, p.get_label (), -1);
        }

        // Обязательные методы-заглушки
        public virtual void refilter (CompletionContext context, GLib.ListModel model) {
            current_word = context.get_word ();

            // 6. Достаем фильтр и заставляем его пересчитать список
            var filter = filter_model.get_filter () as Gtk.CustomFilter;
            filter.changed (Gtk.FilterChange.DIFFERENT);

            if (model.get_n_items () == 0) {
                context.get_completion ().hide ();
            }
        }

        public virtual string ? get_title () { return "Simple"; }
        public virtual int get_priority (CompletionContext context) { return 100; }
        public virtual bool is_running (CompletionContext context) { return true; }
    }
}