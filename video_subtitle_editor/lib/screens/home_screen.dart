import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../services/media_scan_service.dart';
import '../state/app_state.dart';
import 'clip_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isScanning = false;
  int _totalFiles = 0;
  int _processedFiles = 0;
  String? _scanningDirName;
  final Map<String, int> _videoCounts = {};
  final MediaScanService _scanService = MediaScanService();

  @override
  void initState() {
    super.initState();
    _loadVideoCounts();
  }

  Future<void> _loadVideoCounts() async {
    final state = context.read<AppState>();
    for (var project in state.projects) {
      try {
        final files = await _scanService.scanVideos(project.rootDir);
        if (mounted) {
          setState(() {
            _videoCounts[project.id] = files.length;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _addDirectory() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择视频目录',
    );
    if (dir == null || dir.trim().isEmpty) return;
    if (!mounted) return;

    // 检查是否已存在
    final state = context.read<AppState>();
    final existing = state.projects.where((p) => p.rootDir == dir);
    if (existing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该目录已添加')),
      );
      return;
    }

    // 创建项目
    await state.addProjectFromDir(dir);

    // 扫描视频文件数量
    setState(() {
      _isScanning = true;
      _scanningDirName = path.basename(dir);
      _processedFiles = 0;
    });

    try {
      final files = await _scanService.scanVideos(dir);
      if (mounted) {
        setState(() {
          _videoCounts[state.selectedProject!.id] = files.length;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanningDirName = null;
        });
      }
    }
  }

  void _deleteProject(Project project) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除目录「${project.displayName}」吗？\n(此操作不会删除您的源文件)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await context.read<AppState>().deleteProjects({project.id});
              _videoCounts.remove(project.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _enterClipScreen(Project project) {
    context.read<AppState>().selectProject(project);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ClipScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('合板工作台'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              onPressed: _isScanning ? null : _addDirectory,
              icon: const Icon(Icons.add),
              label: const Text('添加视频目录'),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: state.projects.isEmpty
                ? _buildEmptyState()
                : _buildCardGrid(state),
          ),
          if (_isScanning) _buildScanOverlay(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '从一个视频目录开始',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '点击右上角「添加视频目录」选择文件夹，添加后以卡片展示。\n点击卡片可进入合板操作页面。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isScanning ? null : _addDirectory,
                  icon: const Icon(Icons.add),
                  label: const Text('添加视频目录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardGrid(AppState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1400
            ? 4
            : width >= 1000
                ? 3
                : width >= 700
                    ? 2
                    : 1;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.2,
          ),
          itemCount: state.projects.length,
          itemBuilder: (context, index) {
            final project = state.projects[index];
            return _ProjectCard(
              project: project,
              videoCount: _videoCounts[project.id] ?? 0,
              onDelete: () => _deleteProject(project),
              onTap: () => _enterClipScreen(project),
            );
          },
        );
      },
    );
  }

  Widget _buildScanOverlay() {
    final progress = _totalFiles > 0 ? _processedFiles / _totalFiles : 0.0;
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '正在扫描视频目录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                _scanningDirName ?? '',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _totalFiles > 0 ? progress : null,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
              if (_totalFiles > 0)
                Text(
                  '$_processedFiles / $_totalFiles',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  _ProjectCard({
    required this.project,
    required this.videoCount,
    required this.onTap,
    required this.onDelete,
  });

  final Project project;
  final int videoCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final DateFormat _fmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      project.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: colorScheme.error,
                    onPressed: onDelete,
                    tooltip: '删除',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                project.rootDir,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.videocam,
                          size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        '$videoCount 个视频',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  Text(
                    '更新：${_fmt.format(project.updatedAt)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
