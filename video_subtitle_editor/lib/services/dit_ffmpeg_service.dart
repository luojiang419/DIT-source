import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'ffmpeg_path_service.dart';

class DitFFmpegService {
  static const _processTimeout = Duration(seconds: 30);

  /// 使用 FFprobe 默认输出格式（key=value）解析元数据，
  /// 避免 JSON 模式下 Windows 路径含反斜杠导致的解析失败。
  static Future<Map<String, String?>> extractMetadata(String videoPath) async {
    final ffprobe = FfmpegPathService.ffprobePath;
    if (!File(ffprobe).existsSync()) {
      throw Exception('FFprobe未找到: $ffprobe');
    }

    // 不使用 -print_format json，改用默认的 key=value 输出
    final result = await Process.run(
      ffprobe,
      ['-v', 'quiet', '-show_format', '-show_streams', videoPath],
      runInShell: true,
    ).timeout(_processTimeout, onTimeout: () {
      throw Exception('FFprobe执行超时: $videoPath');
    });

    if (result.exitCode != 0) {
      throw Exception('FFprobe执行失败: ${result.stderr}');
    }

    final output = result.stdout.toString();

    // 解析默认 FFprobe 输出（分段的 key=value 格式）
    // [STREAM]...[/STREAM] 和 [FORMAT]...[/FORMAT]
    Map<String, String>? videoStream;
    Map<String, String>? audioStream;
    Map<String, String>? formatData;

    Map<String, String>? currentMap;
    bool inStream = false;
    bool inFormat = false;
    bool currentIsVideo = false;
    bool currentIsAudio = false;

    for (final line in output.split('\n')) {
      final trimmed = line.trim();

      if (trimmed == '[STREAM]') {
        inStream = true;
        currentMap = {};
        currentIsVideo = false;
        currentIsAudio = false;
        continue;
      }
      if (trimmed == '[/STREAM]') {
        if (currentMap != null) {
          if (currentIsVideo && videoStream == null) {
            videoStream = currentMap;
          } else if (currentIsAudio && audioStream == null) {
            audioStream = currentMap;
          }
        }
        inStream = false;
        currentMap = null;
        continue;
      }
      if (trimmed == '[FORMAT]') {
        inFormat = true;
        currentMap = {};
        continue;
      }
      if (trimmed == '[/FORMAT]') {
        formatData = currentMap;
        inFormat = false;
        currentMap = null;
        continue;
      }

      if (currentMap != null && trimmed.contains('=')) {
        final idx = trimmed.indexOf('=');
        final key = trimmed.substring(0, idx);
        final value = trimmed.substring(idx + 1);
        currentMap[key] = value;

        // 检测 stream 类型
        if (inStream && key == 'codec_type') {
          if (value == 'video') currentIsVideo = true;
          if (value == 'audio') currentIsAudio = true;
        }
      }
    }

    final metadata = <String, String?>{};

    // 格式信息
    if (formatData != null) {
      final duration = formatData['duration'];
      if (duration != null) {
        final seconds = double.tryParse(duration) ?? 0.0;
        final hours = (seconds / 3600).floor();
        final minutes = ((seconds % 3600) / 60).floor();
        final secs = (seconds % 60).floor();
        metadata['duration'] =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
      }
      if (formatData['bit_rate'] != null) {
        final bitRate = int.tryParse(formatData['bit_rate']!) ?? 0;
        metadata['bitrate'] = '${(bitRate ~/ 1000)} kb/s';
      }

      // TAG: 前缀的标签（如 TAG:make=Canon）
      final tags = <String, String>{};
      for (final entry in formatData.entries) {
        if (entry.key.startsWith('TAG:')) {
          tags[entry.key.substring(4)] = entry.value;
        }
      }
      metadata['cameraMake'] =
          tags['make'] ?? tags['com.apple.quicktime.make'];
      metadata['cameraModel'] =
          tags['model'] ?? tags['com.apple.quicktime.model'];
      metadata['recordStartTime'] =
          tags['creation_time'] ?? tags['com.apple.quicktime.creationdate'];
    }

    // 文件大小
    final file = File(videoPath);
    if (file.existsSync()) {
      final fileSize = await file.length();
      metadata['fileSize'] = '${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB';
    }

    // 视频流
    if (videoStream != null) {
      metadata['codec'] = videoStream['codec_name'];
      final width = videoStream['width'];
      final height = videoStream['height'];
      if (width != null && height != null) {
        metadata['resolution'] = '${width}x${height}';
      }

      final frameRate = videoStream['r_frame_rate'];
      if (frameRate != null) {
        final parts = frameRate.split('/');
        if (parts.length == 2) {
          final num = int.tryParse(parts[0]) ?? 0;
          final den = int.tryParse(parts[1]) ?? 1;
          if (den > 0) {
            metadata['frameRate'] = '${(num / den).toStringAsFixed(2)} fps';
          }
        }
      }

      metadata['colorSpace'] = videoStream['color_space'];
      metadata['colorPrimaries'] = videoStream['color_primaries'];
      metadata['colorTransfer'] = videoStream['color_transfer'];
      metadata['colorRange'] = videoStream['color_range'];
      metadata['chromaLocation'] = videoStream['chroma_location'];
      metadata['pixelFormat'] = videoStream['pix_fmt'];
    }

    // 音频流
    if (audioStream != null) {
      metadata['audioCodec'] = audioStream['codec_name'];
      metadata['audioSampleRate'] =
          audioStream['sample_rate'] != null ? '${audioStream['sample_rate']} Hz' : null;
      metadata['audioChannels'] = audioStream['channels'];
      if (audioStream['bit_rate'] != null) {
        final audioBitRate = int.tryParse(audioStream['bit_rate']!) ?? 0;
        metadata['audioBitrate'] = '${(audioBitRate ~/ 1000)} kb/s';
      }
    }

    return metadata;
  }

  static Future<String?> extractThumbnail(String videoPath, String outputDir) async {
    final ffmpeg = FfmpegPathService.ffmpegPath;
    if (!File(ffmpeg).existsSync()) {
      throw Exception('FFmpeg未找到: $ffmpeg');
    }

    await Directory(outputDir).create(recursive: true);
    final hash = md5.convert(utf8.encode(videoPath)).toString();
    final thumbnailPath = path.join(outputDir, '$hash.jpg');

    if (File(thumbnailPath).existsSync()) {
      return thumbnailPath;
    }

    var result = await Process.run(
      ffmpeg,
      ['-i', videoPath, '-ss', '00:00:01', '-vframes', '1', '-q:v', '2', '-y', thumbnailPath],
      runInShell: true,
    ).timeout(_processTimeout, onTimeout: () {
      return ProcessResult(0, 1, '', '超时');
    });

    if (result.exitCode != 0) {
      result = await Process.run(
        ffmpeg,
        ['-i', videoPath, '-ss', '00:00:00', '-vframes', '1', '-q:v', '2', '-y', thumbnailPath],
        runInShell: true,
      ).timeout(_processTimeout, onTimeout: () {
        return ProcessResult(0, 1, '', '超时');
      });
    }

    if (result.exitCode != 0) {
      if (File(thumbnailPath).existsSync()) {
        await File(thumbnailPath).delete();
      }
      return null;
    }

    return thumbnailPath;
  }
}
