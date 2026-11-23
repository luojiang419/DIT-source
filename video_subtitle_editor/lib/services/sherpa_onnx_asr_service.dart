import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/timeline_model.dart';
import 'ffmpeg_path_service.dart';
import 'sherpa_onnx_path_service.dart';

/// sherpa-onnx ASR 识别结果
class SherpaOnnxResult {
  const SherpaOnnxResult({
    required this.clips,
    required this.durationMs,
    required this.rawText,
    this.language,
    this.emotion,
  });

  /// 识别出的字幕片段列表（按时间戳分段）
  final List<TimelineClip> clips;

  /// 音频总时长（毫秒）
  final int durationMs;

  /// 原始识别文本
  final String rawText;

  /// 检测到的语言
  final String? language;

  /// 检测到的情感
  final String? emotion;
}

/// sherpa-onnx ASR 语音识别服务
///
/// 封装 sherpa-onnx-offline.exe 调用，支持 SenseVoice 等模型。
/// SenseVoice 高精度中文语音识别引擎，自动检测语言。
///
/// 处理流程：FFmpeg 提取 16kHz WAV → sherpa-onnx-offline 识别 → 解析 JSON 输出
class SherpaOnnxAsrService {
  /// 分片时长（毫秒），用于长音频分片处理
  static const int _segmentDurationMs = 300000; // 5 分钟

  // ==================== GPU 自动检测 ====================

  /// 是否检测到 NVIDIA GPU（缓存结果）
  static bool? _hasNvidiaGpu;

  /// CUDA provider 是否可用（已测试）
  static bool? _cudaAvailable;

  /// 检测系统是否有 NVIDIA GPU
  static Future<bool> hasNvidiaGpu() async {
    if (_hasNvidiaGpu != null) return _hasNvidiaGpu!;
    try {
      final result = await Process.run(
        'nvidia-smi',
        ['--query-gpu=name', '--format=csv,noheader'],
      );
      _hasNvidiaGpu = result.exitCode == 0;
      if (_hasNvidiaGpu!) {
        final name = (result.stdout as String?)?.trim() ?? 'Unknown';
        print('[SherpaOnnx] 检测到 NVIDIA GPU: $name');
      }
    } catch (_) {
      _hasNvidiaGpu = false;
    }
    return _hasNvidiaGpu!;
  }

  /// 检测 CUDA provider 是否可用
  ///
  /// 检查条件：
  /// 1. 系统有 NVIDIA GPU
  /// 2. sherpa-onnx\bin\ 目录存在 CUDA 相关 DLL
  /// 3. (可选) 运行快速测试验证 CUDA 能否初始化
  static Future<bool> detectCudaSupport() async {
    if (_cudaAvailable != null) return _cudaAvailable!;

    // 条件1：必须有 NVIDIA GPU
    if (!await hasNvidiaGpu()) {
      print('[SherpaOnnx] 未检测到 NVIDIA GPU，CUDA 不可用');
      _cudaAvailable = false;
      return false;
    }

    // 条件2：检查 CUDA DLL 是否存在
    final binDir = p.dirname(SherpaOnnxPathService.offlineExePath);
    final cudaDll = File(p.join(binDir, 'cudart64_12.dll'));
    final cudaEpDll = File(p.join(binDir, 'onnxruntime_providers_cuda.dll'));

    if (!cudaDll.existsSync() || !cudaEpDll.existsSync()) {
      print('[SherpaOnnx] CUDA DLL 缺失，CUDA 不可用');
      print('[SherpaOnnx]   cudart64_12.dll: ${cudaDll.existsSync()}');
      print('[SherpaOnnx]   onnxruntime_providers_cuda.dll: ${cudaEpDll.existsSync()}');
      _cudaAvailable = false;
      return false;
    }

    // 条件3：检查 cuDNN DLL（CUDA EP 必需）
    final cudnnDll = File(p.join(binDir, 'cudnn64_9.dll'));
    final cudnnOpsDll = File(p.join(binDir, 'cudnn_ops64_9.dll'));
    if (!cudnnDll.existsSync() || !cudnnOpsDll.existsSync()) {
      print('[SherpaOnnx] cuDNN DLL 缺失，CUDA provider 将无法初始化');
      print('[SherpaOnnx]   cudnn64_9.dll: ${cudnnDll.existsSync()}');
      print('[SherpaOnnx]   cudnn_ops64_9.dll: ${cudnnOpsDll.existsSync()}');
      print('[SherpaOnnx] 请下载 cuDNN 9.x for CUDA 12.x 并将 DLL 复制到: $binDir');
      _cudaAvailable = false;
      return false;
    }

    // 条件4：检查 cuFFT DLL（CUDA EP 必需）
    final cufftDll = File(p.join(binDir, 'cufft64_11.dll'));
    if (!cufftDll.existsSync()) {
      print('[SherpaOnnx] cufft64_11.dll 缺失，CUDA provider 将无法初始化');
      _cudaAvailable = false;
      return false;
    }

    // 所有条件满足，CUDA 应该可用
    print('[SherpaOnnx] CUDA 环境检测通过，GPU 加速可用');
    _cudaAvailable = true;
    return true;
  }

