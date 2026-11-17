import '../models/timeline_model.dart';
import 'context_matching_service.dart';
import 'timecode_service.dart';

/// 锚点：一对匹配的视频字幕和音频字幕
class AnchorPoint {
  const AnchorPoint({
    required this.videoSubtitle,
    required this.audioSubtitle,
    required this.confidence,
    required this.offsetMs,
  });

  final TimelineClip videoSubtitle;
  final TimelineClip audioSubtitle;
  final double confidence;

  /// offset = videoSubtitle.timelineStartMs - audioSubtitle.timelineStartMs
  final int offsetMs;

  @override
  String toString() =>
      'Anchor(${videoSubtitle.text?.substring(0, videoSubtitle.text!.length > 15 ? 15 : videoSubtitle.text!.length)}..., '
      'offset=${offsetMs}ms, conf=${(confidence * 100).toStringAsFixed(1)}%)';
}

/// 多点同步结果
class MultiPointSyncResult {
  const MultiPointSyncResult({
    required this.syncedProject,
    required this.anchorPoints,
    required this.isSegmented,
    required this.segmentCount,
  });

  final TimelineProject syncedProject;
  final List<AnchorPoint> anchorPoints;

  /// 是否进行了分段裁切（true=分段，false=全局偏移）
  final bool isSegmented;
  final int segmentCount;
}

/// 多点字幕锚点合板服务
///
/// 支持两种同步策略：
/// 1. 时间码同步（优先）：当视频和音频都有源时间码时，直接计算偏移，精度毫秒级
/// 2. 字幕匹配同步（降级）：通过字幕文本上下文匹配计算偏移
class MultiPointSyncService {
  final _matchingService = ContextMatchingService();
  final _timecodeService = TimecodeService();

  /// 同步策略类型
  static const String strategyTimecode = '时间码同步';
  static const String strategySubtitle = '字幕匹配';

  /// 执行多点合板（策略路由）
  ///
  /// 优先使用时间码同步，无时间码时降级到字幕匹配。
  /// [audioTimecodes] 可选传入音频时间码，为空时自动从项目提取。
  Future<MultiPointSyncResult> performSync({
    required TimelineProject originalProject,
    Map<String, SourceTimecode>? audioTimecodes,
  }) async {
    // ── 1. 检查是否有音视频时间码 ─────────────────────────────
    final videoTCs = originalProject.sourceTimecodes;
    final audioTCs = audioTimecodes ?? await _extractAudioTimecodes(originalProject);

    final videoFilesWithTC = videoTCs.keys.where((k) {
      return originalProject.videoTrack?.clips.any((c) => c.filePath == k) ?? false;
    }).toList();

    final hasVideoTC = videoFilesWithTC.isNotEmpty;
    final hasAudioTC = audioTCs.isNotEmpty;

    // ── 2. 时间码优先 ──────────────────────────────────────────
    if (hasVideoTC && hasAudioTC) {
      try {
        return _syncByTimecodes(originalProject, videoTCs, audioTCs);
      } catch (e) {
        // 时间码同步失败，降级到字幕匹配
      }
    }

    // ── 3. 降级到字幕匹配 ──────────────────────────────────────
    return _syncBySubtitleMatching(originalProject);
  }

  /// 从音频轨道提取源时间码
  Future<Map<String, SourceTimecode>> _extractAudioTimecodes(
    TimelineProject project,
  ) async {
    final result = <String, SourceTimecode>{};
    for (final track in project.audioTracks) {
      for (final clip in track.clips) {
        // 跳过已提取过的（在 sourceTimecodes 中已有的）
        if (project.sourceTimecodes.containsKey(clip.filePath)) continue;
        final tc = await _timecodeService.extractTimecode(
          clip.filePath,
          clip.durationMs,
        );
        if (tc != null) {
          result[clip.filePath] = tc;
        }
      }
    }
    return result;
  }

