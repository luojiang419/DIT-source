import 'dart:io';
import 'package:path/path.dart' as p;

/// 管理 sherpa-onnx 工具路径及模型文件路径。
///
/// 查找顺序：
/// 1. 与应用程序 exe 同级的 sherpa-onnx/ 目录（打包发布场景）
/// 2. 硬编码的开发机绝对路径（开发调试场景）
class SherpaOnnxPathService {
  static const _devSherpaOnnxDir = r'G:\data\app\DIT\sherpa-onnx';

  static String? _sherpaOnnxDir;

  /// sherpa-onnx 根目录
  static String get sherpaOnnxDir =>
      _sherpaOnnxDir ??= _resolveDir();

  /// sherpa-onnx-offline.exe 路径
  static String get offlineExePath =>
      p.join(sherpaOnnxDir, 'bin', 'sherpa-onnx-offline.exe');

  /// sherpa-onnx-vad.exe 路径
  static String get vadExePath =>
      p.join(sherpaOnnxDir, 'bin', 'sherpa-onnx-vad.exe');

  /// sherpa-onnx-offline-punctuation.exe 路径
  static String get punctuationExePath =>
      p.join(sherpaOnnxDir, 'bin', 'sherpa-onnx-offline-punctuation.exe');

  /// sherpa-onnx-vad-with-offline-asr.exe 路径（VAD+ASR 组合工具）
  static String get vadWithAsrExePath =>
      p.join(sherpaOnnxDir, 'bin', 'sherpa-onnx-vad-with-offline-asr.exe');

  /// Silero VAD 模型路径
  static String get sileroVadModelPath =>
      p.join(sherpaOnnxDir, 'models', 'silero_vad.onnx');

  /// 检查 sherpa-onnx-offline.exe 是否存在
  static bool get isAvailable => File(offlineExePath).existsSync();

  /// 检查 VAD+ASR 组合模式是否可用
  /// 需要同时存在：sherpa-onnx-vad-with-offline-asr.exe、silero_vad.onnx、模型文件
  static bool isVadWithAsrAvailable(String modelVariant) =>
      File(vadWithAsrExePath).existsSync() &&
      File(sileroVadModelPath).existsSync() &&
      (isSenseVoiceAvailable(modelVariant) || isQwen3AsrAvailable(modelVariant));

  /// 获取模型目录路径
  static String _modelsDir() => p.join(sherpaOnnxDir, 'models');

  /// 获取 SenseVoice 模型路径
  static String senseVoiceModelPath(String variant) =>
      p.join(_modelsDir(), variant, 'model.int8.onnx');

  /// 获取 SenseVoice tokens.txt 路径
  static String senseVoiceTokensPath(String variant) =>
      p.join(_modelsDir(), variant, 'tokens.txt');

  /// 检查 SenseVoice 模型是否存在
  static bool isSenseVoiceAvailable(String variant) =>
      File(senseVoiceModelPath(variant)).existsSync() &&
      File(senseVoiceTokensPath(variant)).existsSync();

  // ========== Qwen3-ASR 模型路径 ==========

  static String qwen3AsrConvFrontendPath(String variant) =>
      p.join(_modelsDir(), variant, 'conv_frontend.onnx');

  static String qwen3AsrEncoderPath(String variant) =>
      p.join(_modelsDir(), variant, 'encoder.int8.onnx');

  static String qwen3AsrDecoderPath(String variant) =>
      p.join(_modelsDir(), variant, 'decoder.int8.onnx');

  static String qwen3AsrTokenizerPath(String variant) =>
      p.join(_modelsDir(), variant, 'tokenizer');

  /// 检查 Qwen3-ASR 模型是否存在
  static bool isQwen3AsrAvailable(String variant) =>
      File(qwen3AsrConvFrontendPath(variant)).existsSync() &&
      File(qwen3AsrEncoderPath(variant)).existsSync() &&
      File(qwen3AsrDecoderPath(variant)).existsSync() &&
      Directory(qwen3AsrTokenizerPath(variant)).existsSync();

  /// 判断模型是否为 Qwen3-ASR 类型
  static bool isQwen3AsrModel(String variant) =>
      variant.contains('qwen3-asr') || variant.contains('qwen3_asr');

  /// 检查任意模型是否可用（SenseVoice 或 Qwen3-ASR）
  static bool isModelAvailable(String variant) =>
      isSenseVoiceAvailable(variant) || isQwen3AsrAvailable(variant);

  /// 列出所有可用的 sherpa-onnx 模型
  static List<SherpaOnnxModelInfo> listAvailableModels() {
    final modelsDir = _modelsDir();
    final dir = Directory(modelsDir);
    if (!dir.existsSync()) return [];

    final models = <SherpaOnnxModelInfo>[];
    for (final entity in dir.listSync()) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);

      // SenseVoice 模型
      final modelFile = p.join(entity.path, 'model.int8.onnx');
      final tokensFile = p.join(entity.path, 'tokens.txt');
      if (File(modelFile).existsSync() && File(tokensFile).existsSync()) {
        final modelSize = File(modelFile).lengthSync();
        models.add(SherpaOnnxModelInfo(
          variant: name,
          modelPath: modelFile,
          tokensPath: tokensFile,
          sizeBytes: modelSize,
        ));
        continue;
      }

      // Qwen3-ASR 模型
      if (isQwen3AsrAvailable(name)) {
        final encoderSize = File(qwen3AsrEncoderPath(name)).lengthSync();
        final decoderSize = File(qwen3AsrDecoderPath(name)).lengthSync();
        final frontendSize = File(qwen3AsrConvFrontendPath(name)).lengthSync();
        models.add(SherpaOnnxModelInfo(
          variant: name,
          modelPath: qwen3AsrEncoderPath(name),
          tokensPath: qwen3AsrTokenizerPath(name),
          sizeBytes: encoderSize + decoderSize + frontendSize,
        ));
      }
    }
    return models;
  }

  /// 推荐的模型列表
  static const availableModels = [
    SherpaOnnxModelInfo(
      variant: 'sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25',
      displayName: 'Qwen3-ASR 0.6B int8 (982MB, 最准确)',
      sizeBytes: 982000000,
    ),
    SherpaOnnxModelInfo(
      variant: 'sense-voice-small',
      displayName: 'SenseVoice-Small (229MB, 速度优先)',
      sizeBytes: 229000000,
    ),
  ];

  static String _resolveDir() {
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidate = p.join(exeDir, 'sherpa-onnx');
      if (Directory(candidate).existsSync()) return candidate;
    } catch (_) {}
    return _devSherpaOnnxDir;
  }
}

/// sherpa-onnx 模型信息
class SherpaOnnxModelInfo {
  const SherpaOnnxModelInfo({
    required this.variant,
    this.displayName,
    this.sizeBytes = 0,
    this.modelPath = '',
    this.tokensPath = '',
  });

  final String variant;
  final String? displayName;
  final int sizeBytes;
  final String modelPath;
  final String tokensPath;

  String get displayLabel =>
      displayName ?? variant;

  String get sizeText {
    if (sizeBytes >= 1000000000) {
      return '${(sizeBytes / 1000000000).toStringAsFixed(1)}GB';
    }
    return '${(sizeBytes / 1000000).toStringAsFixed(0)}MB';
  }
}
