import 'dart:convert';
import 'database_service.dart';
import '../models/asr_project.dart';

/// ASR 合板工程管理服务
class AsrProjectService {
  /// 获取所有工程
  static Future<List<AsrProject>> getAllProjects() async {
    final maps = await DatabaseService.getAllAsrProjects();
    return maps.map((m) => AsrProject.fromMap(m)).toList();
  }

  /// 获取单个工程
  static Future<AsrProject?> getProject(String id) async {
    final map = await DatabaseService.getAsrProject(id);
    if (map == null) return null;
    return AsrProject.fromMap(map);
  }

  /// 创建新工程
  static Future<AsrProject> createProject({required String name}) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final project = AsrProject(id: id, name: name);
    await _saveProject(project);
    return project;
  }

  /// 保存工程（全量更新）
  static Future<void> _saveProject(AsrProject project) async {
    final json = project.toJson();
    final map = <String, dynamic>{
      'id': json['id'],
      'name': json['name'],
      'video_directory': json['videoDirectory'],
      'audio_directory': json['audioDirectory'],
      'video_files': json['videoFiles'],
      'audio_files': json['audioFiles'],
      'status': json['status'],
      'asr_language': json['asrLanguage'],
      'asr_engine': json['asrEngine'],
      'asr_model': json['asrModel'],
      'video_subtitles': json['videoSubtitles'],
      'audio_subtitles': json['audioSubtitles'],
      'match_pairs': json['matchPairs'],
      'timeline_project_id': json['timelineProjectId'],
      'created_at': json['createdAt'],
      'updated_at': json['updatedAt'],
    };
    await DatabaseService.insertAsrProject(map);
  }

  /// 更新工程（部分字段）
  static Future<void> updateProject(AsrProject project) async {
    final json = project.toJson();
    final map = <String, dynamic>{
      'name': json['name'],
      'video_directory': json['videoDirectory'],
      'audio_directory': json['audioDirectory'],
      'video_files': json['videoFiles'],
      'audio_files': json['audioFiles'],
      'status': json['status'],
      'asr_language': json['asrLanguage'],
      'asr_engine': json['asrEngine'],
      'asr_model': json['asrModel'],
      'video_subtitles': json['videoSubtitles'],
      'audio_subtitles': json['audioSubtitles'],
      'match_pairs': json['matchPairs'],
      'timeline_project_id': json['timelineProjectId'],
      'updated_at': json['updatedAt'],
    };
    await DatabaseService.updateAsrProject(project.id, map);
  }

  /// 删除工程
  static Future<void> deleteProject(String id) async {
    await DatabaseService.deleteAsrProject(id);
  }

  /// 设置视频文件列表
  static Future<void> setVideoFiles(AsrProject project, String directory, List<String> files) async {
    project.videoDirectory = directory;
    project.videoFiles.clear();
    project.videoFiles.addAll(files);
    project.status = project.hasMedia ? AsrProjectStatus.ready : AsrProjectStatus.empty;
    project.updatedAt = DateTime.now();
    await updateProject(project);
  }

  /// 设置音频文件列表
  static Future<void> setAudioFiles(AsrProject project, String directory, List<String> files) async {
    project.audioDirectory = directory;
    project.audioFiles.clear();
    project.audioFiles.addAll(files);
    project.status = project.hasMedia ? AsrProjectStatus.ready : AsrProjectStatus.empty;
    project.updatedAt = DateTime.now();
    await updateProject(project);
  }

  /// 保存识别结果
  static Future<void> saveRecognitionResults(
    AsrProject project, {
    Map<String, List<dynamic>>? videoSubs,
    Map<String, List<dynamic>>? audioSubs,
  }) async {
    if (videoSubs != null) {
      final converted = <String, List<dynamic>>{};
      videoSubs.forEach((k, v) => converted[k] = v);
    }
    if (audioSubs != null) {
      final converted = <String, List<dynamic>>{};
      audioSubs.forEach((k, v) => converted[k] = v);
    }
    project.updatedAt = DateTime.now();
    await updateProject(project);
  }

  /// 保存匹配结果
  static Future<void> saveMatchResults(AsrProject project, List<dynamic> pairs) async {
    project.status = AsrProjectStatus.matched;
    project.updatedAt = DateTime.now();
    await updateProject(project);
  }
}
