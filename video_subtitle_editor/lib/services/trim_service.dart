import '../models/timeline_model.dart';

/// 一键修剪结果
class TrimResult {
  const TrimResult({
    required this.videoTrack,
    required this.audioTracks,
    required this.totalGapRemovedMs,
    required this.originalDurationMs,
    required this.newDurationMs,
  });

  final TimelineTrack videoTrack;
  final List<TimelineTrack> audioTracks;
  final int totalGapRemovedMs;
  final int originalDurationMs;
  final int newDurationMs;

  String get formattedGapRemoved {
    final minutes = totalGapRemovedMs ~/ 60000;
    final seconds = (totalGapRemovedMs % 60000) ~/ 1000;
    if (minutes > 0) return '$minutes 分 $seconds 秒';
    return '$seconds 秒';
  }
}

/// 一键修剪服务：裁切音频 + 压缩视频间空白
class TrimService {
  /// 执行一键修剪
  ///
  /// 步骤：
  /// 1. 按视频片段时间范围裁切音频为多段
  /// 2. 计算压缩偏移量（消除视频间空白）
  /// 3. 应用压缩到视频、音频、字幕
  TrimResult trim(TimelineProject project) {
    final videoClips = project.videoTrack?.clips ?? [];
    if (videoClips.isEmpty) {
      return TrimResult(
        videoTrack: project.videoTrack ?? TimelineTrack(type: TrackType.video),
        audioTracks: project.audioTracks,
        totalGapRemovedMs: 0,
        originalDurationMs: project.durationMs,
        newDurationMs: project.durationMs,
      );
    }

    // ── 步骤1：按时间排序视频片段 ──────────────────────────────
    final sortedVideos = List<TimelineClip>.from(videoClips)
      ..sort((a, b) => a.timelineStartMs.compareTo(b.timelineStartMs));

    // ── 步骤2：计算压缩偏移量 ──────────────────────────────────
    // 每个视频片段压缩后的新起始位置
    final compactStarts = <String, int>{}; // clipId → 新起始位置
    int cursor = 0;
    for (final video in sortedVideos) {
      compactStarts[video.id] = cursor;
      cursor += video.durationMs;
    }

    // 总共清理的空白时长
    final originalSpan = sortedVideos.last.timelineEndMs - sortedVideos.first.timelineStartMs;
    final totalVideoMs = sortedVideos.fold<int>(0, (sum, c) => sum + c.durationMs);
    final totalGapMs = originalSpan - totalVideoMs;

    // ── 步骤3：压缩视频片段 ────────────────────────────────────
    final compactedVideos = sortedVideos.map((v) {
      return v.copyWith(timelineStartMs: compactStarts[v.id]!);
    }).toList();

    // ── 步骤4：压缩视频字幕 ────────────────────────────────────
    TimelineTrack? compactedVideoSubtitleTrack;
    if (project.videoTrack?.linkedSubtitleTrack != null) {
      final compactedSubs = _compactSubtitles(
        project.videoTrack!.linkedSubtitleTrack!.clips,
        sortedVideos,
        compactStarts,
      );
      compactedVideoSubtitleTrack = TimelineTrack(
        type: TrackType.subtitle,
        clips: compactedSubs,
      );
    }

    final compactedVideoTrack = TimelineTrack(
      type: TrackType.video,
      clips: compactedVideos,
      linkedSubtitleTrack: compactedVideoSubtitleTrack,
    );

    // ── 步骤5：裁切音频并压缩 ──────────────────────────────────
    final compactedAudioTracks = <TimelineTrack>[];
    for (final audioTrack in project.audioTracks) {
      final trimmedAudioClips = <TimelineClip>[];
      final trimmedSubtitleClips = <TimelineClip>[];

      for (final video in sortedVideos) {
        final newStart = compactStarts[video.id]!;

        // 从音频轨道中提取与该视频时间范围重叠的部分
        final audioSegment = _extractAudioSegment(
          audioTrack: audioTrack,
          sourceStart: video.timelineStartMs,
          sourceEnd: video.timelineEndMs,
          targetStart: newStart,
        );

        if (audioSegment != null) {
          trimmedAudioClips.add(audioSegment);
        }

        // 提取对应的字幕段落
        if (audioTrack.linkedSubtitleTrack != null) {
          final subSegments = _extractSubtitleSegments(
            audioTrack.linkedSubtitleTrack!.clips,
            video.timelineStartMs,
            video.timelineEndMs,
            newStart,
          );
          trimmedSubtitleClips.addAll(subSegments);
        }
      }

      compactedAudioTracks.add(TimelineTrack(
        type: TrackType.audio,
        clips: trimmedAudioClips,
        linkedSubtitleTrack: trimmedSubtitleClips.isNotEmpty
            ? TimelineTrack(type: TrackType.subtitle, clips: trimmedSubtitleClips)
            : null,
      ));
    }

    final newDuration = cursor; // cursor 就是所有视频片段总时长

    return TrimResult(
      videoTrack: compactedVideoTrack,
      audioTracks: compactedAudioTracks,
      totalGapRemovedMs: totalGapMs > 0 ? totalGapMs : 0,
      originalDurationMs: project.durationMs,
      newDurationMs: newDuration,
    );
  }

