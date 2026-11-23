
import 'dart:io';
import '../models/timeline_model.dart';

class SubtitleService {
  /// Parses an SRT file into a list of TimelineClips.
  Future<List<TimelineClip>> parseSrt(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Subtitle file not found: $filePath');
    }

    final lines = await file.readAsLines();
    final clips = <TimelineClip>[];
    
    String? currentText;
    int? currentStart;
    int? currentEnd;
    
    // Regex for timestamp: 00:00:01,000 --> 00:00:04,000
    final timeRegex = RegExp(r'(\d{2}):(\d{2}):(\d{2}),(\d{3})\s-->\s(\d{2}):(\d{2}):(\d{2}),(\d{3})');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      
      if (line.isEmpty) {
        // End of a block (or just empty line)
        if (currentStart != null && currentEnd != null && currentText != null) {
          clips.add(TimelineClip(
            filePath: filePath,
            fileName: file.uri.pathSegments.last,
            timelineStartMs: currentStart,
            durationMs: currentEnd - currentStart,
            mediaIndex: -1, // Not a media player item
            text: currentText,
          ));
          currentStart = null;
          currentEnd = null;
          currentText = null;
        }
        continue;
      }

      // Check if it's an index number (just digits)
      if (int.tryParse(line) != null && currentStart == null) {
        continue; // Skip index
      }

      // Check if it's a timestamp line
      final match = timeRegex.firstMatch(line);
      if (match != null) {
        currentStart = _parseTime(match.group(1)!, match.group(2)!, match.group(3)!, match.group(4)!);
        currentEnd = _parseTime(match.group(5)!, match.group(6)!, match.group(7)!, match.group(8)!);
        currentText = ''; // Start collecting text
        continue;
      }

      // If we have a start time, this must be text
      if (currentStart != null) {
        if (currentText!.isNotEmpty) {
          currentText = '$currentText\n$line';
        } else {
          currentText = line;
        }
      }
    }

    // Add last block if file doesn't end with empty line
    if (currentStart != null && currentEnd != null && currentText != null) {
      clips.add(TimelineClip(
        filePath: filePath,
        fileName: file.uri.pathSegments.last,
        timelineStartMs: currentStart,
        durationMs: currentEnd - currentStart,
        mediaIndex: -1,
        text: currentText,
      ));
    }

    return clips;
  }

  int _parseTime(String h, String m, String s, String ms) {
    return int.parse(h) * 3600000 +
           int.parse(m) * 60000 +
           int.parse(s) * 1000 +
           int.parse(ms);
  }
}