  /// ──────────────────────────────────────────────────────────────
  /// 策略A：时间码同步
  /// ──────────────────────────────────────────────────────────────
  MultiPointSyncResult _syncByTimecodes(
    TimelineProject original,
    Map<String, SourceTimecode> videoTCs,
    Map<String, SourceTimecode> audioTCs,
  ) {
    final videoClips = original.videoTrack?.clips ?? [];
    if (videoClips.isEmpty) throw Exception('没有视频片段');

    // 找到第一个有音频文件的音频轨道
    final audioTrack = original.audioTracks
        .where((t) => t.clips.isNotEmpty)
        .firstOrNull;
    if (audioTrack == null) throw Exception('没有音频轨道');

    final audioClip = audioTrack.clips.first;

    // 音频基准时间码（最早的音频源时间码）
    final audioBaseMs = audioTCs.values
        .map((tc) => tc.startMs)
        .reduce((a, b) => a < b ? a : b);

    final newAudioClips = <TimelineClip>[];
    final anchors = <AnchorPoint>[];
    int matchedCount = 0;

    for (final videoClip in videoClips) {
      final videoTC = videoTCs[videoClip.filePath];
      if (videoTC == null) continue;

      // 视频对应的音频源位置 = 视频时间码 - 音频基准时间码
      final audioSourcePos = videoTC.startMs - audioBaseMs;
      if (audioSourcePos < 0) continue; // 视频在音频开始前，跳过

      // 检查音频源位置是否超出音频总时长
      final audioTotalMs = audioClip.durationMs + audioClip.sourceStartMs;
      if (audioSourcePos >= audioTotalMs) continue;

      // 创建对齐的音频段
      newAudioClips.add(TimelineClip(
        filePath: audioClip.filePath,
        fileName: audioClip.fileName,
        timelineStartMs: videoClip.timelineStartMs, // 和视频位置一致
        durationMs: videoClip.durationMs,            // 和视频等长
        mediaIndex: -1,
        sourceStartMs: audioSourcePos,               // 源文件中的起始位置
      ));

      // 创建虚拟锚点用于显示
      anchors.add(AnchorPoint(
        videoSubtitle: TimelineClip(
          filePath: videoClip.filePath,
          fileName: videoClip.fileName,
          timelineStartMs: videoClip.timelineStartMs,
          durationMs: 0,
          mediaIndex: -1,
          text: '[TC] ${videoClip.fileName}',
        ),
        audioSubtitle: TimelineClip(
          filePath: audioClip.filePath,
          fileName: audioClip.fileName,
          timelineStartMs: audioSourcePos,
          durationMs: 0,
          mediaIndex: -1,
          text: '[TC] 偏移 ${audioSourcePos}ms',
        ),
        confidence: 1.0, // 时间码精度 = 100%
        offsetMs: 0,     // 直接定位，offset=0
      ));

      matchedCount++;
    }

    if (newAudioClips.isEmpty) {
      throw Exception('时间码同步失败：没有找到可对齐的视频-音频对');
    }

    // 构建新的音频轨道
    final newAudioTrack = TimelineTrack(
      type: TrackType.audio,
      clips: newAudioClips,
    );

    // 保留其他音频轨道
    final newAudioTracks = <TimelineTrack>[];
    bool primaryReplaced = false;
    for (final track in original.audioTracks) {
      if (track.clips.isNotEmpty && !primaryReplaced) {
        newAudioTracks.add(newAudioTrack);
        primaryReplaced = true;
      } else {
        newAudioTracks.add(track);
      }
    }
    if (!primaryReplaced) {
      newAudioTracks.add(newAudioTrack);
    }

    final synced = _buildProject(original, newAudioTracks);

    return MultiPointSyncResult(
      syncedProject: synced,
      anchorPoints: anchors,
      isSegmented: newAudioClips.length > 1,
      segmentCount: newAudioClips.length,
    );
  }

