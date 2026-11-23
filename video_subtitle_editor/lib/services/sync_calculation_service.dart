import '../models/timeline_model.dart';
import 'context_matching_service.dart';

/// 合板偏移量计算结果
class SyncCalculationResult {
  const SyncCalculationResult({
    required this.videoClips,       // 重新定位后的视频片段列表
    required this.audioOffsetMs,    // 音频轨道整体偏移量（毫秒）
    required this.matchedContext,   // 使用的匹配对
    required this.totalDurationMs,  // 合板后总时长
  });

  final List<TimelineClip> videoClips;
  final int audioOffsetMs;
  final SyncMatch matchedContext;
  final int totalDurationMs;
}

/// 基于源时间码计算合板偏移量，将视频平铺到音频时间轴
class SyncCalculationService {
  /// 计算合板结果
  ///
  /// 核心逻辑：
  /// 1. 找到匹配字幕对应的源时间码
  /// 2. 计算每个视频文件在音频时间轴上的绝对位置
  /// 3. 返回重新定位后的视频片段列表
  SyncCalculationResult calculate({
    required List<TimelineClip> videoClips,
    required Map<String, SourceTimecode> videoTimecodes,
    required Map<String, SourceTimecode> audioTimecodes,
    required SyncMatch match,
  }) {
    // 获取音频的源起始时间码（以第一条音频为基准）
    final audioBaseMs = audioTimecodes.values.isNotEmpty
        ? audioTimecodes.values.first.startMs
        : 0;

    // 重新定位每个视频片段
    final repositionedClips = <TimelineClip>[];
    int maxEndMs = 0;

    // 按文件分组，每个文件只计算一次偏移量
    final fileOffsets = <String, int>{};

    for (final clip in videoClips) {
      final tc = videoTimecodes[clip.filePath];
      if (tc == null) {
        // 没有时间码的片段保持原位
        repositionedClips.add(clip);
        continue;
      }

      // 计算该视频文件在音频时间轴上的起始位置（每个文件只算一次）
      if (!fileOffsets.containsKey(clip.filePath)) {
        // 视频源时间码 - 音频基准时间码 = 视频在音频时间轴上的绝对位置
        fileOffsets[clip.filePath] = tc.startMs - audioBaseMs;
      }

      final fileOffset = fileOffsets[clip.filePath]!;

      // 视频片段在音频时间轴上的位置 = 视频源时间码 - 音频基准时间码
      // 视频导入时 timelineStartMs 已经是相对最早视频的偏移，这里需要用源时间码重新定位到音频时间轴
      final newStart = fileOffset;

      final repositioned = clip.copyWith(
        timelineStartMs: newStart < 0 ? 0 : newStart,
      );
      repositionedClips.add(repositioned);

      final endMs = repositioned.timelineStartMs + repositioned.durationMs;
      if (endMs > maxEndMs) maxEndMs = endMs;
    }

    // 音频总时长也计入
    for (final tc in audioTimecodes.values) {
      if (tc.durationMs > maxEndMs) maxEndMs = tc.durationMs;
    }

    return SyncCalculationResult(
      videoClips: repositionedClips,
      audioOffsetMs: 0, // 音频保持不动，视频移动到音频时间轴
      matchedContext: match,
      totalDurationMs: maxEndMs,
    );
  }

  /// 将视频字幕跟随视频片段同步移动
  List<TimelineClip> repositionSubtitles({
    required List<TimelineClip> subtitles,
    required List<TimelineClip> originalVideoClips,
    required List<TimelineClip> repositionedVideoClips,
  }) {
    // 建立原始片段 → 新片段的偏移量映射
    final offsetMap = <String, int>{};
    for (int i = 0; i < originalVideoClips.length; i++) {
      if (i < repositionedVideoClips.length) {
        final delta = repositionedVideoClips[i].timelineStartMs -
            originalVideoClips[i].timelineStartMs;
        offsetMap[originalVideoClips[i].id] = delta;
      }
    }

    // 为每条字幕找到所属的视频片段，应用对应偏移量
    return subtitles.map((sub) {
      final parentClip = originalVideoClips.firstWhere(
        (c) =>
            sub.timelineStartMs >= c.timelineStartMs &&
            sub.timelineStartMs < c.timelineEndMs,
        orElse: () => originalVideoClips.isNotEmpty
            ? originalVideoClips.first
            : sub as TimelineClip,
      );
      final delta = offsetMap[parentClip.id] ?? 0;
      return sub.copyWith(timelineStartMs: sub.timelineStartMs + delta);
    }).toList();
  }
}
