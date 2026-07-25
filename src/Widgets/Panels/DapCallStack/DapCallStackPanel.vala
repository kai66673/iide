/*
*/
public class Iide.DapCallStackPanel : BasePanel {
    public DapCallStackPanel(WindowSession session) {
        base (session, "Debug Stack Trace", SymbIconProvider.get_instance ().icon_name (IconID.DAP_STACK_TRACE));
        child = new DapCallStackWidget (session);
        can_maximize = true;
    }

    public override Panel.Position initial_pos () {
        return new Panel.Position () { area = Panel.Area.BOTTOM };
    }

    public override string panel_id () {
        return "DapCallStackPanel";
    }

}