  // ── 私有方法 ──────────────────────────────────────────────────

  /// 从音频轨道中提取 [sourceStart, sourceEnd) 范围内的片段
  /// 并将其放置到 targetStart 位置
  TimelineClip? _extractAudioSegment({
    required TimelineTrack audioTrack,
    required int sourceStart,
    required int sourceEnd,
    required int targetStart,
  }) {
    for (final audioClip in audioTrack.clips) {
      final clipStart = audioClip.timelineStartMs;
      final clipEnd = audioClip.timelineEndMs;

      // 计算交集
      final intersectStart = sourceStart > clipStart ? sourceStart : clipStart;
      final intersectEnd = sourceEnd < clipEnd ? sourceEnd : clipEnd;

      if (intersectStart < intersectEnd) {
        final duration = intersectEnd - intersectStart;
        // 在源文件内的偏移量（叠加已有 sourceStartMs）
        final inFileOffset = audioClip.sourceStartMs + (intersectStart - clipStart);

        return TimelineClip(
          filePath: audioClip.filePath,
          fileName: audioClip.fileName,
          timelineStartMs: targetStart,
          durationMs: duration,
          mediaIndex: audioClip.mediaIndex,
          sourceStartMs: inFileOffset,
        );
      }
    }
    return null;
  }

  /// 提取 [sourceStart, sourceEnd) 范围内的字幕，并移动到 targetStart 对应位置
  List<TimelineClip> _extractSubtitleSegments(
    List<TimelineClip> subtitles,
    int sourceStart,
    int sourceEnd,
    int targetStart,
  ) {
    final result = <TimelineClip>[];
    for (final sub in subtitles) {
      if (sub.timelineStartMs >= sourceStart && sub.timelineStartMs < sourceEnd) {
        final relativePos = sub.timelineStartMs - sourceStart;
        result.add(sub.copyWith(
          timelineStartMs: targetStart + relativePos,
        ));
      }
    }
    return result;
  }

  /// 压缩字幕位置（跟随视频片段移动）
  List<TimelineClip> _compactSubtitles(
    List<TimelineClip> subtitles,
    List<TimelineClip> sortedVideos,
    Map<String, int> compactStarts,
  ) {
    final result = <TimelineClip>[];
    for (final sub in subtitles) {
      // 找到该字幕所属的视频片段
      TimelineClip? parentVideo;
      for (final v in sortedVideos) {
        if (sub.timelineStartMs >= v.timelineStartMs &&
            sub.timelineStartMs < v.timelineEndMs) {
          parentVideo = v;
          break;
        }
      }
      if (parentVideo == null) continue;

      final newVideoStart = compactStarts[parentVideo.id]!;
      final relativePos = sub.timelineStartMs - parentVideo.timelineStartMs;
      result.add(sub.copyWith(
        timelineStartMs: newVideoStart + relativePos,
      ));
    }
    return result;
  }
}
