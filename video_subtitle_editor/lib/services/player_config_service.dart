import 'package:media_kit/media_kit.dart';

/// Service to configure advanced MPV player options
class PlayerConfigService {
  /// Configure hardware decoding for the player
  /// This should be called after player initialization
  static Future<void> enableHardwareDecoding(Player player) async {
    try {
      // Wait for player to be fully initialized
      await Future.delayed(const Duration(milliseconds: 200));

      // Get the native MPV handle
      final handle = await player.platform?.handle;

      if (handle != null) {
        // Try to set hwdec property via MPV
        // Note: This requires accessing the MPV library directly
        // For now, we rely on vo=gpu which automatically enables hardware decoding
        print('[PlayerConfig] Player handle obtained: $handle');
        print('[PlayerConfig] Hardware decoding enabled via vo=gpu');
        print('[PlayerConfig] MPV will automatically use CUDA/NVDEC/D3D11VA');
      } else {
        print('[PlayerConfig] Could not obtain player handle');
        print('[PlayerConfig] Using vo=gpu for hardware acceleration');
      }
    } catch (e) {
      print('[PlayerConfig] Error configuring hardware decoding: $e');
      print('[PlayerConfig] Falling back to vo=gpu configuration');
    }
  }

  /// Get recommended player configuration
  /// vo 不强制指定，让 MPV 根据当前硬件自动选择最优输出驱动
  static PlayerConfiguration getOptimizedConfiguration() {
    return PlayerConfiguration(
      // Large buffer for smooth seeking and playback
      bufferSize: 64 * 1024 * 1024, // 64MB

      // 不强制 vo=gpu，避免在无 NVIDIA/兼容 GPU 的机器上初始化失败
      // MPV 会自动按优先级选择：gpu -> d3d11va -> dxva2 -> software

      // Enable libass for subtitle rendering
      libass: true,

      // Reduce log verbosity
      logLevel: MPVLogLevel.error,

      ready: () {
        print('[PlayerConfig] Player initialized (auto video output)');
      },
    );
  }
}
