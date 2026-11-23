import 'dart:convert';
import 'timeline_model.dart';

/// ASR 合板工程状态
enum AsrProjectStatus {
  empty('empty', '待导入'),
  ready('ready', '待识别'),
  recognizing('recognizing', '识别中'),
  recognized('recognized', '待匹配'),
  matched('matched', '待确认'),
  completed('completed', '已完成'),
  error('error', '出错');

  const AsrProjectStatus(this.value, this.label);
  final String value;
  final String label;

  static AsrProjectStatus fromString(String v) {
    return AsrProjectStatus.values.firstWhere(
      (e) => e.value == v,
      orElse: () => AsrProjectStatus.empty,
    );
  }
}

/// 视频-音频匹配对
class MatchPair {
  const MatchPair({
    required this.videoFilePath,
    required this.audioFilePath,
    required this.confidence,
    required this.offsetMs,
    required this.matchedWindowCount,
    required this.totalWindowCount,
    this.isConsistent = true,
    this.isUserConfirmed = false,
    this.isManualMatch = false,
  });

  final String videoFilePath;
  final String audioFilePath;
  final double confidence;
  final int offsetMs;
  final int matchedWindowCount;
  final int totalWindowCount;
  final bool isConsistent;
  final bool isUserConfirmed;
  final bool isManualMatch;

  /// 置信度等级：高/中/低
  String get confidenceLabel {
    if (confidence >= 0.9) return '高';
    if (confidence >= 0.7) return '中';
    return '低';
  }

  Map<String, dynamic> toJson() => {
        'videoFilePath': videoFilePath,
        'audioFilePath': audioFilePath,
        'confidence': confidence,
        'offsetMs': offsetMs,
        'matchedWindowCount': matchedWindowCount,
        'totalWindowCount': totalWindowCount,
        'isConsistent': isConsistent,
        'isUserConfirmed': isUserConfirmed,
        'isManualMatch': isManualMatch,
      };

  factory MatchPair.fromJson(Map<String, dynamic> json) => MatchPair(
        videoFilePath: json['videoFilePath'] as String,
        audioFilePath: json['audioFilePath'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        offsetMs: json['offsetMs'] as int,
        matchedWindowCount: json['matchedWindowCount'] as int,
        totalWindowCount: json['totalWindowCount'] as int,
        isConsistent: json['isConsistent'] as bool? ?? true,
        isUserConfirmed: json['isUserConfirmed'] as bool? ?? false,
        isManualMatch: json['isManualMatch'] as bool? ?? false,
      );

  MatchPair copyWith({
    bool? isUserConfirmed,
    bool? isManualMatch,
    double? confidence,
    int? offsetMs,
  }) =>
      MatchPair(
        videoFilePath: videoFilePath,
        audioFilePath: audioFilePath,
        confidence: confidence ?? this.confidence,
        offsetMs: offsetMs ?? this.offsetMs,
        matchedWindowCount: matchedWindowCount,
        totalWindowCount: totalWindowCount,
        isConsistent: isConsistent,
        isUserConfirmed: isUserConfirmed ?? this.isUserConfirmed,
        isManualMatch: isManualMatch ?? this.isManualMatch,
      );
}

/// ASR 合板工程
class AsrProject {
  AsrProject({
    required this.id,
    required this.name,
    this.videoDirectory,
    this.audioDirectory,
    List<String>? videoFiles,
    List<String>? audioFiles,
    this.status = AsrProjectStatus.empty,
    this.asrLanguage = 'zh',
    this.asrEngine = 'sensevoice',
    this.asrModel = 'ggml-medium.bin',
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, List<TimelineClip>>? videoSubtitles,
    Map<String, List<TimelineClip>>? audioSubtitles,
    List<MatchPair>? matchPairs,
    this.timelineProjectId,
  })  : videoFiles = videoFiles ?? [],
        audioFiles = audioFiles ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        _videoSubtitles = videoSubtitles,
        _audioSubtitles = audioSubtitles,
        _matchPairs = matchPairs;

  final String id;
  String name;
  String? videoDirectory;
  String? audioDirectory;
  final List<String> videoFiles;
  final List<String> audioFiles;
  AsrProjectStatus status;
  String asrLanguage;
  String asrEngine;
  String asrModel;
  DateTime createdAt;
  DateTime updatedAt;
  final String? timelineProjectId;

