import 'timeline_model.dart';

class Project {
  Project({
    required this.id,
    required this.rootDir,
    required this.createdAt,
    required this.updatedAt,
    this.timelineProject,
    this.isSyncedProject = false,
    this.originalProjectId,
    this.customDisplayName,
  });

  final String id;
  final String rootDir;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TimelineProject? timelineProject;

  // ── 合板相关字段 ──
  final bool isSyncedProject;
  final String? originalProjectId;
  /// 自定义显示名称（合板项目用"原名-合板"）
  final String? customDisplayName;

  String get displayName {
    if (customDisplayName != null && customDisplayName!.isNotEmpty) {
      return customDisplayName!;
    }
    final normalized = rootDir.replaceAll('\\', '/');
    final parts = normalized.split('/').where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? rootDir : parts.last;
  }

  Project copyWith({
    String? id,
    String? rootDir,
    DateTime? createdAt,
    DateTime? updatedAt,
    TimelineProject? timelineProject,
    bool? isSyncedProject,
    String? originalProjectId,
    String? customDisplayName,
  }) {
    return Project(
      id: id ?? this.id,
      rootDir: rootDir ?? this.rootDir,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      timelineProject: timelineProject ?? this.timelineProject,
      isSyncedProject: isSyncedProject ?? this.isSyncedProject,
      originalProjectId: originalProjectId ?? this.originalProjectId,
      customDisplayName: customDisplayName ?? this.customDisplayName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rootDir': rootDir,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (timelineProject != null) 'timelineProject': timelineProject!.toJson(),
      'isSyncedProject': isSyncedProject,
      if (originalProjectId != null) 'originalProjectId': originalProjectId,
      if (customDisplayName != null) 'customDisplayName': customDisplayName,
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      rootDir: json['rootDir'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      timelineProject: json['timelineProject'] != null
          ? TimelineProject.fromJson(json['timelineProject'] as Map<String, dynamic>)
          : null,
      isSyncedProject: json['isSyncedProject'] as bool? ?? false,
      originalProjectId: json['originalProjectId'] as String?,
      customDisplayName: json['customDisplayName'] as String?,
    );
  }
}

