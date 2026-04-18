public abstract class Iide.LspConfig {
    public abstract string command ();

    public abstract string[] args ();

    public abstract Json.Node initialize_params (string? workspace_root, string? initial_uri);

    public abstract Json.Node? server_response_result (Json.Object response);
}