  /// ──────────────────────────────────────────────────────────────
  /// 策略B：字幕匹配同步（原逻辑）
  /// ──────────────────────────────────────────────────────────────
  Future<MultiPointSyncResult> _syncBySubtitleMatching(
    TimelineProject originalProject,
  ) async {
    // ── 1. 获取字幕 ────────────────────────────────────────────
    final videoSubtitles =
        originalProject.videoTrack?.linkedSubtitleTrack?.clips ?? [];
    final videoClips = originalProject.videoTrack?.clips ?? [];

    if (videoSubtitles.isEmpty) {
      throw Exception('视频轨道没有字幕，请先为视频导入字幕');
    }

    final audioTrackWithSub = originalProject.audioTracks
        .where((t) => t.linkedSubtitleTrack?.clips.isNotEmpty == true)
        .toList();

    if (audioTrackWithSub.isEmpty) {
      throw Exception('音频轨道没有字幕，请先为音频导入字幕');
    }

    final audioTrack = audioTrackWithSub.first;
    final audioSubtitles = audioTrack.linkedSubtitleTrack!.clips;

    // ── 2. 一对一字幕匹配 ──────────────────────────────────────
    final videoContexts =
        _matchingService.buildContexts(videoSubtitles, -1);
    final audioContexts =
        _matchingService.buildContexts(audioSubtitles, 0);

    final matches = _matchingService.findOneToOneMatches(
      videoContexts,
      audioContexts,
    );

    if (matches.isEmpty) {
      throw Exception(
        '未找到匹配的字幕。\n'
        '视频字幕：${videoSubtitles.length}条，音频字幕：${audioSubtitles.length}条',
      );
    }

    // ── 3. 构建锚点并计算偏移 ──────────────────────────────────
    final anchors = <AnchorPoint>[];
    for (final match in matches) {
      final vSub = match.videoContext.target;
      final aSub = match.audioContext.target;
      final offset = vSub.timelineStartMs - aSub.timelineStartMs;
      anchors.add(AnchorPoint(
        videoSubtitle: vSub,
        audioSubtitle: aSub,
        confidence: match.confidence,
        offsetMs: offset,
      ));
    }

    // 按音频字幕时间排序锚点（用于确定分段边界）
    anchors.sort((a, b) =>
        a.audioSubtitle.timelineStartMs
            .compareTo(b.audioSubtitle.timelineStartMs));

    // ── 4. 判断裁切策略 ────────────────────────────────────────
    final offsets = anchors.map((a) => a.offsetMs).toList();
    final minOffset = offsets.reduce((a, b) => a < b ? a : b);
    final maxOffset = offsets.reduce((a, b) => a > b ? a : b);
    final offsetSpread = maxOffset - minOffset;

    const toleranceMs = 50; // 50ms 容差
    final needSegmentation = offsetSpread > toleranceMs;

    if (!needSegmentation) {
      // 全局偏移模式：所有锚点偏移量一致，无需分段
      return _applyGlobalOffset(
        originalProject,
        anchors,
        audioTrack,
      );
    }

    // ── 5. 分段裁切模式 ────────────────────────────────────────
    final isMultiVideoClip = videoClips.length > 1;

    if (isMultiVideoClip) {
      return _segmentByVideoClips(
        originalProject,
        anchors,
        audioTrack,
        videoClips,
      );
    } else {
      return _segmentBySubtitleAnchors(
        originalProject,
        anchors,
        audioTrack,
      );
    }
  }

  /// 全局偏移模式（偏移量一致时使用）
  MultiPointSyncResult _applyGlobalOffset(
    TimelineProject original,
    List<AnchorPoint> anchors,
    TimelineTrack audioTrack,
  ) {
    // 使用中位数偏移量（比平均值更抗干扰）
    final sortedOffsets = anchors.map((a) => a.offsetMs).toList()..sort();
    final medianOffset = sortedOffsets[sortedOffsets.length ~/ 2];

    // 移动所有音频轨道
    final newAudioTracks = original.audioTracks.map((track) {
      return _shiftTrack(track, medianOffset);
    }).toList();

    final synced = _buildProject(original, newAudioTracks);

    return MultiPointSyncResult(
      syncedProject: synced,
      anchorPoints: anchors,
      isSegmented: false,
      segmentCount: 1,
    );
  }

