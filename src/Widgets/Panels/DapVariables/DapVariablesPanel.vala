/*
*/
public class Iide.DapVariablesPanel : BasePanel {
    public DapVariablesPanel(Window window) {
        base (window, "Debug Variables", SymbIconProvider.get_instance ().icon_name (IconID.DAP_VARIABLES));
        child = new DapVariablesWidget (window);
        can_maximize = true;
    }

    public override Panel.Position initial_pos () {
        return new Panel.Position () { area = Panel.Area.BOTTOM };
    }

    public override string panel_id () {
        return "DapVariablesPanel";
    }
}