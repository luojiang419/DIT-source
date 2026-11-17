import 'dart:convert';
import 'dart:io';

import 'ffmpeg_path_service.dart';

class ThumbnailService {
  // 动态解析 ffmpeg 路径
  static String get _ffmpegPath => FfmpegPathService.ffmpegPath;
  
  // Track all running ffmpeg processes globally by video path
  static final Map<String, Process> _globalProcesses = {};
  
  // Track processes started by THIS service instance
  final Set<String> _localProcessKeys = {};

  Future<List<File>> ensureThumbnails(
    String videoPath, {
    double fps = 1.0,
    int height = 160,
    int maxFrames = 300,
  }) async {
    final dir = await _cacheDirFor(videoPath, fps, height);
    if (await dir.exists()) {
      final files = await _listImages(dir);
      if (files.isNotEmpty) return files;
    } else {
      await dir.create(recursive: true);
    }

    final processKey = videoPath;
    
    // Kill any existing process for this video (global check)
    if (_globalProcesses.containsKey(processKey)) {
      _globalProcesses[processKey]?.kill();
      _globalProcesses.remove(processKey);
    }

    final args = [
      '-y',
      '-i',
      videoPath,
      '-vf',
      'fps=$fps,scale=-1:$height',
      '-frames:v',
      '$maxFrames',
      '${dir.path}${Platform.pathSeparator}thumb_%05d.jpg',
    ];
    
    try {
      final process = await Process.start(_ffmpegPath, args);
      _globalProcesses[processKey] = process;
      _localProcessKeys.add(processKey);
      
      final exitCode = await process.exitCode;
      _globalProcesses.remove(processKey);
      _localProcessKeys.remove(processKey);
      
      if (exitCode != 0) {
        return const [];
      }
      return _listImages(dir);
    } catch (e) {
      _globalProcesses.remove(processKey);
      _localProcessKeys.remove(processKey);
      return const [];
    }
  }

  void cancelAll() {
    for (final key in _localProcessKeys) {
      if (_globalProcesses.containsKey(key)) {
        _globalProcesses[key]?.kill();
        _globalProcesses.remove(key);
      }
    }
    _localProcessKeys.clear();
  }

  Future<Directory> _cacheDirFor(String videoPath, double fps, int height) async {
    final temp = Directory.systemTemp.path;
    final name = _safeHash('$videoPath|$fps|$height');
    final root = Directory(
      '$temp${Platform.pathSeparator}video_subtitle_editor_cache${Platform.pathSeparator}thumbnails${Platform.pathSeparator}$name',
    );
    return root;
  }

  Future<List<File>> _listImages(Directory dir) async {
    final entries = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.jpg'))
        .cast<File>()
        .toList();
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  String _safeHash(String input) {
    final bytes = utf8.encode(input);
    final digest = bytes.fold<int>(0, (p, e) => (p * 31 + e) & 0x7fffffff);
    return digest.toRadixString(16);
  }
}

