import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ffmpeg_path_service.dart';

class WaveformService {
  // 动态解析 ffmpeg 路径
  static String get _ffmpegPath => FfmpegPathService.ffmpegPath;
  
  // Track all running ffmpeg processes globally by audio path
  static final Map<String, Process> _globalProcesses = {};
  
  // Track processes started by THIS service instance
  final Set<String> _localProcessKeys = {};

  // Extract PCM data at a low sample rate (e.g., 100 samples/sec)
  // Returns a List<double> where each value is a normalized amplitude (0.0 to 1.0)
  Future<List<double>> extractWaveform(
    String audioPath, {
    int samplesPerSecond = 100,
  }) async {
    final cacheFile = await _cacheFileFor(audioPath, samplesPerSecond);
    if (await cacheFile.exists()) {
      return _readFromCache(cacheFile);
    }

    final processKey = audioPath;
    
    // Kill any existing process for this audio (global check)
    if (_globalProcesses.containsKey(processKey)) {
      _globalProcesses[processKey]?.kill();
      _globalProcesses.remove(processKey);
    }

    // Run ffmpeg to extract raw PCM data
    // -ac 1: mono
    // -ar $samplesPerSecond: sample rate
    // -f f32le: 32-bit float little-endian
    // -c:a pcm_f32le
    final args = [
      '-y',
      '-i',
      audioPath,
      '-vn', // No video
      '-ac',
      '1',
      '-ar',
      '$samplesPerSecond',
      '-f',
      'f32le',
      '-acodec', 
      'pcm_f32le',
      cacheFile.path,
    ];

    try {
      final process = await Process.start(_ffmpegPath, args);
      _globalProcesses[processKey] = process;
      _localProcessKeys.add(processKey);
      
      final exitCode = await process.exitCode;
      _globalProcesses.remove(processKey);
      _localProcessKeys.remove(processKey);
      
      if (exitCode != 0) {
        return [];
      }
      return _readFromCache(cacheFile);
    } catch (e) {
      _globalProcesses.remove(processKey);
      _localProcessKeys.remove(processKey);
      return [];
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

  Future<File> _cacheFileFor(String path, int samplesPerSecond) async {
    final temp = Directory.systemTemp.path;
    final name = _safeHash('$path|$samplesPerSecond');
    final dir = Directory(
      '$temp${Platform.pathSeparator}video_subtitle_editor_cache${Platform.pathSeparator}waveforms',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$name.bin');
  }

  Future<List<double>> _readFromCache(File file) async {
    final bytes = await file.readAsBytes();
    // Ensure we have a multiple of 4 bytes for Float32
    final length = bytes.length - (bytes.length % 4);
    final buffer = bytes.buffer.asByteData(0, length);
    
    final result = <double>[];
    for (var i = 0; i < length; i += 4) {
      final val = buffer.getFloat32(i, Endian.little);
      result.add(val.abs().clamp(0.0, 1.0));
    }
    return result;
  }

  String _safeHash(String input) {
    final bytes = utf8.encode(input);
    final digest = bytes.fold<int>(0, (p, e) => (p * 31 + e) & 0x7fffffff);
    return digest.toRadixString(16);
  }

  /// Finds the best time offset (in milliseconds) to align [target] waveform with [reference].
  /// [samplesPerSecond] must be the same for both waveforms.
  /// A positive result means [target] starts LATER than [reference] in the source media.
  int findOffset(List<double> reference, List<double> target, int samplesPerSecond) {
    if (reference.isEmpty || target.isEmpty) return 0;

    // To optimize, we use a sliding window correlation.
    // We'll search for the target within the reference.
    // Since this is for sync, we might only need to check a certain range, 
    // but for now let's do a full cross-correlation for simplicity on small low-res data.
    
    int bestOffsetSamples = 0;
    double maxCorrelation = -1.0;

    // Limit search range to prevent O(N^2) explosion on very long clips
    // Usually, we don't expect more than 10 minutes of offset
    final maxSearchOffset = 600 * samplesPerSecond; 
    
    // We only take a representative sample of the target to speed up (e.g., first 30s)
    final targetSampleLength = 30 * samplesPerSecond;
    final targetSample = target.sublist(0, target.length < targetSampleLength ? target.length : targetSampleLength);

    final limit = reference.length - targetSample.length;
    final searchEnd = limit < maxSearchOffset ? limit : maxSearchOffset;

    for (int s = 0; s <= searchEnd; s++) {
      double correlation = 0;
      for (int i = 0; i < targetSample.length; i++) {
        correlation += reference[s + i] * targetSample[i];
      }
      
      if (correlation > maxCorrelation) {
        maxCorrelation = correlation;
        bestOffsetSamples = s;
      }
    }

    // Convert samples to ms
    return (bestOffsetSamples * 1000 ~/ samplesPerSecond);
  }
}
