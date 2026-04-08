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

    public class OldLspCompletionProvider : GLib.Object, CompletionProvider {
        private weak Iide.TextView text_view;
        private IdeLspService lsp_service;

        public OldLspCompletionProvider (Iide.TextView view) {
            this.text_view = view;
            this.lsp_service = IdeLspService.get_instance ();
        }

        public virtual CompletionActivation get_activation (CompletionContext context) {
            // Разрешаем показ при наборе текста (INTERACTIVE)
            // и принудительный показ по Ctrl+Space (USER_REQUESTED)
            return // CompletionActivation.INTERACTIVE |
                   CompletionActivation.USER_REQUESTED;
        }

        public virtual async GLib.ListModel populate_async (CompletionContext context, GLib.Cancellable? cancellable) throws GLib.Error {
            var store = new GLib.ListStore (typeof (LspCompletionProposal));

            if (text_view == null) {
                return store;
            }

            var buffer = text_view.text_view.buffer;
            var insert_mark = buffer.get_insert ();
            TextIter iter;
            buffer.get_iter_at_mark (out iter, insert_mark);

            int line = iter.get_line ();
            int character = iter.get_line_offset ();
            string uri = text_view.uri;

            var result = yield lsp_service.request_completion (uri, line, character);

            if (result == null || result.items.size == 0) {
                return store;
            }


            foreach (var item in result.items) {
                var proposal = new LspCompletionProposal (item);
                store.append (proposal);
            }

            return store;
        }

        public virtual void display (CompletionContext context, CompletionProposal proposal, CompletionCell cell) {
            var p = (MyProposal) proposal;
            if (cell.column == CompletionColumn.TYPED_TEXT) {
                cell.text = p.label;
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
            // Когда пользователь вводит текст, GSV передает нам текущую модель (наш ListStore).
            // Мы очищаем его и заполняем заново исходя из нового слова.
            var list = model as GLib.ListStore;
            if (list == null)
                return;

            string? word = context.get_word ();
            if (word == null || word.length == 0) {
                list.remove_all ();
                return;
            }

            var store = new GLib.ListStore (typeof (LspCompletionProposal));
            for (var i = 0; i < list.get_n_items (); i++) {
                var proposal = (LspCompletionProposal) list.get_item (i);
                if (proposal.get_label ().has_prefix (word)) {
                    store.append (proposal);
                }
            }
            model = store;

            if (model.get_n_items () == 0) {
                context.get_completion ().hide ();
            }
        }

        public virtual string ? get_title () { return "Simple"; }
        public virtual int get_priority (CompletionContext context) { return 100; }
        public virtual bool is_running (CompletionContext context) { return true; }
    }
}
