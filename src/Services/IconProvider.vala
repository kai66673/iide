/*
 */

public class Iide.IconProvider {

    private static IconProvider? instance = null;

    private Pango.AttrList _cached_attrs;
    private Pango.FontDescription[] _font_descriptions;
    private int _icon_sizes[2] = { 16, 18 };
    private Gee.HashMap<string, Gdk.Texture> _file_textures;

    private Gdk.Texture[] _folder_textures;

    public static IconProvider get_instance() {
        if (instance == null) {
            instance = new IconProvider();
        }
        return instance;
    }

    private IconProvider() {
        _font_descriptions = {
            Pango.FontDescription.from_string("Symbols Nerd Font 11"),
            Pango.FontDescription.from_string("Symbols Nerd Font 12")
        };

        _cached_attrs = new Pango.AttrList();
        foreach (var fd in _font_descriptions) {
            _cached_attrs.insert(Pango.AttrFontDesc.new(fd));
        }

        Gdk.RGBA color = Gdk.RGBA();
        color.parse("#dcb67a");

        _folder_textures = {
            render_font_char_to_texture("\ueaf7", color, 0),
            render_font_char_to_texture("\ueaf7", color, 1)
        };

        _file_textures = new Gee.HashMap<string, Gdk.Texture> ();

        ///////////////////////////////////////////////////
        // File Extensions

        // --- Системные / Конфиги ---
        var mk_texture = render_font_char_to_texture
                ("\uf308", Gdk.RGBA() { red = 0.43f, green = 0.50f, blue = 0.53f, alpha = 1.0f }, 1);
        _file_textures.set(".mk", mk_texture);
        _file_textures.set("makefile", mk_texture);

        var docker_texture = render_font_char_to_texture
                ("\uf308", Gdk.RGBA() { red = 0.22f, green = 0.30f, blue = 0.33f, alpha = 1.0f }, 1);
        _file_textures.set("dockerfile", docker_texture);
        _file_textures.set(".dockerfile", docker_texture);

        var json_texture = render_font_char_to_texture
                ("\uf308", Gdk.RGBA() { red = 0.80f, green = 0.80f, blue = 0.25f, alpha = 1.0f }, 1);
        _file_textures.set(".json", json_texture);

        var xml_texture = render_font_char_to_texture
                (((unichar) 0xf05c0).to_string(), Gdk.RGBA() { red = 0.89f, green = 0.47f, blue = 0.20f, alpha = 1.0f }, 1);
        _file_textures.set(".xml", xml_texture);
        _file_textures.set(".ui", xml_texture);
        _file_textures.set(".glade", xml_texture);
        _file_textures.set(".qrc", xml_texture);

        var yaml_texture = render_font_char_to_texture
                ("\ue6a8", Gdk.RGBA() { red = 0.80f, green = 0.24f, blue = 0.13f, alpha = 1.0f }, 1);
        _file_textures.set(".yaml", yaml_texture);
        _file_textures.set(".yml", yaml_texture);

        var conf_texture = render_font_char_to_texture
                ("\ue615", Gdk.RGBA() { red = 0.43f, green = 0.50f, blue = 0.53f, alpha = 1.0f }, 1);
        _file_textures.set(".conf", conf_texture);
        _file_textures.set(".ini", conf_texture);
    }

    private Gtk.Image image_from_texture(Gdk.Texture texture, int icon_size) {
        var img = new Gtk.Image.from_paintable(texture);
        img.pixel_size = icon_size;
        return img;
    }

    private Gdk.Texture render_font_char_to_texture(string icon_char,
                                                    Gdk.RGBA color,
                                                    int size_index) {
        var icon_size = _icon_sizes[size_index];

        // Рендерим в Cairo Surface
        var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, icon_size, icon_size);
        var cr = new Cairo.Context(surface);

        Gdk.cairo_set_source_rgba(cr, color);

        // Настраиваем Pango Layout
        var layout = Pango.cairo_create_layout(cr);
        layout.set_font_description(_font_descriptions[size_index]);
        layout.set_text(icon_char, -1);

        // Центрируем иконку
        Pango.Rectangle ink_rect, logical_rect;
        layout.get_pixel_extents(out ink_rect, out logical_rect);
        cr.move_to((icon_size - logical_rect.width) / 2.0,
                   (icon_size - logical_rect.height) / 2.0);

        Pango.cairo_show_layout(cr, layout);

        size_t data_size = (size_t) surface.get_stride() * icon_size;
        return new Gdk.MemoryTexture(icon_size,
                                     icon_size,
                                     Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED,
                                     new Bytes(surface.get_data()[0 : data_size]),
                                     surface.get_stride());
    }
}