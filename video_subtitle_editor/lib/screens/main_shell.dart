import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'asr_project_list_screen.dart';
import 'dit_data_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final PageStorageBucket _bucket = PageStorageBucket();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (value) {
              setState(() {
                _index = value;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library),
                label: Text('合板工作台'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: Text('ASR合板'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.storage_outlined),
                selectedIcon: Icon(Icons.storage),
                label: Text('元数据管理'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: Text('查找素材'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('设置'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: PageStorage(
              bucket: _bucket,
              child: _buildPage(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage() {
    switch (_index) {
      case 0:
        return const HomeScreen(key: PageStorageKey('home'));
      case 1:
        return const AsrProjectListScreen(key: PageStorageKey('asr_projects'));
      case 2:
        return const DitDataScreen(key: PageStorageKey('dit_data'));
      case 3:
        return const SearchScreen(key: PageStorageKey('search'));
      case 4:
        return const SettingsScreen(key: PageStorageKey('settings'));
      default:
        return const HomeScreen(key: PageStorageKey('home'));
    }
  }
}