  /// 自动选择最佳 provider
  ///
  /// 优先使用 CUDA，不可用时回退到 CPU
  static Future<String> autoSelectProvider() async {
    final cudaOk = await detectCudaSupport();
    if (cudaOk) {
      print('[SherpaOnnx] 使用 GPU (CUDA) 加速');
      return 'cuda';
    }
    print('[SherpaOnnx] 使用 CPU 模式');
    return 'cpu';
  }

  /// 重置 CUDA 检测缓存（用于设置变更后重新检测）
  static void resetGpuCache() {
    _cudaAvailable = null;
    // 不重置 _hasNvidiaGpu，GPU 硬件不会变
  }

  // ==================== 识别方法 ====================

  /// 识别单个文件的字幕
  ///
  /// [filePath] 音频或视频文件路径
  /// [modelVariant] 模型变体名：'sense-voice-small'
  /// [language] 语言代码：'zh', 'en', 'ja', 'ko', 'yue', 'auto'
  /// [useItn] 是否启用逆文本归一化（数字转汉字等）
  /// [provider] 推理后端：'auto'（自动选择）、'cpu' 或 'cuda'
  /// [numThreads] CPU 线程数
  /// [timelineStartMs] 字幕在时间轴上的起始偏移
  /// [useVad] 是否使用 VAD 预处理（默认 true，不可用时自动回退）
  /// [onProgress] 进度回调 0.0~1.0
  Future<SherpaOnnxResult> recognize({
    required String filePath,
    required String modelVariant,
    String language = 'zh',
    bool useItn = true,
    String provider = 'auto',
    int numThreads = 8,
    int timelineStartMs = 0,
    bool useVad = true,
    void Function(double progress)? onProgress,
  }) async {
    if (!SherpaOnnxPathService.isAvailable) {
      throw Exception('sherpa-onnx-offline.exe 未找到，请检查 sherpa-onnx 目录');
    }
    if (!SherpaOnnxPathService.isModelAvailable(modelVariant)) {
      throw Exception('模型 $modelVariant 未找到，请先下载模型');
    }

    // 自动选择 provider
    String effectiveProvider = provider;
    if (provider == 'auto') {
      effectiveProvider = await autoSelectProvider();
    }

    // Step 1: 用 FFmpeg 提取 16kHz WAV
    onProgress?.call(0.05);
    final wavPath = await _extractWav(filePath);
    final wavFile = File(wavPath);
    if (!wavFile.existsSync()) {
      throw Exception('WAV 提取失败');
    }

    // Step 2: 选择处理模式（含 CUDA→CPU 降级）
    SherpaOnnxResult result;
    try {
      result = await _recognizeWithProvider(
        wavPath: wavPath,
        modelVariant: modelVariant,
        language: language,
        useItn: useItn,
        provider: effectiveProvider,
        numThreads: numThreads,
        timelineStartMs: timelineStartMs,
        useVad: useVad,
        onProgress: onProgress,
      );
    } catch (e) {
      // CUDA 失败时自动降级到 CPU
      if (effectiveProvider == 'cuda') {
        print('[SherpaOnnx] CUDA 推理失败，自动降级到 CPU: $e');
        _cudaAvailable = false; // 标记 CUDA 不可用，后续不再尝试
        result = await _recognizeWithProvider(
          wavPath: wavPath,
          modelVariant: modelVariant,
          language: language,
          useItn: useItn,
          provider: 'cpu',
          numThreads: numThreads,
          timelineStartMs: timelineStartMs,
          useVad: useVad,
          onProgress: onProgress,
        );
      } else {
        rethrow;
      }
    }

    // Step 3: 清理临时文件
    try {
      await wavFile.delete();
    } catch (_) {}

    onProgress?.call(1.0);
    return result;
  }

