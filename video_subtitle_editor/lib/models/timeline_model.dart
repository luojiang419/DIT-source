
class TimelineClip {
  TimelineClip({
    String? id,
    required this.filePath,
    required this.fileName,
    required this.timelineStartMs,
    required this.durationMs,
    required this.mediaIndex,
    this.text,
    this.sourceStartMs = 0,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final String filePath;
  final String fileName;
  final int timelineStartMs;
  final int durationMs;
  final int mediaIndex;
  final String? text;

  /// 在源文件中的起始位置（毫秒）。0=从文件开头播放。
  /// 用于音频分段裁切后记录每段在源文件中的起始偏移。
  final int sourceStartMs;

  int get timelineEndMs => timelineStartMs + durationMs;

  TimelineClip copyWith({
    String? id,
    String? filePath,
    String? fileName,
    int? timelineStartMs,
    int? durationMs,
    int? mediaIndex,
    String? text,
    int? sourceStartMs,
  }) {
    return TimelineClip(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      timelineStartMs: timelineStartMs ?? this.timelineStartMs,
      durationMs: durationMs ?? this.durationMs,
      mediaIndex: mediaIndex ?? this.mediaIndex,
      text: text ?? this.text,
      sourceStartMs: sourceStartMs ?? this.sourceStartMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'fileName': fileName,
        'timelineStartMs': timelineStartMs,
        'durationMs': durationMs,
        'mediaIndex': mediaIndex,
        if (text != null) 'text': text,
        if (sourceStartMs != 0) 'sourceStartMs': sourceStartMs,
      };

  factory TimelineClip.fromJson(Map<String, dynamic> json) => TimelineClip(
        id: json['id'],
        filePath: json['filePath'],
        fileName: json['fileName'],
        timelineStartMs: json['timelineStartMs'],
        durationMs: json['durationMs'],
        mediaIndex: json['mediaIndex'],
        text: json['text'],
        sourceStartMs: json['sourceStartMs'] as int? ?? 0,
      );
}

class TimelineTrack {
  TimelineTrack({
    required this.type, 
    this.clips = const [],
    this.linkedSubtitleTrack,
  });

  final TrackType type;
  final List<TimelineClip> clips;
  final TimelineTrack? linkedSubtitleTrack;

  TimelineTrack copyWith({
    TrackType? type,
    List<TimelineClip>? clips,
    TimelineTrack? linkedSubtitleTrack,
  }) {
    return TimelineTrack(
      type: type ?? this.type,
      clips: clips ?? this.clips,
      linkedSubtitleTrack: linkedSubtitleTrack ?? this.linkedSubtitleTrack,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.index,
        'clips': clips.map((e) => e.toJson()).toList(),
        if (linkedSubtitleTrack != null) 'linkedSubtitleTrack': linkedSubtitleTrack!.toJson(),
      };

  factory TimelineTrack.fromJson(Map<String, dynamic> json) => TimelineTrack(
        type: TrackType.values[json['type']],
        clips: (json['clips'] as List)
            .map((e) => TimelineClip.fromJson(e))
            .toList(),
        linkedSubtitleTrack: json['linkedSubtitleTrack'] != null
            ? TimelineTrack.fromJson(json['linkedSubtitleTrack'])
            : null,
      );
}

enum TrackType {
  video,
  audio,
  subtitle,
}

// ─── 合板相关模型 ────────────────────────────────────────────────

/// 源时间码：24小时制绝对时间码（毫秒）
class SourceTimecode {
  const SourceTimecode({
    required this.filePath,
    required this.startMs,
    required this.durationMs,
  });

  final String filePath;
  final int startMs;    // 源起始时间码（毫秒，24h制）
  final int durationMs; // 文件录制时长

  /// 录制时间码 → 源时间码
  int toSource(int recordingMs) => startMs + recordingMs;

  /// 源时间码 → 录制时间码
  int toRecording(int sourceMs) => sourceMs - startMs;

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'startMs': startMs,
        'durationMs': durationMs,
      };

  factory SourceTimecode.fromJson(Map<String, dynamic> json) => SourceTimecode(
        filePath: json['filePath'] as String,
        startMs: json['startMs'] as int,
        durationMs: json['durationMs'] as int,
      );
}

/// 压缩信息：记录一键修剪后清理的空白数据
class CompactInfo {
  const CompactInfo({
    required this.totalGapRemovedMs,
    required this.clipOffsets,
  });

  final int totalGapRemovedMs;              // 总共清理的空白时长（毫秒）
  final Map<String, int> clipOffsets;       // clipId → 压缩偏移量（毫秒）

  Map<String, dynamic> toJson() => {
        'totalGapRemovedMs': totalGapRemovedMs,
        'clipOffsets': clipOffsets,
      };

  factory CompactInfo.fromJson(Map<String, dynamic> json) => CompactInfo(
        totalGapRemovedMs: json['totalGapRemovedMs'] as int,
        clipOffsets: Map<String, int>.from(json['clipOffsets'] as Map),
      );
}

// ─────────────────────────────────────────────────────────────────

class TimelineProject {
  TimelineProject({
    this.videoTrack,
    this.audioTracks = const [],
    this.subtitleTrack,
    this.durationMs = 0,
    this.sourceTimecodes = const {},
    this.isSyncedProject = false,
    this.originalProjectId,
    this.compactInfo,
    this.syncOffsetMs,
  });

  final TimelineTrack? videoTrack;
  final List<TimelineTrack> audioTracks;
  final TimelineTrack? subtitleTrack;
  final int durationMs;

  // ── 合板相关字段 ──
  /// filePath → SourceTimecode，记录每个文件的源时间码
  final Map<String, SourceTimecode> sourceTimecodes;
  /// 是否为合板项目
  final bool isSyncedProject;
  /// 原始项目ID（合板项目追溯用）
  final String? originalProjectId;
  /// 一键修剪后的压缩信息
  final CompactInfo? compactInfo;
  /// 合板时计算出的整体偏移量（毫秒），用于显示
  final int? syncOffsetMs;

  TimelineProject copyWith({
    TimelineTrack? videoTrack,
    List<TimelineTrack>? audioTracks,
    TimelineTrack? subtitleTrack,
    int? durationMs,
    Map<String, SourceTimecode>? sourceTimecodes,
    bool? isSyncedProject,
    String? originalProjectId,
    CompactInfo? compactInfo,
    int? syncOffsetMs,
  }) {
    return TimelineProject(
      videoTrack: videoTrack ?? this.videoTrack,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTrack: subtitleTrack ?? this.subtitleTrack,
      durationMs: durationMs ?? this.durationMs,
      sourceTimecodes: sourceTimecodes ?? this.sourceTimecodes,
      isSyncedProject: isSyncedProject ?? this.isSyncedProject,
      originalProjectId: originalProjectId ?? this.originalProjectId,
      compactInfo: compactInfo ?? this.compactInfo,
      syncOffsetMs: syncOffsetMs ?? this.syncOffsetMs,
    );
  }

  Map<String, dynamic> toJson() => {
        if (videoTrack != null) 'videoTrack': videoTrack!.toJson(),
        'audioTracks': audioTracks.map((e) => e.toJson()).toList(),
        if (subtitleTrack != null) 'subtitleTrack': subtitleTrack!.toJson(),
        'durationMs': durationMs,
        if (sourceTimecodes.isNotEmpty)
          'sourceTimecodes': sourceTimecodes.map((k, v) => MapEntry(k, v.toJson())),
        'isSyncedProject': isSyncedProject,
        if (originalProjectId != null) 'originalProjectId': originalProjectId,
        if (compactInfo != null) 'compactInfo': compactInfo!.toJson(),
        if (syncOffsetMs != null) 'syncOffsetMs': syncOffsetMs,
      };

  factory TimelineProject.fromJson(Map<String, dynamic> json) => TimelineProject(
        videoTrack: json['videoTrack'] != null
            ? TimelineTrack.fromJson(json['videoTrack'])
            : null,
        audioTracks: (json['audioTracks'] as List? ?? [])
            .map((e) => TimelineTrack.fromJson(e))
            .toList(),
        subtitleTrack: json['subtitleTrack'] != null
            ? TimelineTrack.fromJson(json['subtitleTrack'])
            : null,
        durationMs: json['durationMs'] ?? 0,
        sourceTimecodes: json['sourceTimecodes'] != null
            ? (json['sourceTimecodes'] as Map<String, dynamic>).map(
                (k, v) => MapEntry(k, SourceTimecode.fromJson(v as Map<String, dynamic>)),
              )
            : const {},
        isSyncedProject: json['isSyncedProject'] as bool? ?? false,
        originalProjectId: json['originalProjectId'] as String?,
        compactInfo: json['compactInfo'] != null
            ? CompactInfo.fromJson(json['compactInfo'] as Map<String, dynamic>)
            : null,
        syncOffsetMs: json['syncOffsetMs'] as int?,
      );
}
