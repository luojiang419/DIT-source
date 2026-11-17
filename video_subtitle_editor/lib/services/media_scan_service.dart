
import 'dart:io';

import '../models/media_file.dart';
import 'ffmpeg_path_service.dart';

class MediaScanService {
  static const _videoExtensions = <String>{
    '.mp4',
    '.mov',
    '.mxf',
    '.avi',
    '.mkv',
    '.mpg',
    '.mpeg',
    '.m4v',
    '.wmv',
  };

  static const _audioExtensions = <String>{
    '.wav',
    '.mp3',
    '.aac',
    '.flac',
    '.m4a',
    '.ogg',
    '.wma',
  };

  // 动态解析 ffprobe 路径（优先使用 exe 同级 ffmpeg/bin/，fallback 到开发机绝对路径）
  static String get _ffprobePath => FfmpegPathService.ffprobePath;

  Future<List<MediaFile>> scanVideos(String rootDir) async {
    return _scan(rootDir, _videoExtensions);
  }

  Future<List<MediaFile>> scanAudios(String rootDir) async {
    return _scan(rootDir, _audioExtensions);
  }

  Future<List<MediaFile>> _scan(String rootDir, Set<String> extensions) async {
    final dir = Directory(rootDir);
    if (!await dir.exists()) return const [];

    final results = <MediaFile>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      final lower = path.toLowerCase();
      final dot = lower.lastIndexOf('.');
      if (dot <= 0) continue;
      final ext = lower.substring(dot);
      if (!extensions.contains(ext)) continue;

      final name = _basename(path);
      results.add(MediaFile(path: path, name: name));
    }

    results.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return results;
  }

  Future<int> getDurationMs(String filePath) async {
    try {
      final result = await Process.run(
        _ffprobePath,
        [
          '-v',
          'error',
          '-show_entries',
          'format=duration',
          '-of',
          'default=noprint_wrappers=1:nokey=1',
          filePath,
        ],
      );

      if (result.exitCode != 0) return 0;
      final output = (result.stdout as String).trim();
      if (output.isEmpty) return 0;
      final seconds = double.tryParse(output) ?? 0.0;
      return (seconds * 1000).toInt();
    } catch (e) {
      // Fallback or log error
      return 0;
    }
  }

  Future<double> getFrameRate(String filePath) async {
    try {
      final result = await Process.run(
        _ffprobePath,
        [
          '-v',
          'error',
          '-select_streams',
          'v:0',
          '-show_entries',
          'stream=r_frame_rate',
          '-of',
          'default=noprint_wrappers=1:nokey=1',
          filePath,
        ],
      );

      if (result.exitCode != 0) return 30.0;
      final output = (result.stdout as String).trim();
      if (output.isEmpty) return 30.0;
      
      // Output format is usually "num/den", e.g., "30000/1001" or "25/1"
      if (output.contains('/')) {
        final parts = output.split('/');
        if (parts.length == 2) {
          final num = double.tryParse(parts[0]) ?? 0;
          final den = double.tryParse(parts[1]) ?? 1;
          if (den != 0) return num / den;
        }
      }
      
      return double.tryParse(output) ?? 30.0;
    } catch (e) {
      return 30.0;
    }
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }
}
