/*
*/

public class Iide.FeatureConfig : GLib.Object {
    public string engine { get; set; default = "lsp"; } // "lsp" или "cli"
    public string? command { get; set; default = null; } // Команда для shell-пайплайна
}

public class Iide.LanguageProfile : GLib.Object {
    public string id { get; set; }
    public string display_name { get; set; }
    public Gee.ArrayList<string> extensions { get; set; default = new Gee.ArrayList<string>(); }
    
    public LspConfig? lsp { get; set; default = null; }
    public FeatureConfig? formatting { get; set; default = null; }
    public FeatureConfig? linting { get; set; default = null; }
}