  /// 按视频片段裁切（多视频片段模式）
  MultiPointSyncResult _segmentByVideoClips(
    TimelineProject original,
    List<AnchorPoint> anchors,
    TimelineTrack audioTrack,
    List<TimelineClip> videoClips,
  ) {
    final newAudioClips = <TimelineClip>[];
    final newAudioSubtitles = <TimelineClip>[];

    // 为每个视频片段找对应的音频段
    for (final videoClip in videoClips) {
      // 找到属于这个视频片段的锚点
      final clipAnchors = anchors.where((a) =>
          a.videoSubtitle.timelineStartMs >= videoClip.timelineStartMs &&
          a.videoSubtitle.timelineStartMs < videoClip.timelineEndMs);

      if (clipAnchors.isEmpty) continue;

      // 使用第一个锚点（已按时间排序）
      final anchor = clipAnchors.first;

      // 计算音频段的源文件位置
      // 音频字幕位置 - (视频字幕位置 - 视频片段起始) = 音频段在源文件中的起始
      final audioSegmentSourceStart = anchor.audioSubtitle.timelineStartMs -
          (anchor.videoSubtitle.timelineStartMs - videoClip.timelineStartMs);

      // 确保不超出源文件范围
      final safeStart = audioSegmentSourceStart < 0 ? 0 : audioSegmentSourceStart;
      final duration = videoClip.durationMs;

      // 创建音频段
      newAudioClips.add(TimelineClip(
        filePath: audioTrack.clips.first.filePath,
        fileName: audioTrack.clips.first.fileName,
        timelineStartMs: videoClip.timelineStartMs,
        durationMs: duration,
        mediaIndex: -1,
        sourceStartMs: safeStart,
      ));

      // 重新定位该视频片段范围内的音频字幕
      final clipSubtitles = audioTrack.linkedSubtitleTrack?.clips
          .where((s) =>
              s.timelineStartMs >= anchor.audioSubtitle.timelineStartMs - 5000 &&
              s.timelineStartMs < anchor.audioSubtitle.timelineStartMs + duration)
          .toList() ?? [];

      for (final sub in clipSubtitles) {
        final relativeToAnchor = sub.timelineStartMs - anchor.audioSubtitle.timelineStartMs;
        newAudioSubtitles.add(sub.copyWith(
          timelineStartMs: anchor.videoSubtitle.timelineStartMs + relativeToAnchor,
        ));
      }
    }

    // 构建新的音频轨道
    final newAudioTrack = TimelineTrack(
      type: TrackType.audio,
      clips: newAudioClips,
      linkedSubtitleTrack: newAudioSubtitles.isNotEmpty
          ? TimelineTrack(type: TrackType.subtitle, clips: newAudioSubtitles)
          : null,
    );

    // 保留其他音频轨道（不处理）
    final newAudioTracks = <TimelineTrack>[];
    bool primaryReplaced = false;
    for (final track in original.audioTracks) {
      if (track.linkedSubtitleTrack?.clips.isNotEmpty == true && !primaryReplaced) {
        newAudioTracks.add(newAudioTrack);
        primaryReplaced = true;
      } else {
        newAudioTracks.add(track);
      }
    }

    final synced = _buildProject(original, newAudioTracks);

    return MultiPointSyncResult(
      syncedProject: synced,
      anchorPoints: anchors,
      isSegmented: true,
      segmentCount: newAudioClips.length,
    );
  }

