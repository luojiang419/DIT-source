import 'dart:io';

class AleService {
  static Map<String, dynamic>? parseAleFile(String alePath) {
    try {
      final file = File(alePath);
      if (!file.existsSync()) return null;

      final content = file.readAsStringSync();
      final lines = content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

      if (lines.isEmpty) return null;

      int columnIndex = lines.indexWhere((l) => l.startsWith('Column'));
      int dataIndex = lines.indexWhere((l) => l.startsWith('Data'));

      if (columnIndex == -1 || dataIndex == -1) return null;

      final columnLine = lines[columnIndex];
      final columns = columnLine.substring(6).trim().split('\t');

      final dataLines = lines.sublist(dataIndex + 1);
      final result = <String, List<Map<String, String>>>{};

      for (var line in dataLines) {
        final values = line.split('\t');
        if (values.length != columns.length) continue;

        final row = <String, String>{};
        for (int i = 0; i < columns.length; i++) {
          row[columns[i]] = values[i];
        }

        final name = row['Name'] ?? row['Clip'] ?? '';
        if (name.isNotEmpty) {
          result.putIfAbsent(name, () => []).add(row);
        }
      }

      return {'clips': result};
    } catch (e) {
      print('ALE解析失败: $e');
      return null;
    }
  }

  static String? findAleInDirectory(String dirPath) {
    try {
      final dir = Directory(dirPath);
      final aleFiles = dir.listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.ale'))
          .toList();

      return aleFiles.isNotEmpty ? aleFiles.first.path : null;
    } catch (e) {
      return null;
    }
  }

  static Map<String, String>? getAleMetadataForClip(Map<String, dynamic>? aleData, String fileName) {
    if (aleData == null) return null;

    final clips = aleData['clips'] as Map<String, List<Map<String, String>>>?;
    if (clips == null) return null;

    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

    // 精确匹配
    if (clips.containsKey(nameWithoutExt)) {
      final list = clips[nameWithoutExt]!;
      return list.isNotEmpty ? list.first : null;
    }

    // 完整文件名匹配
    for (var entry in clips.entries) {
      if (entry.key == fileName) {
        return entry.value.isNotEmpty ? entry.value.first : null;
      }
    }

    // 模糊匹配
    Map<String, String>? fuzzyMatch;
    int fuzzyMatchLen = 0;
    for (var entry in clips.entries) {
      final aleName = entry.key;
      if (aleName.length >= 3 && nameWithoutExt.contains(aleName) && aleName.length > fuzzyMatchLen) {
        fuzzyMatch = entry.value.isNotEmpty ? entry.value.first : null;
        fuzzyMatchLen = aleName.length;
      }
    }

    return fuzzyMatch;
  }
}
