class SrtParserService {
  static List<Map<String, dynamic>> parseSRT(String content) {
    final subtitles = <Map<String, dynamic>>[];

    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split('\n\n').where((b) => b.trim().isNotEmpty);

    for (var block in blocks) {
      final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.length < 2) continue;

      int timeLineIndex = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timeLineIndex = i;
          break;
        }
      }
      if (timeLineIndex < 0) continue;

      final timeLine = lines[timeLineIndex];
      final timeMatch = RegExp(
              r'(\d{2}):(\d{2}):(\d{2})[,\.](\d{2,3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,\.](\d{2,3})')
          .firstMatch(timeLine);
      if (timeMatch == null) continue;

      final startTime = (int.tryParse(timeMatch.group(1)!) ?? 0) * 3600 +
          (int.tryParse(timeMatch.group(2)!) ?? 0) * 60 +
          (int.tryParse(timeMatch.group(3)!) ?? 0) +
          (int.tryParse(timeMatch.group(4)!) ?? 0) / (timeMatch.group(4)!.length == 2 ? 100 : 1000);
      final endTime = (int.tryParse(timeMatch.group(5)!) ?? 0) * 3600 +
          (int.tryParse(timeMatch.group(6)!) ?? 0) * 60 +
          (int.tryParse(timeMatch.group(7)!) ?? 0) +
          (int.tryParse(timeMatch.group(8)!) ?? 0) / (timeMatch.group(8)!.length == 2 ? 100 : 1000);

      final text = lines.sublist(timeLineIndex + 1).join('\n');

      final indexStr = timeLineIndex > 0 ? lines[timeLineIndex - 1] : '';
      final index = int.tryParse(indexStr.trim()) ?? subtitles.length + 1;

      subtitles.add({'index': index, 'startTime': startTime, 'endTime': endTime, 'text': text});
    }

    return subtitles;
  }
}