  /// 内部：使用指定 provider 执行识别（不含降级逻辑）
  Future<SherpaOnnxResult> _recognizeWithProvider({
    required String wavPath,
    required String modelVariant,
    required String language,
    required bool useItn,
    required String provider,
    required int numThreads,
    required int timelineStartMs,
    required bool useVad,
    void Function(double progress)? onProgress,
  }) async {
    if (useVad && SherpaOnnxPathService.isVadWithAsrAvailable(modelVariant)) {
      // VAD+ASR 组合模式（推荐）
      try {
        onProgress?.call(0.1);
        return await _processWithVad(
          wavPath: wavPath,
          modelVariant: modelVariant,
          language: language,
          useItn: useItn,
          provider: provider,
          numThreads: numThreads,
          timelineStartMs: timelineStartMs,
        );
      } catch (e) {
        print('[SherpaOnnxVad] VAD+ASR 模式失败，回退到传统模式: $e');
        return await _processLegacy(
          wavPath: wavPath,
          modelVariant: modelVariant,
          language: language,
          useItn: useItn,
          provider: provider,
          numThreads: numThreads,
          timelineStartMs: timelineStartMs,
          onProgress: onProgress,
        );
      }
    } else {
      // 传统固定分片模式（后备）
      return await _processLegacy(
        wavPath: wavPath,
        modelVariant: modelVariant,
        language: language,
        useItn: useItn,
        provider: provider,
        numThreads: numThreads,
        timelineStartMs: timelineStartMs,
        onProgress: onProgress,
      );
    }
  }

  /// 使用 VAD+ASR 组合模式处理整个 WAV 文件
  ///
  /// 调用 sherpa-onnx-vad-with-offline-asr.exe，先 VAD 检测语音片段，
  /// 再对每个片段运行 SenseVoice ASR，输出每行格式：start -- end: text
  Future<SherpaOnnxResult> _processWithVad({
    required String wavPath,
    required String modelVariant,
    required String language,
    required bool useItn,
    required String provider,
    required int numThreads,
    required int timelineStartMs,
  }) async {
    final args = <String>[
      '--silero-vad-model=${SherpaOnnxPathService.sileroVadModelPath}',
      ..._buildModelArgs(modelVariant: modelVariant, language: language, useItn: useItn),
      '--provider=$provider',
      '--num-threads=$numThreads',
      '--silero-vad-threshold=0.5',
      '--silero-vad-min-silence-duration=0.5',
      '--silero-vad-min-speech-duration=0.25',
      '--silero-vad-max-speech-duration=20',
      '--silero-vad-window-size=512',
      wavPath,
    ];

    print('[SherpaOnnxVad] 运行命令: ${SherpaOnnxPathService.vadWithAsrExePath} ${args.join(" ")}');

    final result = await Process.run(
      SherpaOnnxPathService.vadWithAsrExePath,
      args,
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
      stderrEncoding: const Utf8Codec(allowMalformed: true),
    );

    if (result.exitCode != 0) {
      final stderr = (result.stderr as String?) ?? '';
      print('[SherpaOnnxVad] 识别失败 (exitCode=${result.exitCode})');
      print('[SherpaOnnxVad] stderr: $stderr');
      throw Exception('VAD+ASR 识别失败 (退出码${result.exitCode}): ${stderr.isNotEmpty ? stderr.split('\n').first : "未知错误"}');
    }

    final stdout = (result.stdout as String?) ?? '';
    print('[SherpaOnnxVad] stdout 长度: ${stdout.length}');
    return _parseVadOutput(stdout, timelineStartMs);
  }

