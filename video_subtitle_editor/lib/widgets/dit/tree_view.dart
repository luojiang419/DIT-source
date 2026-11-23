import 'package:flutter/material.dart';
import '../../models/tree_node.dart';

class TreeView extends StatefulWidget {
  final TreeNode root;
  final Function(int videoId)? onVideoSelected;

  const TreeView({
    super.key,
    required this.root,
    this.onVideoSelected,
  });

  @override
  State<TreeView> createState() => _TreeViewState();
}

class _TreeViewState extends State<TreeView> {
  final Set<String> _expandedNodes = {};

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: _buildNode(widget.root, 0),
    );
  }

  Widget _buildNode(TreeNode node, int level) {
    final isExpanded = _expandedNodes.contains(node.path);
    final hasChildren = node.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            if (node.isDirectory && hasChildren) {
              setState(() {
                if (isExpanded) {
                  _expandedNodes.remove(node.path);
                } else {
                  _expandedNodes.add(node.path);
                }
              });
            } else if (node.videoId != null && widget.onVideoSelected != null) {
              widget.onVideoSelected!(node.videoId!);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(left: level * 20.0, top: 4, bottom: 4),
            child: Row(
              children: [
                if (node.isDirectory && hasChildren)
                  Icon(
                    isExpanded ? Icons.folder_open : Icons.folder,
                    size: 16,
                    color: Colors.amber,
                  )
                else if (node.isDirectory)
                  const Icon(Icons.folder, size: 16, color: Colors.grey)
                else
                  const Icon(Icons.video_file, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded && hasChildren)
          ...node.children.map((child) => _buildNode(child, level + 1)),
      ],
    );
  }
}
