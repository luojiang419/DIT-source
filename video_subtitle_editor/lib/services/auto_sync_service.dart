import '../models/timeline_model.dart';
import 'context_matching_service.dart';
import 'sync_calculation_service.dart';
import 'timecode_service.dart';

/// 合板进度回调
typedef SyncProgressCallback = void Function(String step, double progress);

/// 合板最终结果
class AutoSyncResult {
  const AutoSyncResult({
    required this.syncedProject,
    required this.matches,
    required this.videoCount,
    required this.audioSubtitleCount,
    required this.videoSubtitleCount,
  });

  final TimelineProject syncedProject;
  final List<SyncMatch> matches;
  final int videoCount;
  final int audioSubtitleCount;
  final int videoSubtitleCount;
}

/// 合板失败异常
class AutoSyncException implements Exception {
  AutoSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 全自动合板服务：编排整个合板流程
class AutoSyncService {
  AutoSyncService({SyncProgressCallback? onProgress}) : _onProgress = onProgress;

  final SyncProgressCallback? _onProgress;
  final _timecodeService = TimecodeService();
  final _matchingService = ContextMatchingService();
  final _calcService = SyncCalculationService();

  void _progress(String step, double p) => _onProgress?.call(step, p);

  /// 执行全自动合板
  Future<AutoSyncResult> performSync({
    required TimelineProject originalProject,
    SyncMatch? selectedMatch,
  }) async {
    final videoClips = originalProject.videoTrack?.clips ?? [];
    final videoSubtitles =
        originalProject.videoTrack?.linkedSubtitleTrack?.clips ?? [];

    if (videoClips.isEmpty) {
      throw AutoSyncException('视频轨道为空，请先添加视频');
    }
    if (originalProject.audioTracks.isEmpty) {
      throw AutoSyncException('音频轨道为空，请先导入音频');
    }
    if (videoSubtitles.isEmpty) {
      throw AutoSyncException('视频轨道没有字幕，请先为视频导入字幕');
    }

    final audioTracksWithSub = originalProject.audioTracks
        .where((t) => t.linkedSubtitleTrack?.clips.isNotEmpty == true)
        .toList();

    if (audioTracksWithSub.isEmpty) {
      final details = originalProject.audioTracks.asMap().entries.map((e) {
        final subCount = e.value.linkedSubtitleTrack?.clips.length ?? 0;
        final clipCount = e.value.clips.length;
        return '轨道${e.key + 1}(${clipCount}个片段, ${subCount}条字幕)';
      }).join(' / ');
      throw AutoSyncException(
        '所有音频轨道都没有字幕。\n当前状态：$details\n'
        '请确认：导入字幕时选择了正确的音频轨道（不是视频轨道）',
      );
    }

    final audioTrack = audioTracksWithSub.first;
    final audioSubtitles = audioTrack.linkedSubtitleTrack!.clips;

    // ── 阶段1：字幕匹配（用于音频对齐） ─────────────────────
    _progress('构建字幕上下文...', 0.1);
    final videoContexts = _matchingService.buildContexts(videoSubtitles, -1);
    final audioContexts = _matchingService.buildContexts(audioSubtitles, 0);
    _progress('匹配字幕上下文...', 0.3);
    final matches = _matchingService.findMatches(videoContexts, audioContexts);

    if (matches.isEmpty) {
      throw AutoSyncException(
        '未找到匹配的字幕上下文。\n'
        '视频字幕：${videoSubtitles.length}条，音频字幕：${audioSubtitles.length}条\n'
        '请检查视频和音频的字幕内容是否一致',
      );
    }

    final bestMatch = selectedMatch ?? matches.first;

    // ── 阶段2：读取源时间码 ──────────────────────────────────
    // 优先使用导入时已存储的源时间码，避免重复读取
    _progress('读取源时间码...', 0.5);

    Map<String, SourceTimecode> videoTimecodes;
    if (originalProject.sourceTimecodes.isNotEmpty) {
      // 只取视频文件的时间码
      videoTimecodes = Map.fromEntries(
        originalProject.sourceTimecodes.entries.where(
          (e) => videoClips.any((c) => c.filePath == e.key),
        ),
      );
    } else {
      final videoDurations = <String, int>{};
      for (final clip in videoClips) {
        videoDurations[clip.filePath] = clip.durationMs;
      }
      videoTimecodes = await _timecodeService.extractTimecodes(
        videoDurations.keys.toList(),
        videoDurations,
      );
    }

    final audioDurations = <String, int>{};
    for (final clip in audioTrack.clips) {
      audioDurations[clip.filePath] = clip.durationMs;
    }
    final audioTimecodes = await _timecodeService.extractTimecodes(
      audioDurations.keys.toList(),
      audioDurations,
    );

    if (videoTimecodes.isEmpty || audioTimecodes.isEmpty) {
      throw AutoSyncException('无法读取源时间码，请确认文件包含时间码元数据');
    }

    // ── 阶段3：按源时间码重新平铺视频（含间隔留白） ──────────
    _progress('按源时间码平铺视频...', 0.7);

    // 以最早的视频源时间码为0点
    final videoOriginMs = videoTimecodes.values
        .where((tc) => tc.startMs > 0)
        .map((tc) => tc.startMs)
        .fold<int>(0, (min, v) => min == 0 || v < min ? v : min);

    // 重新定位视频片段（按源时间码，保留间隔）
    final repositionedVideoClips = videoClips.map((clip) {
      final tc = videoTimecodes[clip.filePath];
      if (tc == null || tc.startMs <= 0) return clip;
      final newStart = tc.startMs - videoOriginMs;
      return clip.copyWith(timelineStartMs: newStart);
    }).toList();

    // ── 阶段4：计算音频偏移量（基于字幕匹配） ────────────────
    _progress('计算音频偏移量...', 0.8);

    // 通过匹配字幕对计算音频相对视频的偏移量：
    // 视频字幕在新时间轴上的位置 - 音频字幕在原时间轴上的位置 = 音频需要移动的量
    final videoSubClip = bestMatch.videoContext.target;
    final audioSubClip = bestMatch.audioContext.target;

    // 找到该视频字幕对应的视频片段，获取其在新时间轴上的偏移量
    final originalVideoClip = videoClips.firstWhere(
      (c) => videoSubClip.timelineStartMs >= c.timelineStartMs &&
             videoSubClip.timelineStartMs < c.timelineEndMs,
      orElse: () => videoClips.first,
    );
    final repositionedVideoClip = repositionedVideoClips.firstWhere(
      (c) => c.filePath == originalVideoClip.filePath,
      orElse: () => repositionedVideoClips.first,
    );
    final videoDelta = repositionedVideoClip.timelineStartMs - originalVideoClip.timelineStartMs;

    // 视频字幕在新时间轴上的绝对位置
    final videoSubNewPos = videoSubClip.timelineStartMs + videoDelta;
    // 音频需要移动的偏移量 = 视频字幕新位置 - 音频字幕原位置
    final audioOffsetMs = videoSubNewPos - audioSubClip.timelineStartMs;

    // 移动音频轨道和音频字幕
    final repositionedAudioTracks = originalProject.audioTracks.map((track) {
      final newClips = track.clips.map((c) => c.copyWith(
        timelineStartMs: c.timelineStartMs + audioOffsetMs,
      )).toList();
      final newSubtitleTrack = track.linkedSubtitleTrack == null ? null :
        TimelineTrack(
          type: TrackType.subtitle,
          clips: track.linkedSubtitleTrack!.clips.map((c) => c.copyWith(
            timelineStartMs: c.timelineStartMs + audioOffsetMs,
          )).toList(),
        );
      return TimelineTrack(
        type: track.type,
        clips: newClips,
        linkedSubtitleTrack: newSubtitleTrack,
      );
    }).toList();

    // ── 阶段5：同步移动视频字幕 ──────────────────────────────
    _progress('同步字幕位置...', 0.9);

    final repositionedSubtitles = _calcService.repositionSubtitles(
      subtitles: videoSubtitles,
      originalVideoClips: videoClips,
      repositionedVideoClips: repositionedVideoClips,
    );

    // ── 阶段6：构建合板项目 ──────────────────────────────────
    _progress('生成合板项目...', 0.95);

    final maxVideoEnd = repositionedVideoClips.fold<int>(
      0, (m, c) => c.timelineEndMs > m ? c.timelineEndMs : m,
    );
    final maxAudioEnd = repositionedAudioTracks.fold<int>(0, (m, track) =>
      track.clips.fold<int>(m, (mm, c) => c.timelineEndMs > mm ? c.timelineEndMs : mm),
    );
    final totalDuration = maxVideoEnd > maxAudioEnd ? maxVideoEnd : maxAudioEnd;

    final syncedVideoTrack = TimelineTrack(
      type: TrackType.video,
      clips: repositionedVideoClips,
      linkedSubtitleTrack: repositionedSubtitles.isNotEmpty
          ? TimelineTrack(type: TrackType.subtitle, clips: repositionedSubtitles)
          : null,
    );

    final allTimecodes = <String, SourceTimecode>{
      ...videoTimecodes,
      ...audioTimecodes,
    };

    final syncedProject = TimelineProject(
      videoTrack: syncedVideoTrack,
      audioTracks: repositionedAudioTracks,
      subtitleTrack: originalProject.subtitleTrack,
      durationMs: totalDuration,
      sourceTimecodes: allTimecodes,
      isSyncedProject: true,
      syncOffsetMs: audioOffsetMs,
    );

    _progress('合板完成', 1.0);

    return AutoSyncResult(
      syncedProject: syncedProject,
      matches: matches,
      videoCount: videoClips.length,
      audioSubtitleCount: audioSubtitles.length,
      videoSubtitleCount: videoSubtitles.length,
    );
  }

  /// 仅执行匹配阶段（用于预览匹配结果）
  List<SyncMatch> previewMatches(TimelineProject project) {
    final videoSubtitles =
        project.videoTrack?.linkedSubtitleTrack?.clips ?? [];

    final audioTrackWithSub = project.audioTracks.where(
      (t) => t.linkedSubtitleTrack?.clips.isNotEmpty == true,
    );
    final audioSubtitles = audioTrackWithSub.isNotEmpty
        ? audioTrackWithSub.first.linkedSubtitleTrack!.clips
        : <TimelineClip>[];

    if (videoSubtitles.isEmpty || audioSubtitles.isEmpty) return [];

    final videoContexts = _matchingService.buildContexts(videoSubtitles, -1);
    final audioContexts = _matchingService.buildContexts(audioSubtitles, 0);
    return _matchingService.findMatches(videoContexts, audioContexts);
  }
}