  // 识别结果（延迟序列化）
  Map<String, List<TimelineClip>>? _videoSubtitles;
  Map<String, List<TimelineClip>>? _audioSubtitles;
  List<MatchPair>? _matchPairs;

  // JSON 序列化用的原始字符串
  String? _videoSubtitlesJson;
  String? _audioSubtitlesJson;
  String? _matchPairsJson;

  Map<String, List<TimelineClip>> get videoSubtitles {
    if (_videoSubtitles == null && _videoSubtitlesJson != null) {
      _videoSubtitles = _deserializeSubtitleMap(_videoSubtitlesJson!);
    }
    return _videoSubtitles ?? {};
  }

  set videoSubtitles(Map<String, List<TimelineClip>> v) {
    _videoSubtitles = v;
    _videoSubtitlesJson = null;
  }

  Map<String, List<TimelineClip>> get audioSubtitles {
    if (_audioSubtitles == null && _audioSubtitlesJson != null) {
      _audioSubtitles = _deserializeSubtitleMap(_audioSubtitlesJson!);
    }
    return _audioSubtitles ?? {};
  }

  set audioSubtitles(Map<String, List<TimelineClip>> v) {
    _audioSubtitles = v;
    _audioSubtitlesJson = null;
  }

  List<MatchPair> get matchPairs {
    if (_matchPairs == null && _matchPairsJson != null) {
      final list = jsonDecode(_matchPairsJson!) as List;
      _matchPairs = list.map((e) => MatchPair.fromJson(e as Map<String, dynamic>)).toList();
    }
    return _matchPairs ?? [];
  }

  set matchPairs(List<MatchPair> v) {
    _matchPairs = v;
    _matchPairsJson = null;
  }

  /// 视频文件数量
  int get videoCount => videoFiles.length;

  /// 音频文件数量
  int get audioCount => audioFiles.length;

  /// 是否有素材
  bool get hasMedia => videoFiles.isNotEmpty && audioFiles.isNotEmpty;

  // ========== 序列化 ==========

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'videoDirectory': videoDirectory,
        'audioDirectory': audioDirectory,
        'videoFiles': jsonEncode(videoFiles),
        'audioFiles': jsonEncode(audioFiles),
        'status': status.value,
        'asrLanguage': asrLanguage,
        'asrEngine': asrEngine,
        'asrModel': asrModel,
        'videoSubtitles': _serializeSubtitleMap(_videoSubtitles),
        'audioSubtitles': _serializeSubtitleMap(_audioSubtitles),
        'matchPairs': _matchPairs != null
            ? jsonEncode(_matchPairs!.map((e) => e.toJson()).toList())
            : null,
        'timelineProjectId': timelineProjectId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AsrProject.fromMap(Map<String, dynamic> map) {
    final project = AsrProject(
      id: map['id'] as String,
      name: map['name'] as String,
      videoDirectory: map['video_directory'] as String?,
      audioDirectory: map['audio_directory'] as String?,
      videoFiles: _parseJsonList(map['video_files'] as String?),
      audioFiles: _parseJsonList(map['audio_files'] as String?),
      status: AsrProjectStatus.fromString(map['status'] as String),
      asrLanguage: map['asr_language'] as String? ?? 'zh',
      asrEngine: map['asr_engine'] as String? ?? 'sensevoice',
      asrModel: map['asr_model'] as String? ?? 'ggml-medium.bin',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      timelineProjectId: map['timeline_project_id'] as String?,
    );

    // 延迟反序列化大数据字段
    project._videoSubtitlesJson = map['video_subtitles'] as String?;
    project._audioSubtitlesJson = map['audio_subtitles'] as String?;
    project._matchPairsJson = map['match_pairs'] as String?;

    return project;
  }

  // ========== 辅助方法 ==========

  static List<String> _parseJsonList(String? json) {
    if (json == null || json.isEmpty) return [];
    return (jsonDecode(json) as List).cast<String>();
  }

  static String? _serializeSubtitleMap(Map<String, List<TimelineClip>>? map) {
    if (map == null || map.isEmpty) return null;
    final serializable = map.map((k, v) => MapEntry(k, v.map((c) => c.toJson()).toList()));
    return jsonEncode(serializable);
  }

  static Map<String, List<TimelineClip>> _deserializeSubtitleMap(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(
          k,
          (v as List).map((e) => TimelineClip.fromJson(e as Map<String, dynamic>)).toList(),
        ));
  }
}
