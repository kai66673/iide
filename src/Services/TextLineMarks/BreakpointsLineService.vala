/*
*/
public class Iide.BreakpointsLineService : TextLineMarkService {
    private FgRenderInfo _fg_render_info;
    
    public BreakpointsLineService (WindowSession session, string category) {
        base (session, category);
        this._fg_render_info = FgRenderInfo () {
            red = 0.92, green = 0.25, blue = 0.25, alpha = 1.0, priority = 2
        };
    }
    
    public override Iide.FgRenderInfo foreground_render_info() {
        return this._fg_render_info;
    }

    public override void render_base(Cairo.Context cr, double cell_y, double cell_height, double gutter_width, double draw_x, double draw_y) {
        cr.save ();
        
        // 1. Мягкий полупрозрачный красный фон всей ячейки строки
        cr.set_source_rgba (0.92, 0.25, 0.25, 0.12); 
        cr.rectangle (0, cell_y, gutter_width, cell_height);
        cr.fill ();

        // 2. ОТРИСОВКА МИНИАТЮРНОГО ПОЛУОВАЛА "(|" У ПРАВОГО КРАЯ
        cr.set_source_rgba (0.92, 0.25, 0.25, 1.0); 

        // УМEНЬШАEМ РАДИУС ВДВОE: Делаем маркер компактным и ювелирным
        double radius = cell_height / 4.0; 
        
        // Вычисляем математический центр дуги строго по середине ячейки
        double center_x = gutter_width; 
        double center_y = cell_y + (cell_height / 2.0);

        // Рисуем левую дугу от 90° (низ) до 270° (верх) по часовой стрелке
        cr.arc (center_x, center_y, radius, Math.PI / 2.0, 3.0 * Math.PI / 2.0);
        
        // ЧEСТНО ЗАМЫКАEМ ФИГУРУ: Рисуем прямую линию по правому краю 
        // вниз к точке окончания дуги (center_y + radius)
        cr.line_to (center_x, center_y + radius);
        
        // Заливаем миниатюрный полуовал
        cr.fill ();
        
        cr.restore ();
    }
}