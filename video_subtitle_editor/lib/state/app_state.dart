import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/project.dart';
import '../models/timeline_model.dart';
import '../services/database_service.dart';

class AppState extends ChangeNotifier {
  final List<Project> _projects = [];
  Project? _selectedProject;

  List<Project> get projects => List.unmodifiable(_projects);
  Project? get selectedProject => _selectedProject;

  AppState();

  /// 从 SQLite 加载所有项目
  Future<void> loadProjects() async {
    final maps = await DatabaseService.getAllProjects();
    _projects.clear();
    for (final map in maps) {
      final project = await _projectFromDb(map);
      _projects.add(project);
    }
    notifyListeners();
  }

  Future<Project> _projectFromDb(Map<String, dynamic> map) async {
    final projectId = map['id'] as String;
    TimelineProject? timelineProject;

    final timelineJson = await DatabaseService.getTimelineData(projectId);
    if (timelineJson != null) {
      try {
        timelineProject = TimelineProject.fromJson(
            jsonDecode(timelineJson) as Map<String, dynamic>);
      } catch (e) {
        print('解析时间线数据出错: $e');
      }
    }

    return Project(
      id: projectId,
      rootDir: map['root_dir'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      timelineProject: timelineProject,
      isSyncedProject: (map['is_synced_project'] as int) == 1,
      originalProjectId: map['original_project_id'] as String?,
      customDisplayName: map['custom_display_name'] as String?,
    );
  }

  Future<void> _saveProject(Project project) async {
    await DatabaseService.insertProject({
      'id': project.id,
      'root_dir': project.rootDir,
      'is_synced_project': project.isSyncedProject ? 1 : 0,
      'original_project_id': project.originalProjectId,
      'custom_display_name': project.customDisplayName,
      'created_at': project.createdAt.toIso8601String(),
      'updated_at': project.updatedAt.toIso8601String(),
    });
  }

  Future<void> addProjectFromDir(String dir) async {
    // 检查是否已存在
    final existingIndex = _projects.indexWhere((p) => p.rootDir == dir);
    if (existingIndex != -1) {
      final existing = _projects.removeAt(existingIndex);
      _projects.insert(0, existing);
      _selectedProject = existing;
      await DatabaseService.updateProject(existing.id, {
        'updated_at': DateTime.now().toIso8601String(),
      });
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    final id = _newId();
    final project = Project(
      id: id,
      rootDir: dir,
      createdAt: now,
      updatedAt: now,
    );
    _projects.insert(0, project);
    _selectedProject = project;
    await _saveProject(project);
    notifyListeners();
  }

  void selectProject(Project project) {
    _selectedProject = project;
    notifyListeners();
  }

  Future<void> deleteProjects(Set<String> projectIds) async {
    _projects.removeWhere((p) => projectIds.contains(p.id));
    if (_selectedProject != null && projectIds.contains(_selectedProject!.id)) {
      _selectedProject = _projects.isNotEmpty ? _projects.first : null;
    }
    await DatabaseService.deleteProjects(projectIds);
    notifyListeners();
  }

  Future<void> updateTimelineProject(String projectId, TimelineProject timelineProject) async {
    final index = _projects.indexWhere((p) => p.id == projectId);
    if (index != -1) {
      final updatedProject = _projects[index].copyWith(
        timelineProject: timelineProject,
        updatedAt: DateTime.now(),
      );
      _projects[index] = updatedProject;
      if (_selectedProject?.id == projectId) {
        _selectedProject = updatedProject;
      }
      // 保存时间线数据到 SQLite
      final timelineJson = jsonEncode(timelineProject.toJson());
      await DatabaseService.saveTimelineData(projectId, timelineJson);
      await DatabaseService.updateProject(projectId, {
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<Project> createSyncedProject({
    required Project originalProject,
    required TimelineProject syncedTimeline,
  }) async {
    final now = DateTime.now();
    final syncedProject = Project(
      id: _newId(),
      rootDir: originalProject.rootDir,
      createdAt: now,
      updatedAt: now,
      timelineProject: syncedTimeline,
      isSyncedProject: true,
      originalProjectId: originalProject.id,
      customDisplayName: '${originalProject.displayName}-合板',
    );
    _projects.insert(0, syncedProject);
    _selectedProject = syncedProject;
    await _saveProject(syncedProject);
    // 保存时间线
    final timelineJson = jsonEncode(syncedTimeline.toJson());
    await DatabaseService.saveTimelineData(syncedProject.id, timelineJson);
    notifyListeners();
    return syncedProject;
  }

  String _newId() {
    final rand = Random();
    final ms = DateTime.now().millisecondsSinceEpoch;
    final salt = rand.nextInt(1 << 32).toRadixString(16);
    return '$ms-$salt';
  }

  /// 从 ASR 合板页面创建同步项目
  Future<Project> addAsrSyncedProject(String name, TimelineProject timelineProject) async {
    final now = DateTime.now();
    final project = Project(
      id: _newId(),
      rootDir: name,
      createdAt: now,
      updatedAt: now,
      timelineProject: timelineProject,
      isSyncedProject: true,
      customDisplayName: name,
    );
    _projects.insert(0, project);
    _selectedProject = project;
    await _saveProject(project);
    final timelineJson = jsonEncode(timelineProject.toJson());
    await DatabaseService.saveTimelineData(project.id, timelineJson);
    notifyListeners();
    return project;
  }
}
