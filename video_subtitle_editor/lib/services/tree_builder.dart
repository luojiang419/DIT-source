import 'package:path/path.dart' as path;
import '../models/tree_node.dart';
import '../models/video_metadata.dart';

class TreeBuilder {
  static TreeNode buildFromVideos(List<VideoMetadata> videos, String rootPath) {
    final root = TreeNode(
      name: path.basename(rootPath),
      path: rootPath,
      isDirectory: true,
      children: [],
    );

    final Map<String, TreeNode> nodeMap = {rootPath: root};

    for (var video in videos) {
      String relativePath;
      try {
        relativePath = video.relativePath ?? path.relative(video.filePath, from: rootPath);
      } catch (_) {
        relativePath = video.filePath;
      }
      final parts = relativePath.replaceAll('\\', '/').split('/');

      TreeNode currentNode = root;

      for (int i = 0; i < parts.length; i++) {
        final part = parts[i];
        if (part.isEmpty) continue;
        final isLastPart = i == parts.length - 1;
        final childPath = i == 0
            ? path.join(rootPath, part)
            : path.join(currentNode.path, part);

        if (!nodeMap.containsKey(childPath)) {
          final newNode = TreeNode(
            name: part,
            path: childPath,
            isDirectory: !isLastPart,
            videoId: isLastPart ? video.id : null,
            children: [],
          );
          currentNode.children.add(newNode);
          nodeMap[childPath] = newNode;
        } else {
          final existing = nodeMap[childPath]!;
          if (!isLastPart && !existing.isDirectory) {
            existing.isDirectory = true;
          }
        }

        currentNode = nodeMap[childPath]!;
      }
    }

    return root;
  }
}
