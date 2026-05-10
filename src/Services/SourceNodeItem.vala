/*
*/
public struct Iide.SourceNodePosition {
    public uint32 row;
    public uint32 column;
}

public struct Iide.SourceNodeItem {
    public string name;
    public string type;
    public SourceNodePosition start_point;
    public Gee.List<SourceNodeItem?> siblings; // Добавляем список соседей
    public Gee.List<SourceNodeItem?> children;
}
