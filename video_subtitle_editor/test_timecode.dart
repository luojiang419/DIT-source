import 'dart:convert';
import 'dart:io';

/// 独立测试脚本：直接读取目录下所有视频的 SMPTE 时间码
/// 运行方式：dart run test_timecode.dart
void main() async {
  const ffprobePath = r'dist\v1.0.14\ffmpeg\bin\ffprobe.exe';
  const videoDir = r'E:\data\260224-元数据脚本测试\1_Video\220822shipin';

  final dir = Directory(videoDir);
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => ['.mp4', '.mov', '.mxf', '.avi']
          .any((ext) => f.path.toLowerCase().endsWith(ext)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  print('找到 ${files.length} 个视频文件\n');
  print('${'文件名'.padRight(16)} ${'SMPTE'.padRight(14)} ${'timelineStart(ms)'.padRight(20)} ${'timelineEnd(ms)'.padRight(18)} 间隔(ms)');
  print('-' * 85);

  int? originMs;
  final results2 = <Map<String, dynamic>>[];

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final result = await _extractTimecode(ffprobePath, f.path);
    final durResult = await Process.run(ffprobePath, [
      '-v', 'quiet', '-show_entries', 'stream=duration:stream=codec_type',
      '-of', 'csv=p=0', f.path,
    ]);
    double durSec = 0;
    for (final line in (durResult.stdout as String).split('\n')) {
      final parts = line.trim().split(',');
      if (parts.length >= 2 && parts[0] == 'video') {
        durSec = double.tryParse(parts[1]) ?? 0;
        break;
      }
    }
    final durationMs = (durSec * 1000).round();
    if (result != null) {
      originMs ??= result['ms'] as int;
      results2.add({...result, 'name': name, 'durationMs': durationMs});
    }
  }

  int? prevEnd;
  for (final r in results2) {
    final startMs = (r['ms'] as int) - originMs!;
    final endMs = startMs + (r['durationMs'] as int);
    final gap = prevEnd != null ? startMs - prevEnd! : 0;
    final overlap = gap < 0 ? ' *** 重叠${-gap}ms ***' : '';
    print('${(r['name'] as String).padRight(16)} ${(r['raw'] as String).padRight(14)} ${startMs.toString().padRight(20)} ${endMs.toString().padRight(18)} $gap$overlap');
    prevEnd = endMs;
  }
}

Future<Map<String, dynamic>?> _extractTimecode(
    String ffprobePath, String filePath) async {
  try {
    // 只提取需要的字段，完全避开 filename 中文乱码破坏 JSON 的问题
    final result = await Process.run(ffprobePath, [
      '-v', 'quiet',
      '-print_format', 'json',
      '-show_entries',
      'stream_tags=timecode,creation_time:stream=r_frame_rate,avg_frame_rate,codec_type:format_tags=creation_time',
      filePath,
    ]);

    if (result.exitCode != 0) {
      print('  ffprobe error: ${result.stderr}');
      return null;
    }

    final rawOutput = result.stdout as String;
    final json = jsonDecode(rawOutput) as Map<String, dynamic>;
    final streams = json['streams'] as List<dynamic>? ?? [];

    // 优先级1：stream timecode (SMPTE)
    for (final stream in streams) {
      final s = stream as Map<String, dynamic>;
      final tags = s['tags'] as Map<String, dynamic>?;
      if (tags == null) continue;
      final tc = tags['timecode'] as String?;
      if (tc == null) continue;

      final rFrameRate = (s['r_frame_rate'] as String?)?.isNotEmpty == true
          ? s['r_frame_rate'] as String
          : s['avg_frame_rate'] as String?;
      final fps = _parseFps(rFrameRate);
      final ms = _parseSmpte(tc, fps);
      if (ms != null) {
        return {'raw': tc, 'ms': ms, 'source': 'SMPTE(stream:${s['codec_type']})'};
      }
    }

    // 优先级2：format creation_time
    final formatTags =
        (json['format'] as Map<String, dynamic>?)?['tags'] as Map<String, dynamic>?;
    if (formatTags != null) {
      final ct = formatTags['creation_time'] as String?;
      if (ct != null) {
        final ms = _parseIso8601(ct);
        if (ms != null) {
          return {'raw': ct, 'ms': ms, 'source': 'creation_time'};
        }
      }
    }

    return {'raw': '无', 'ms': 0, 'source': '未找到'};
  } catch (e) {
    print('  exception: $e');
    return null;
  }
}

int? _parseSmpte(String s, double fps) {
  try {
    final clean = s.replaceAll(';', ':');
    final parts = clean.split(':');
    if (parts.length < 3) return null;
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final sec = int.parse(parts[2]);
    final frames = parts.length >= 4 ? int.parse(parts[3]) : 0;
    final frameMs = fps > 0 ? (frames / fps * 1000).floor() : 0;
    return h * 3600000 + m * 60000 + sec * 1000 + frameMs;
  } catch (_) {
    return null;
  }
}

int? _parseIso8601(String s) {
  try {
    final dt = DateTime.parse(s).toLocal();
    return dt.hour * 3600000 + dt.minute * 60000 + dt.second * 1000 + dt.millisecond;
  } catch (_) {
    return null;
  }
}

double _parseFps(String? s) {
  if (s == null || s.isEmpty) return 25.0;
  if (s.contains('/')) {
    final parts = s.split('/');
    final n = double.tryParse(parts[0]) ?? 0;
    final d = double.tryParse(parts[1]) ?? 1;
    return d != 0 ? n / d : 25.0;
  }
  return double.tryParse(s) ?? 25.0;
}
