import 'dart:io';

class FileInfo {
  final String path;
  final String name;
  final String extension;
  final int size;
  final DateTime modifiedTime;
  bool isSelected;

  FileInfo({
    required this.path,
    required this.name,
    required this.extension,
    required this.size,
    required this.modifiedTime,
    this.isSelected = false,
  });

  factory FileInfo.fromFile(File file) {
    final stat = file.statSync();
    final name = file.path.split(RegExp(r'[/\\]')).last;
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    return FileInfo(
      path: file.path,
      name: name,
      extension: extension,
      size: stat.size,
      modifiedTime: stat.modified,
    );
  }

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(2)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class FileStats {
  final int totalFiles;
  final int totalFolders;
  final int totalSize;
  final Map<String, int> extensionCount;

  FileStats({
    required this.totalFiles,
    required this.totalFolders,
    required this.totalSize,
    required this.extensionCount,
  });

  String get totalSizeFormatted {
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(2)} KB';
    if (totalSize < 1024 * 1024 * 1024) return '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