  /// 按字幕锚点裁切（单视频片段模式）
  MultiPointSyncResult _segmentBySubtitleAnchors(
    TimelineProject original,
    List<AnchorPoint> anchors,
    TimelineTrack audioTrack,
  ) {
    final audioClip = audioTrack.clips.first;
    final audioTotalDuration = audioClip.durationMs;
    final audioFileStart = audioClip.timelineStartMs;

    // 计算分段边界：以相邻音频字幕中点为界
    final boundaries = <int>[];

    // 起始边界
    boundaries.add(audioFileStart);

    for (int i = 0; i < anchors.length - 1; i++) {
      final currentAudioSub = anchors[i].audioSubtitle.timelineStartMs;
      final nextAudioSub = anchors[i + 1].audioSubtitle.timelineStartMs;
      final midpoint = (currentAudioSub + nextAudioSub) ~/ 2;
      boundaries.add(midpoint);
    }

    // 结束边界
    boundaries.add(audioFileStart + audioTotalDuration);

    // 为每段创建音频片段
    final newAudioClips = <TimelineClip>[];
    final newAudioSubtitles = <TimelineClip>[];

    for (int i = 0; i < anchors.length; i++) {
      final anchor = anchors[i];
      final segStart = boundaries[i];
      final segEnd = boundaries[i + 1];
      final segDuration = segEnd - segStart;

      if (segDuration <= 0) continue;

      // 源文件偏移：该段在源文件中的起始位置
      final sourceOffset = segStart - audioFileStart + audioClip.sourceStartMs;

      // 时间线位置：源段起始 + 锚点偏移
      final timelinePos = segStart + anchor.offsetMs;

      newAudioClips.add(TimelineClip(
        filePath: audioClip.filePath,
        fileName: audioClip.fileName,
        timelineStartMs: timelinePos,
        durationMs: segDuration,
        mediaIndex: -1,
        sourceStartMs: sourceOffset < 0 ? 0 : sourceOffset,
      ));

      // 该段内的音频字幕也跟着移动
      final segSubtitles = audioTrack.linkedSubtitleTrack?.clips
              .where((s) =>
                  s.timelineStartMs >= segStart &&
                  s.timelineStartMs < segEnd)
              .toList() ??
          [];

      for (final sub in segSubtitles) {
        final relativePos = sub.timelineStartMs - segStart;
        newAudioSubtitles.add(sub.copyWith(
          timelineStartMs: timelinePos + relativePos,
        ));
      }
    }

    // 构建新的音频轨道
    final newAudioTrack = TimelineTrack(
      type: TrackType.audio,
      clips: newAudioClips,
      linkedSubtitleTrack: newAudioSubtitles.isNotEmpty
          ? TimelineTrack(type: TrackType.subtitle, clips: newAudioSubtitles)
          : null,
    );

    // 保留其他音频轨道
    final newAudioTracks = <TimelineTrack>[];
    bool primaryReplaced = false;
    for (final track in original.audioTracks) {
      if (track.linkedSubtitleTrack?.clips.isNotEmpty == true && !primaryReplaced) {
        newAudioTracks.add(newAudioTrack);
        primaryReplaced = true;
      } else {
        newAudioTracks.add(track);
      }
    }

    final synced = _buildProject(original, newAudioTracks);

    return MultiPointSyncResult(
      syncedProject: synced,
      anchorPoints: anchors,
      isSegmented: true,
      segmentCount: newAudioClips.length,
    );
  }

  /// 整体移动一条轨道（片段+字幕）
  TimelineTrack _shiftTrack(TimelineTrack track, int offsetMs) {
    final newClips = track.clips
        .map((c) => c.copyWith(timelineStartMs: c.timelineStartMs + offsetMs))
        .toList();

    final newSubtitleTrack = track.linkedSubtitleTrack == null
        ? null
        : TimelineTrack(
            type: TrackType.subtitle,
            clips: track.linkedSubtitleTrack!.clips
                .map((c) =>
                    c.copyWith(timelineStartMs: c.timelineStartMs + offsetMs))
                .toList(),
          );

    return TimelineTrack(
      type: track.type,
      clips: newClips,
      linkedSubtitleTrack: newSubtitleTrack,
    );
  }

  /// 构建新的 TimelineProject
  TimelineProject _buildProject(
    TimelineProject original,
    List<TimelineTrack> newAudioTracks,
  ) {
    final maxVideoEnd = original.videoTrack?.clips.fold<int>(
          0,
          (m, c) => c.timelineEndMs > m ? c.timelineEndMs : m,
        ) ??
        0;

    final maxAudioEnd = newAudioTracks.fold<int>(
      0,
      (m, track) =>
          track.clips.fold<int>(m, (mm, c) => c.timelineEndMs > mm ? c.timelineEndMs : mm),
    );

    return TimelineProject(
      videoTrack: original.videoTrack,
      audioTracks: newAudioTracks,
      subtitleTrack: original.subtitleTrack,
      durationMs: maxVideoEnd > maxAudioEnd ? maxVideoEnd : maxAudioEnd,
      sourceTimecodes: original.sourceTimecodes,
      isSyncedProject: true,
    );
  }
}
