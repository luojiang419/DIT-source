import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import '../models/video_metadata.dart';
import '../models/video_directory.dart';

class DatabaseService {
  static Database? _database;
  static Completer<Database>? _initCompleter;

  static String get appDir {
    final exePath = Platform.resolvedExecutable;
    return path.dirname(exePath);
  }

  static Future<Database> get database async {
    if (_database != null) return _database!;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<Database>();
    try {
      _database = await _initDatabase();
      _initCompleter!.complete(_database!);
      return _database!;
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
    _initCompleter = null;
  }

  // ========== 数据库初始化 ==========

  static Future<Database> _initDatabase() async {
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final dbPath = path.join(appDir, 'data', 'app.db');
      final dbDir = path.dirname(dbPath);
      await Directory(dbDir).create(recursive: true);

      return await openDatabase(
        dbPath,
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      throw Exception('数据库初始化失败: $e');
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    // 应用设置表
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 项目表
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        root_dir TEXT NOT NULL,
        display_name TEXT,
        is_synced_project INTEGER NOT NULL DEFAULT 0,
        original_project_id TEXT,
        custom_display_name TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 时间线数据表
    await db.execute('''
      CREATE TABLE timeline_projects (
        project_id TEXT PRIMARY KEY,
        timeline_data TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');

    // 职员设置表
    await db.execute('''
      CREATE TABLE production_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id TEXT,
        production TEXT,
        cinematographer TEXT,
        operator TEXT,
        director TEXT,
        location TEXT,
        company TEXT,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
      )
    ''');

    // 视频目录表
    await db.execute('''
      CREATE TABLE video_directories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        project_id TEXT,
        added_at TEXT NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
      )
    ''');

    // 视频元数据表
    await db.execute('''
      CREATE TABLE video_metadata (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        root_path TEXT NOT NULL,
        project_id TEXT,
        file_path TEXT NOT NULL UNIQUE,
        file_name TEXT NOT NULL,
        relative_path TEXT,
        duration TEXT,
        resolution TEXT,
        codec TEXT,
        frame_rate TEXT,
        bitrate TEXT,
        file_size TEXT,
        thumbnail_path TEXT,
        audio_codec TEXT,
        audio_sample_rate TEXT,
        audio_channels TEXT,
        audio_bitrate TEXT,
        color_space TEXT,
        color_primaries TEXT,
        color_transfer TEXT,
        color_range TEXT,
        chroma_location TEXT,
        pixel_format TEXT,
        camera_make TEXT,
        camera_model TEXT,
        lens_model TEXT,
        iso TEXT,
        white_balance TEXT,
        record_start_time TEXT,
        record_end_time TEXT,
        camera_sn TEXT,
        camera_id TEXT,
        camera_index TEXT,
        lens_sn TEXT,
        lens_type TEXT,
        focus_distance_unit TEXT,
        nd_filter_density TEXT,
        gamma TEXT,
        cc_shift TEXT,
        exposure_index TEXT,
        look_name TEXT,
        look_burned_in TEXT,
        look_user_lut TEXT,
        lut_file_name TEXT,
        shutter_angle TEXT,
        sensor_fps TEXT,
        image_orientation TEXT,
        image_sharpness TEXT,
        image_detail TEXT,
        image_denoising TEXT,
        production TEXT,
        cinematographer TEXT,
        operator TEXT,
        director TEXT,
        location TEXT,
        company TEXT,
        user_info1 TEXT,
        user_info2 TEXT,
        reel_name TEXT,
        scene TEXT,
        take TEXT,
        date_camera TEXT,
        time_camera TEXT,
        uuid TEXT,
        sup_version TEXT,
        storage_sn TEXT,
        project_fps TEXT,
        asc_sat TEXT,
        asc_sop TEXT,
        ale_metadata TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
      )
    ''');

    // 索引
    await db.execute('CREATE INDEX idx_video_metadata_root_path ON video_metadata(root_path)');
    await db.execute('CREATE INDEX idx_video_metadata_project_id ON video_metadata(project_id)');
    await db.execute('CREATE INDEX idx_video_directories_project_id ON video_directories(project_id)');

    // v2: ASR 合板工程表
    await _createAsrProjectsTable(db);
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createAsrProjectsTable(db);
    }
  }

  static Future<void> _createAsrProjectsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asr_projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        video_directory TEXT,
        audio_directory TEXT,
        video_files TEXT,
        audio_files TEXT,
        status TEXT NOT NULL DEFAULT 'empty',
        asr_language TEXT DEFAULT 'zh',
        asr_engine TEXT DEFAULT 'sensevoice',
        asr_model TEXT DEFAULT 'ggml-medium.bin',
        video_subtitles TEXT,
        audio_subtitles TEXT,
        match_pairs TEXT,
        timeline_project_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  // ========== 应用设置 ==========

  static Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isNotEmpty) return maps.first['value'] as String?;
    return null;
  }

  static Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('app_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ========== 项目 CRUD ==========

  static Future<void> insertProject(Map<String, dynamic> projectMap) async {
    final db = await database;
    await db.insert('projects', projectMap, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getAllProjects() async {
    final db = await database;
    return await db.query('projects', orderBy: 'updated_at DESC');
  }

  static Future<void> updateProject(String id, Map<String, dynamic> values) async {
    final db = await database;
    await db.update('projects', values, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteProject(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('timeline_projects', where: 'project_id = ?', whereArgs: [id]);
      await txn.delete('production_settings', where: 'project_id = ?', whereArgs: [id]);
      await txn.delete('projects', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<void> deleteProjects(Set<String> ids) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete('timeline_projects', where: 'project_id = ?', whereArgs: [id]);
        await txn.delete('production_settings', where: 'project_id = ?', whereArgs: [id]);
        await txn.delete('projects', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  // ========== 时间线数据 ==========

  static Future<String?> getTimelineData(String projectId) async {
    final db = await database;
    final maps = await db.query('timeline_projects', where: 'project_id = ?', whereArgs: [projectId]);
    if (maps.isNotEmpty) return maps.first['timeline_data'] as String?;
    return null;
  }

  static Future<void> saveTimelineData(String projectId, String timelineJson) async {
    final db = await database;
    await db.insert('timeline_projects', {
      'project_id': projectId,
      'timeline_data': timelineJson,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ========== 职员设置 ==========

  static Future<Map<String, dynamic>?> getProductionSettings(String? projectId) async {
    final db = await database;
    if (projectId != null) {
      final maps = await db.query('production_settings',
          where: 'project_id = ?', whereArgs: [projectId], limit: 1);
      if (maps.isNotEmpty) return maps.first;
    }
    // 回退到全局设置
    final maps = await db.query('production_settings',
        where: 'project_id IS NULL', limit: 1);
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  static Future<void> saveProductionSettings(Map<String, dynamic> settings) async {
    final db = await database;
    settings['updated_at'] = DateTime.now().toIso8601String();
    if (settings['id'] != null) {
      await db.update('production_settings', settings, where: 'id = ?', whereArgs: [settings['id']]);
    } else {
      await db.insert('production_settings', settings);
    }
  }

  // ========== 视频目录 ==========

  static Future<int> addVideoDirectory(VideoDirectory directory) async {
    final db = await database;
    return await db.insert('video_directories', directory.toMap());
  }

  static Future<List<VideoDirectory>> getVideoDirectories() async {
    final db = await database;
    final maps = await db.query('video_directories', orderBy: 'added_at DESC');
    return maps.map((map) => VideoDirectory.fromMap(map)).toList();
  }

  static Future<List<VideoDirectory>> getVideoDirectoriesByProject(String projectId) async {
    final db = await database;
    final maps = await db.query('video_directories',
        where: 'project_id = ?', whereArgs: [projectId], orderBy: 'added_at DESC');
    return maps.map((map) => VideoDirectory.fromMap(map)).toList();
  }

  static Future<void> deleteVideoDirectory(String dirPath) async {
    final db = await database;
    final videos = await getVideosByRootPath(dirPath);

    for (var video in videos) {
      final hash = md5.convert(utf8.encode(video.filePath)).toString();
      final imgDir = path.join(appDir, 'data', 'img');
      final thumbnailFile = File(path.join(imgDir, '$hash.jpg'));
      if (thumbnailFile.existsSync()) {
        await thumbnailFile.delete();
      }
    }

    await db.transaction((txn) async {
      await txn.delete('video_directories', where: 'path = ?', whereArgs: [dirPath]);
      await txn.delete('video_metadata', where: 'root_path = ?', whereArgs: [dirPath]);
    });
  }

  // ========== 视频元数据 ==========

  static Future<int> addVideoMetadata(VideoMetadata metadata) async {
    final db = await database;
    return await db.insert('video_metadata', metadata.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<VideoMetadata>> getVideosByRootPath(String rootPath) async {
    final db = await database;
    final maps = await db.query('video_metadata', where: 'root_path = ?', whereArgs: [rootPath]);
    return maps.map((map) => VideoMetadata.fromMap(map)).toList();
  }

  static Future<List<VideoMetadata>> getVideosByProject(String projectId) async {
    final db = await database;
    final maps = await db.query('video_metadata',
        where: 'project_id = ?', whereArgs: [projectId]);
    return maps.map((map) => VideoMetadata.fromMap(map)).toList();
  }

  static Future<List<VideoMetadata>> searchVideos(String rootPath,
      {String? searchText, String? format, String? resolution}) async {
    final db = await database;
    final conditions = <String>['root_path = ?'];
    final args = <dynamic>[rootPath];

    if (searchText != null && searchText.isNotEmpty) {
      conditions.add('file_name LIKE ?');
      args.add('%$searchText%');
    }
    if (format != null && format.isNotEmpty) {
      conditions.add('codec = ?');
      args.add(format);
    }
    if (resolution != null && resolution.isNotEmpty) {
      conditions.add('resolution = ?');
      args.add(resolution);
    }

    final maps = await db.query('video_metadata',
        where: conditions.join(' AND '), whereArgs: args);
    return maps.map((map) => VideoMetadata.fromMap(map)).toList();
  }

  static Future<void> deleteVideoMetadata(int id) async {
    final db = await database;
    await db.delete('video_metadata', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteVideoMetadataByPaths(List<String> filePaths) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final fp in filePaths) {
        await txn.delete('video_metadata', where: 'file_path = ?', whereArgs: [fp]);
      }
    });
  }

  static Future<void> updateVideoMetadata(VideoMetadata metadata) async {
    final db = await database;
    final map = metadata.toMap()..remove('id');
    await db.update('video_metadata', map, where: 'id = ?', whereArgs: [metadata.id]);
  }

  static Future<VideoMetadata?> getVideoMetadataByPath(String filePath) async {
    final db = await database;
    final maps = await db.query('video_metadata', where: 'file_path = ?', whereArgs: [filePath]);
    if (maps.isNotEmpty) return VideoMetadata.fromMap(maps.first);
    return null;
  }

  static Future<List<String>> getDistinctCodecs(String rootPath) async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT DISTINCT codec FROM video_metadata WHERE root_path = ? AND codec IS NOT NULL AND codec != ''",
        [rootPath]);
    return result.map((e) => e['codec'] as String).toList();
  }

  static Future<List<String>> getDistinctResolutions(String rootPath) async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT DISTINCT resolution FROM video_metadata WHERE root_path = ? AND resolution IS NOT NULL AND resolution != ''",
        [rootPath]);
    return result.map((e) => e['resolution'] as String).toList();
  }

  // ========== ASR 合板工程 ==========

  static Future<void> insertAsrProject(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('asr_projects', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getAllAsrProjects() async {
    final db = await database;
    return await db.query('asr_projects', orderBy: 'updated_at DESC');
  }

  static Future<Map<String, dynamic>?> getAsrProject(String id) async {
    final db = await database;
    final maps = await db.query('asr_projects', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  static Future<void> updateAsrProject(String id, Map<String, dynamic> values) async {
    final db = await database;
    values['updated_at'] = DateTime.now().toIso8601String();
    await db.update('asr_projects', values, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteAsrProject(String id) async {
    final db = await database;
    await db.delete('asr_projects', where: 'id = ?', whereArgs: [id]);
  }
}
