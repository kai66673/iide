/*
*/
public class Iide.DapCallStackPanel : BasePanel {
    public DapCallStackPanel(Window window) {
        base (window, "Debug Stack Trace", SymbIconProvider.get_instance ().icon_name (IconID.DAP_STACK_TRACE));
        child = new DapCallStackWidget ();
        can_maximize = true;
    }

    public override Panel.Position initial_pos () {
        return new Panel.Position () { area = Panel.Area.BOTTOM };
    }

    public override string panel_id () {
        return "DapCallStackPanel";
    }

}