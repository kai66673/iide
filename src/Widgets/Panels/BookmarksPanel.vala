/*
*/

public class Iide.BookmarksPanel : BasePanel {
    public BookmarksPanel(Window window) {
        base (window, "Bookmarks", SymbIconProvider.get_instance ().icon_name (IconID.APP_BOOKMARKS));
        child = new BookmarksView (window);
        can_maximize = true;
    }

    public override Panel.Position initial_pos () {
        return new Panel.Position () { area = Panel.Area.BOTTOM };
    }

    public override string panel_id () {
        return "BookmarksPanel";
    }
}