  /// 根据模型类型构建 CLI 参数
  static List<String> _buildModelArgs({
    required String modelVariant,
    required String language,
    required bool useItn,
  }) {
    if (SherpaOnnxPathService.isQwen3AsrModel(modelVariant)) {
      return [
        '--qwen3-asr-conv-frontend=${SherpaOnnxPathService.qwen3AsrConvFrontendPath(modelVariant)}',
        '--qwen3-asr-encoder=${SherpaOnnxPathService.qwen3AsrEncoderPath(modelVariant)}',
        '--qwen3-asr-decoder=${SherpaOnnxPathService.qwen3AsrDecoderPath(modelVariant)}',
        '--qwen3-asr-tokenizer=${SherpaOnnxPathService.qwen3AsrTokenizerPath(modelVariant)}',
        '--qwen3-asr-max-total-len=2048',
      ];
    }
    // SenseVoice 模型
    return [
      '--sense-voice-model=${SherpaOnnxPathService.senseVoiceModelPath(modelVariant)}',
      '--tokens=${SherpaOnnxPathService.senseVoiceTokensPath(modelVariant)}',
      '--sense-voice-language=$language',
      '--sense-voice-use-itn=${useItn ? 'true' : 'false'}',
    ];
  }

  /// 解析 VAD+ASR 组合模式的纯文本输出
  ///
  /// 输出格式：每行一个语音片段
  ///   start_sec -- end_sec: text
  /// 例如：
  ///   0.518 -- 1.452: 快点。
  ///   2.438 -- 6.476: 阿能给您做个采访吗嗯？
  SherpaOnnxResult _parseVadOutput(String output, int timelineStartMs) {
    final lines = output.split('\n');
    final clips = <TimelineClip>[];
    int totalDurationMs = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 匹配格式: "start -- end: text"
      final match = RegExp(r'^(\d+\.?\d*)\s*--\s*(\d+\.?\d*):\s*(.+)$').firstMatch(trimmed);
      if (match == null) {
        continue;
      }

      final startSec = double.parse(match.group(1)!);
      final endSec = double.parse(match.group(2)!);
      final text = match.group(3)!.trim();

      if (text.isEmpty) continue;

      final startMs = (startSec * 1000).round();
      final endMs = (endSec * 1000).round();
      final durationMs = (endMs - startMs).clamp(100, 10000000);

      totalDurationMs = max(totalDurationMs, endMs);

      // 长文本按标点/字数拆分
      if (text.length > 42) {
        final subClips = _splitTextIntoClips(
          text: text,
          startMs: startMs,
          durationMs: durationMs,
          timelineStartMs: timelineStartMs,
        );
        clips.addAll(subClips);
      } else {
        clips.add(TimelineClip(
          filePath: '',
          fileName: '',
          timelineStartMs: timelineStartMs + startMs,
          durationMs: durationMs,
          mediaIndex: -1,
          text: text,
        ));
      }
    }

    final rawText = clips.map((c) => c.text ?? '').join('');

    print('[SherpaOnnxVad] _parseVadOutput: 解析到 ${clips.length} 条字幕');

