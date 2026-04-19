public class Iide.TerminalPanel : BasePanel {
    public TerminalPanel () {
        base ("Terminal", "utilities-terminal-symbolic");
        child = new Iide.Terminal ();
        can_maximize = true;
    }

    public override Panel.Position initial_pos () {
        return new Panel.Position () { area = Panel.Area.BOTTOM };
    }

    public override string panel_id () {
        return "TerminalPanel";
    }
}
