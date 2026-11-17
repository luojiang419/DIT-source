import 'dart:io';
import 'package:path/path.dart' as p;

/// 统一管理 ffmpeg/ffprobe 可执行文件路径。
///
/// 查找顺序：
/// 1. 与应用程序 exe 同级的 ffmpeg/bin/ 目录（打包发布场景）
/// 2. 硬编码的开发机绝对路径（开发调试场景）
class FfmpegPathService {
  static const _devFfmpegPath  = r'G:\data\app\DIT\ffmpeg\bin\ffmpeg.exe';
  static const _devFfprobePath = r'G:\data\app\DIT\ffmpeg\bin\ffprobe.exe';

  /// 检查 FFmpeg/FFprobe 是否实际存在于磁盘
  static bool get isAvailable {
    return File(ffmpegPath).existsSync() && File(ffprobePath).existsSync();
  }

  static String? _ffmpegPath;
  static String? _ffprobePath;

  static String get ffmpegPath  => _ffmpegPath  ??= _resolve('ffmpeg.exe',  _devFfmpegPath);
  static String get ffprobePath => _ffprobePath ??= _resolve('ffprobe.exe', _devFfprobePath);

  static String _resolve(String exeName, String devFallback) {
    try {
      // 取应用 exe 所在目录，拼接 ffmpeg/bin/<exeName>
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidate = p.join(exeDir, 'ffmpeg', 'bin', exeName);
      if (File(candidate).existsSync()) {
        return candidate;
      }
    } catch (_) {}

    // 开发机绝对路径 fallback
    return devFallback;
  }
}