    return SherpaOnnxResult(
      clips: clips,
      durationMs: totalDurationMs,
      rawText: rawText,
    );
  }

  /// 将长文本按标点/字数拆分为多个字幕片段
  /// 时间按字符数等比分配
  List<TimelineClip> _splitTextIntoClips({
    required String text,
    required int startMs,
    required int durationMs,
    required int timelineStartMs,
  }) {
    const maxChars = 42;
    final chunks = <String>[];
    final buffer = StringBuffer();
    int charCount = 0;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      buffer.write(char);
      charCount++;

      final isPunct = '?？。！，、；：!.,;:'.contains(char);
      if ((isPunct || charCount >= maxChars) && buffer.isNotEmpty) {
        final chunk = buffer.toString().trim();
        if (chunk.isNotEmpty) chunks.add(chunk);
        buffer.clear();
        charCount = 0;
      }
    }
    if (buffer.isNotEmpty) {
      final chunk = buffer.toString().trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
    }

    // 按字符数等比分配时间
    final totalChars = text.length;
    final clips = <TimelineClip>[];
    int currentMs = startMs;

    for (final chunk in chunks) {
      if (chunk.isEmpty) continue;
      final chunkDuration = (durationMs * chunk.length / totalChars).round().clamp(100, durationMs);
      clips.add(TimelineClip(
        filePath: '',
        fileName: '',
        timelineStartMs: timelineStartMs + currentMs,
        durationMs: chunkDuration,
        mediaIndex: -1,
        text: chunk,
      ));
      currentMs += chunkDuration;
    }

    return clips;
  }

  /// 传统固定分片模式（后备方案）
  Future<SherpaOnnxResult> _processLegacy({
    required String wavPath,
    required String modelVariant,
    required String language,
    required bool useItn,
    required String provider,
    required int numThreads,
    required int timelineStartMs,
    void Function(double progress)? onProgress,
  }) async {
    // 获取 WAV 时长
    final wavFile = File(wavPath);
    final wavSize = await wavFile.length();
    final estimatedDurationMs = (wavSize / 32000).round();

    // 分片处理
    final segmentCount = (estimatedDurationMs / _segmentDurationMs).ceil();
    List<SherpaOnnxResult> segmentResults;

    if (segmentCount <= 1) {
      // 单段处理
      onProgress?.call(0.1);
      segmentResults = [
        await _processSegment(
          wavPath: wavPath,
          startTimeMs: 0,
          modelVariant: modelVariant,
          language: language,
          useItn: useItn,
          provider: provider,
          numThreads: numThreads,
          timelineStartMs: timelineStartMs,
        ),
      ];
      onProgress?.call(0.95);
    } else {
      // 分片处理
      segmentResults = [];
      for (int i = 0; i < segmentCount; i++) {
        final segStartMs = i * _segmentDurationMs;
        final progress = 0.1 + (i / segmentCount) * 0.85;
        onProgress?.call(progress);

        final segWavPath = '$wavPath.seg_$i.wav';
        await _splitWav(wavPath, segStartMs, _segmentDurationMs, segWavPath);

        try {
          final result = await _processSegment(
            wavPath: segWavPath,
            startTimeMs: 0,
            modelVariant: modelVariant,
            language: language,
            useItn: useItn,
            provider: provider,
            numThreads: numThreads,
            timelineStartMs: timelineStartMs + segStartMs,
          );
          segmentResults.add(result);
        } finally {
          // 清理分片 WAV
          try {
            await File(segWavPath).delete();
          } catch (_) {}
        }
      }
    }

    // 合并结果
    final allClips = <TimelineClip>[];
    String rawText = '';
    String? detectedLang;
    String? detectedEmotion;

    for (final r in segmentResults) {
      allClips.addAll(r.clips);
      rawText += r.rawText;
      detectedLang ??= r.language;
      detectedEmotion ??= r.emotion;
    }

    // 过滤幻觉
    final filteredClips = _filterHallucination(allClips);

    return SherpaOnnxResult(
      clips: filteredClips,
      durationMs: estimatedDurationMs,
      rawText: rawText,
      language: detectedLang,
      emotion: detectedEmotion,
    );
  }

  /// 处理单个分片
  Future<SherpaOnnxResult> _processSegment({
    required String wavPath,
    required int startTimeMs,
    required String modelVariant,
    required String language,
    required bool useItn,
    required String provider,
    required int numThreads,
    required int timelineStartMs,
  }) async {
    final args = <String>[
      ..._buildModelArgs(modelVariant: modelVariant, language: language, useItn: useItn),
      '--provider=$provider',
      '--num-threads=$numThreads',
      wavPath,
    ];

    print('[SherpaOnnx] 运行命令: ${SherpaOnnxPathService.offlineExePath} ${args.join(" ")}');

    final result = await Process.run(
      SherpaOnnxPathService.offlineExePath,
      args,
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
      stderrEncoding: const Utf8Codec(allowMalformed: true),
    );

    if (result.exitCode != 0) {
      final stderr = (result.stderr as String?) ?? '';
      print('[SherpaOnnx] 识别失败 (exitCode=${result.exitCode})');
      print('[SherpaOnnx] stderr: $stderr');
      throw Exception('sherpa-onnx 识别失败 (退出码${result.exitCode}): ${stderr.isNotEmpty ? stderr.split('\n').first : "未知错误"}');
    }

    final stdout = (result.stdout as String?) ?? '';
    print('[SherpaOnnx] stdout 长度: ${stdout.length}');
    print('[SherpaOnnx] stdout 前200字符: ${stdout.substring(0, stdout.length > 200 ? 200 : stdout.length)}');
    return _parseOutput(stdout, timelineStartMs, startTimeMs);
  }

  /// 解析 sherpa-onnx 输出
  ///
  /// sherpa-onnx-offline 输出格式：
  /// ```
  /// /path/to/file.wav
  /// ----
  /// num threads: 8
  /// decoding method: greedy_search
  /// Elapsed seconds: 10.5 s
  /// Real time factor (RTF): 10.5 / 60.0 = 0.175
  /// {"lang": "<|zh|>", "emotion": "<|HAPPY|>", "event": "<|Speech|>", "text": "识别文本", "timestamps": [...], "tokens": [...]}
  /// ```
  SherpaOnnxResult _parseOutput(String output, int timelineStartMs, int segmentStartMs) {
    // 找到最后一个 JSON 行
    final lines = output.split('\n');
    String? jsonLine;
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.startsWith('{')) {
        jsonLine = line;
        break;
      }
    }

    if (jsonLine == null) {
      print('[SherpaOnnx] 未找到 JSON 行，输出总行数: ${lines.length}');
      for (int i = 0; i < lines.length && i < 5; i++) {
        print('[SherpaOnnx] line[$i]: ${lines[i]}');
      }
      return const SherpaOnnxResult(
        clips: [],
        durationMs: 0,
        rawText: '',
      );
    }

    try {
      final json = jsonDecode(jsonLine) as Map<String, dynamic>;
      final text = (json['text'] as String?) ?? '';
      final timestamps = (json['timestamps'] as List?)?.cast<double>() ?? [];
      final tokens = (json['tokens'] as List?)?.cast<String>() ?? [];
      final lang = (json['lang'] as String?) ?? '';
      final emotion = (json['emotion'] as String?) ?? '';
      print('[SherpaOnnx] JSON 解析成功: text长度=${text.length}, tokens=${tokens.length}, timestamps=${timestamps.length}');

      // 根据 timestamps 构建字幕片段
      // SenseVoice 输出的是每个 token 的时间戳，需要聚合成字幕行
      final clips = _buildClipsFromTokens(
        tokens: tokens,
        timestamps: timestamps,
        timelineStartMs: timelineStartMs,
        segmentStartMs: segmentStartMs,
      );

      return SherpaOnnxResult(
        clips: clips,
        durationMs: timestamps.isNotEmpty
            ? (timestamps.last * 1000).round() - (timestamps.first * 1000).round()
            : 0,
        rawText: text,
        language: lang.replaceAll('<|', '').replaceAll('|>', ''),
        emotion: emotion.replaceAll('<|', '').replaceAll('|>', ''),
      );
    } catch (e) {
      print('[SherpaOnnx] JSON 解析失败: $e');
      return const SherpaOnnxResult(
        clips: [],
        durationMs: 0,
        rawText: '',
      );
    }
  }

  /// 将 token 级时间戳聚合为字幕片段
  ///
  /// 策略：遇到标点符号（？。！，、；：）或积累 42 字符时分段
  List<TimelineClip> _buildClipsFromTokens({
    required List<String> tokens,
    required List<double> timestamps,
    required int timelineStartMs,
    required int segmentStartMs,
  }) {
    if (tokens.isEmpty || timestamps.isEmpty) return [];

    final clips = <TimelineClip>[];
    final buffer = StringBuffer();
    double? segStartTime;
    double? segEndTime;
    int charCount = 0;
    const maxChars = 42; // 单行最大字符数

    for (int i = 0; i < tokens.length && i < timestamps.length; i++) {
      final token = tokens[i];
      final ts = timestamps[i];

      if (segStartTime == null) {
        segStartTime = ts;
      }
      segEndTime = ts;

      buffer.write(token);
      charCount += token.length;

      // 分段条件：标点符号 或 达到最大字符数
      final isPunctuation = '?？。！，、；：!.,;:'.contains(token);
      final shouldSplit = isPunctuation || charCount >= maxChars;

      if (shouldSplit && buffer.isNotEmpty) {
        final text = buffer.toString().trim();
        if (text.isNotEmpty) {
          // 时间戳从分段起始偏移
          final startMs = (segStartTime * 1000).round();
          final endMs = (segEndTime * 1000).round();

          clips.add(TimelineClip(
            filePath: '',
            fileName: '',
            timelineStartMs: timelineStartMs + startMs,
            durationMs: (endMs - startMs).abs().clamp(100, double.maxFinite.toInt()),
            mediaIndex: -1,
            text: text,
          ));
        }
        buffer.clear();
        charCount = 0;
        segStartTime = null;
        segEndTime = null;
      }
    }

    // 处理剩余内容
    if (buffer.isNotEmpty && segStartTime != null) {
      final text = buffer.toString().trim();
      if (text.isNotEmpty) {
        final startMs = (segStartTime * 1000).round();
        final endMs = (segEndTime! * 1000).round();
        clips.add(TimelineClip(
          filePath: '',
          fileName: '',
          timelineStartMs: timelineStartMs + startMs,
          durationMs: (endMs - startMs).abs().clamp(100, double.maxFinite.toInt()),
          mediaIndex: -1,
          text: text,
        ));
      }
    }

    print('[SherpaOnnx] _buildClipsFromTokens: 输入 tokens=${tokens.length}, 生成 clips=${clips.length}');

    return clips;
  }

  /// 过滤幻觉重复段落
  static List<TimelineClip> _filterHallucination(List<TimelineClip> clips) {
    if (clips.length < 6) return clips;

    final isHallucination = List.filled(clips.length, false);

    for (int i = 0; i < clips.length; i++) {
      if (isHallucination[i]) continue;

      final text = (clips[i].text ?? '').trim();
      if (text.isEmpty) continue;

      // 策略1：连续重复
      int consecutiveCount = 1;
      int j = i + 1;
      while (j < clips.length && (clips[j].text ?? '').trim() == text) {
        consecutiveCount++;
        j++;
      }
      if (consecutiveCount >= 3) {
        for (int k = i; k < j; k++) {
          isHallucination[k] = true;
        }
        continue;
      }

      // 策略2：交替重复
      for (int cycleLen = 2; cycleLen <= 3; cycleLen++) {
        if (i + cycleLen >= clips.length) continue;
        final cycleTexts = <String>[];
        for (int c = 0; c < cycleLen; c++) {
          cycleTexts.add((clips[i + c].text ?? '').trim());
        }
        int matchCount = cycleLen;
        int k = i + cycleLen;
        while (k < clips.length) {
          final expectedText = cycleTexts[(k - i) % cycleLen];
          if ((clips[k].text ?? '').trim() != expectedText) break;
          matchCount++;
          k++;
        }
        if (matchCount >= 6 && matchCount >= cycleLen * 3) {
          for (int m = i; m < k; m++) {
            isHallucination[m] = true;
          }
          break;
        }
      }
    }

    return [for (int i = 0; i < clips.length; i++) if (!isHallucination[i]) clips[i]];
  }

  /// 用 FFmpeg 提取 16kHz 单声道 WAV
  Future<String> _extractWav(String inputPath) async {
    final wavPath = '$inputPath.tmp_sherpa.wav';
    print('[SherpaOnnx] 提取 WAV: $inputPath');
    final result = await Process.run(FfmpegPathService.ffmpegPath, [
      '-i', inputPath,
      '-ar', '16000',
      '-ac', '1',
      '-c:a', 'pcm_s16le',
      '-y',
      wavPath,
    ]);
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String?) ?? '';
      print('[SherpaOnnx] FFmpeg WAV 提取失败: $stderr');
      throw Exception('音频提取失败: 文件可能没有音频轨道或格式不支持');
    }
    return wavPath;
  }

  /// 用 FFmpeg 切割 WAV 分片
  Future<void> _splitWav(
    String inputPath,
    int startMs,
    int durationMs,
    String outputPath,
  ) async {
    await Process.run(FfmpegPathService.ffmpegPath, [
      '-i', inputPath,
      '-ss', (startMs / 1000).toString(),
      '-t', (durationMs / 1000).toString(),
      '-c:a', 'pcm_s16le',
      '-ar', '16000',
      '-ac', '1',
      '-y',
      outputPath,
    ]);
  }
}
