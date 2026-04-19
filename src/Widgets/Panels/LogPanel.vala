public class Iide.LogPanel : BasePanel {
    public LogPanel () {
        base ("Logs", "document-properties-symbolic");
        child = new LogView ();
        can_maximize = true;
    }

    public override Panel.Position initial_pos () {
        return new Panel.Position () { area = Panel.Area.BOTTOM };
    }

    public override string panel_id () {
        return "LogPanel";
    }
}
