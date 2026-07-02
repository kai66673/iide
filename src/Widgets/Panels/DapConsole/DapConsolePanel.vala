/*
*/
public class Iide.DapConsolePanel : BasePanel {
    public DapConsolePanel (Window window) {
        base (window, "Debug Console", SymbIconProvider.get_instance ().icon_name (IconID.DAP_CONSOLE));
        child = new DapConsoleWidget ();
        can_maximize = true;

    }
    
    public override Panel.Position initial_pos () {
        return new Panel.Position () { area = Panel.Area.BOTTOM };
    }

    public override string panel_id () {
        return "DapConsolePanel";
    }
}   