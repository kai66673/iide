/*
*/
public class Iide.BookmarksLineService : TextLineMarkService {
    private FgRenderInfo _fg_render_info;

    public BookmarksLineService (Window window, string category) {
        base (window, category);
        this._fg_render_info = FgRenderInfo () {
            red = 0.2, green = 0.52, blue = 0.89, alpha = 1.0, priority = 1
        };
    }

    public override Iide.FgRenderInfo foreground_render_info() {
        return this._fg_render_info;
    }

    public override void render_base(Cairo.Context cr, double cell_y, double cell_height, double gutter_width, double draw_x, double draw_y) {
        cr.save ();
        
        cr.set_source_rgba (0.2, 0.52, 0.89, 0.15); 
        cr.rectangle (0, cell_y, gutter_width, cell_height);
        cr.fill ();

        cr.set_source_rgba (0.2, 0.52, 0.89, 1.0); 
        cr.rectangle (0, cell_y, 3.0, cell_height); 
        cr.fill ();
        
        cr.restore ();
    }
}