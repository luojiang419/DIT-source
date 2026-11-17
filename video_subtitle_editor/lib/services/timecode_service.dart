import 'dart:convert';
import 'dart:io';

import '../models/timeline_model.dart';
import 'ffmpeg_path_service.dart';

/// 从媒体文件中提取源时间码（24小时制绝对时间码）
class TimecodeService {
  static String get _ffprobePath => FfmpegPathService.ffprobePath;

  /// 提取文件的源时间码，返回 SourceTimecode
  /// 按优先级尝试：creation_time → timecode轨道 → 文件修改时间
  Future<SourceTimecode?> extractTimecode(String filePath, int durationMs) async {
    try {
      final result = await Process.run(
        _ffprobePath,
        [
          '-v', 'quiet',
          '-print_format', 'json',
          '-show_entries',
          'stream_tags=timecode,creation_time:stream=r_frame_rate,avg_frame_rate,codec_type:format_tags=creation_time',
          filePath,
        ],
      );

      if (result.exitCode != 0) {
        return _fallbackToFileTime(filePath, durationMs);
      }

      // 只提取了必要字段，不含 filename，避免中文路径乱码破坏 JSON 解析
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;

      final streams = json['streams'] as List<dynamic>? ?? [];

      // 优先级1：stream_tags.timecode（SMPTE格式，最精确的源时间码）
      // 专业摄影机（如 Blackmagic、Sony、Canon）会在 video stream 或 tmcd stream 写入 SMPTE 时间码
      for (final stream in streams) {
        final streamMap = stream as Map<String, dynamic>;
        final tags = streamMap['tags'] as Map<String, dynamic>?;
        if (tags != null) {
          final timecode = tags['timecode'] as String?;
          if (timecode != null) {
            // 优先从 video stream 取帧率，tmcd stream 的 avg_frame_rate 也可用
            final rFrameRate = (streamMap['r_frame_rate'] as String?)?.isNotEmpty == true
                ? streamMap['r_frame_rate'] as String
                : streamMap['avg_frame_rate'] as String?;
            final fps = _parseFrameRate(rFrameRate);
            final ms = _parseSmpteToMs(timecode, fps);
            if (ms != null) {
              return SourceTimecode(filePath: filePath, startMs: ms, durationMs: durationMs);
            }
          }
        }
      }

      // 优先级2：format_tags.creation_time（ISO 8601，记录的是录制日期时间，精度到秒）
      final formatTags = (json['format'] as Map<String, dynamic>?)?['tags'] as Map<String, dynamic>?;
      if (formatTags != null) {
        final creationTime = formatTags['creation_time'] as String?;
        if (creationTime != null) {
          final ms = _parseIso8601ToMs(creationTime);
          if (ms != null) {
            return SourceTimecode(filePath: filePath, startMs: ms, durationMs: durationMs);
          }
        }
      }

      // 优先级3：文件修改时间兜底
      return _fallbackToFileTime(filePath, durationMs);
    } catch (e) {
      return _fallbackToFileTime(filePath, durationMs);
    }
  }

  /// 批量提取多个文件的源时间码
  Future<Map<String, SourceTimecode>> extractTimecodes(
    List<String> filePaths,
    Map<String, int> durations, // filePath → durationMs
  ) async {
    final result = <String, SourceTimecode>{};
    for (final path in filePaths) {
      final tc = await extractTimecode(path, durations[path] ?? 0);
      if (tc != null) {
        result[path] = tc;
      }
    }
    return result;
  }

  // ── 私有解析方法 ──────────────────────────────────────────────

  /// 解析 ISO 8601 时间字符串为当天毫秒数（24h制）
  /// 例：2024-03-15T14:32:15.480000Z → 14*3600000 + 32*60000 + 15480
  int? _parseIso8601ToMs(String s) {
    try {
      final dt = DateTime.parse(s).toLocal();
      return _timeToMs(dt.hour, dt.minute, dt.second, dt.millisecond);
    } catch (_) {
      return null;
    }
  }

  /// 解析 SMPTE 时间码为毫秒
  /// 格式：HH:MM:SS:FF 或 HH:MM:SS;FF（drop frame）
  int? _parseSmpteToMs(String s, double fps) {
    try {
      final clean = s.replaceAll(';', ':');
      final parts = clean.split(':');
      if (parts.length < 3) return null;
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final sec = int.parse(parts[2]);
      final frames = parts.length >= 4 ? int.parse(parts[3]) : 0;
      // 帧号转毫秒用截断（floor）而非四舍五入，避免与视频时长产生累积误差
      final frameMs = fps > 0 ? (frames / fps * 1000).floor() : 0;
      return _timeToMs(h, m, sec, frameMs);
    } catch (_) {
      return null;
    }
  }

  /// 解析帧率字符串，如 "24000/1001" 或 "25/1"
  double _parseFrameRate(String? s) {
    if (s == null || s.isEmpty) return 25.0;
    if (s.contains('/')) {
      final parts = s.split('/');
      final num = double.tryParse(parts[0]) ?? 0;
      final den = double.tryParse(parts[1]) ?? 1;
      return den != 0 ? num / den : 25.0;
    }
    return double.tryParse(s) ?? 25.0;
  }

  int _timeToMs(int h, int m, int s, int ms) =>
      h * 3600000 + m * 60000 + s * 1000 + ms;

  /// 使用文件修改时间作为兜底
  SourceTimecode? _fallbackToFileTime(String filePath, int durationMs) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final modified = file.lastModifiedSync();
      // 用文件修改时间的时分秒作为近似源时间码
      final ms = _timeToMs(modified.hour, modified.minute, modified.second, modified.millisecond);
      return SourceTimecode(filePath: filePath, startMs: ms, durationMs: durationMs);
    } catch (_) {
      return null;
    }
  }
}
