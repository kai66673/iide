public class Iide.LspRegistry {
    public static string ? get_lsp_id (string language) {
        switch (language) {
        case "python":
            return "basedpyright";
        case "cpp":
            return "clangd";
        default:
            return null;
        }
    }

    public static LspConfig ? get_config (string lsp_id) {
        switch (lsp_id) {
        case "basedpyright" :
            return new PythonLspConfig ();
        case "clangd":
            return new CppLspConfig ();
        default:
            return null;
        }
    }
}
