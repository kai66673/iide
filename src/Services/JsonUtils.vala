namespace Iide {
    public string json_node_to_string (Json.Node node) {
        var generator = new Json.Generator ();
        generator.set_root (node);
        return generator.to_data (null);
    }

    public string json_object_to_string (Json.Object? obj) {
        if (obj == null)return "<<null>>";
        var node = new Json.Node (Json.NodeType.OBJECT);
        node.set_object (obj);
        return json_node_to_string (node);
    }
}
