import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'database_service.dart';

class MigrationService {
  static const _migratedKey = 'migration_completed_v3';

  static Future<bool> needsMigration() async {
    final db = await DatabaseService.database;
    final result = await db.query('app_settings', where: 'key = ?', whereArgs: [_migratedKey]);
    return result.isEmpty;
  }

  static Future<void> migrateIfNeeded() async {
    if (!await needsMigration()) return;

    final db = await DatabaseService.database;
    final prefs = await SharedPreferences.getInstance();

    // 1. 迁移项目数据（从 SharedPreferences JSON）
    final jsonString = prefs.getString('projects');
    if (jsonString != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        for (final e in jsonList) {
          final Map<String, dynamic> proj = e as Map<String, dynamic>;
          await db.insert('projects', {
            'id': proj['id'],
            'root_dir': proj['rootDir'],
            'is_synced_project': (proj['isSyncedProject'] as bool? ?? false) ? 1 : 0,
            'original_project_id': proj['originalProjectId'],
            'custom_display_name': proj['customDisplayName'],
            'created_at': proj['createdAt'],
            'updated_at': proj['updatedAt'],
          }, conflictAlgorithm: ConflictAlgorithm.ignore);

          // 迁移时间线数据
          if (proj['timelineProject'] != null) {
            final timelineJson = jsonEncode(proj['timelineProject']);
            await db.insert('timeline_projects', {
              'project_id': proj['id'],
              'timeline_data': timelineJson,
              'updated_at': proj['updatedAt'] ?? DateTime.now().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
      } catch (e) {
        print('迁移项目数据出错: $e');
      }
    }

    // 2. 迁移应用设置
    final settingKeys = [
      'isDarkTheme', 'last_path',
      'production', 'cinematographer', 'operator',
      'director', 'location', 'company',
    ];
    for (final key in settingKeys) {
      final value = prefs.getString(key) ?? prefs.getBool(key)?.toString();
      if (value != null) {
        await db.insert('app_settings', {'key': key, 'value': value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    // 3. 迁移旧 DIT-tools SQLite 数据库（如果存在）
    await _migrateOldDitDatabase(db);

    // 4. 标记迁移完成
    await db.insert('app_settings', {'key': _migratedKey, 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> _migrateOldDitDatabase(dynamic db) async {
    final oldDbPath = path.join(DatabaseService.appDir, 'data', 'Metadata', 'metadata.db');
    final oldDbFile = File(oldDbPath);
    if (!oldDbFile.existsSync()) return;

    try {
      // 使用 sqflite 打开旧数据库（只读）
      final oldDb = await openDatabase(oldDbPath, version: 3, readOnly: true);

      // 迁移 video_directories
      try {
        final dirs = await oldDb.query('video_directories');
        for (final dir in dirs) {
          await db.insert('video_directories', {
            'id': dir['id'],
            'path': dir['path'],
            'added_at': dir['addedAt'],
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      } catch (e) {
        print('迁移 video_directories 出错: $e');
      }

      // 迁移 video_metadata（列名从 camelCase 转为 snake_case）
      try {
        final videos = await oldDb.query('video_metadata');
        for (final v in videos) {
          final converted = _convertMetadataKeys(v);
          await db.insert('video_metadata', converted,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      } catch (e) {
        print('迁移 video_metadata 出错: $e');
      }

      await oldDb.close();
    } catch (e) {
      print('打开旧 DIT 数据库出错: $e');
    }
  }

  static Map<String, dynamic> _convertMetadataKeys(Map<String, dynamic> old) {
    final keyMap = {
      'rootPath': 'root_path',
      'filePath': 'file_path',
      'fileName': 'file_name',
      'relativePath': 'relative_path',
      'frameRate': 'frame_rate',
      'fileSize': 'file_size',
      'thumbnailPath': 'thumbnail_path',
      'audioCodec': 'audio_codec',
      'audioSampleRate': 'audio_sample_rate',
      'audioChannels': 'audio_channels',
      'audioBitrate': 'audio_bitrate',
      'colorSpace': 'color_space',
      'colorPrimaries': 'color_primaries',
      'colorTransfer': 'color_transfer',
      'colorRange': 'color_range',
      'chromaLocation': 'chroma_location',
      'pixelFormat': 'pixel_format',
      'cameraMake': 'camera_make',
      'cameraModel': 'camera_model',
      'lensModel': 'lens_model',
      'whiteBalance': 'white_balance',
      'recordStartTime': 'record_start_time',
      'recordEndTime': 'record_end_time',
      'cameraSn': 'camera_sn',
      'cameraId': 'camera_id',
      'cameraIndex': 'camera_index',
      'lensSn': 'lens_sn',
      'lensType': 'lens_type',
      'focusDistanceUnit': 'focus_distance_unit',
      'ndFilterDensity': 'nd_filter_density',
      'ccShift': 'cc_shift',
      'exposureIndex': 'exposure_index',
      'lookName': 'look_name',
      'lookBurnedIn': 'look_burned_in',
      'lookUserLut': 'look_user_lut',
      'lutFileName': 'lut_file_name',
      'shutterAngle': 'shutter_angle',
      'sensorFps': 'sensor_fps',
      'imageOrientation': 'image_orientation',
      'imageSharpness': 'image_sharpness',
      'imageDetail': 'image_detail',
      'imageDenoising': 'image_denoising',
      'userInfo1': 'user_info1',
      'userInfo2': 'user_info2',
      'reelName': 'reel_name',
      'dateCamera': 'date_camera',
      'timeCamera': 'time_camera',
      'supVersion': 'sup_version',
      'storageSn': 'storage_sn',
      'projectFps': 'project_fps',
      'ascSat': 'asc_sat',
      'ascSop': 'asc_sop',
      'aleMetadata': 'ale_metadata',
      'createdAt': 'created_at',
    };

    final result = <String, dynamic>{};
    for (final entry in old.entries) {
      final newKey = keyMap[entry.key] ?? entry.key;
      result[newKey] = entry.value;
    }
    return result;
  }
}
