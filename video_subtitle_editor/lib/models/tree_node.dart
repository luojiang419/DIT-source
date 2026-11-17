class TreeNode {
  final String name;
  final String path;
  bool isDirectory;
  final List<TreeNode> children;
  final int? videoId;

  TreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    List<TreeNode>? children,
    this.videoId,
  }) : children = children ?? [];

  bool get hasChildren => children.isNotEmpty;

  TreeNode copyWith({
    String? name,
    String? path,
    bool? isDirectory,
    List<TreeNode>? children,
    int? videoId,
  }) {
    return TreeNode(
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      children: children ?? this.children,
      videoId: videoId ?? this.videoId,
    );
  }
}
