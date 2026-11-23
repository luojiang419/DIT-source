import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/app_state.dart';
import 'services/database_service.dart';
import 'services/migration_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 初始化数据库
  await DatabaseService.database;

  // 执行数据迁移（SharedPreferences → SQLite）
  await MigrationService.migrateIfNeeded();

  final appState = AppState();
  await appState.loadProjects();

  runApp(
    ChangeNotifierProvider(
      create: (_) => appState,
      child: const App(),
    ),
  );
}
