import 'package:flutter/material.dart';

import '../models/asr_project.dart';
import '../services/asr_project_service.dart';
import 'asr_project_detail_screen.dart';

/// ASR 合板工程列表页
class AsrProjectListScreen extends StatefulWidget {
  const AsrProjectListScreen({super.key});

  @override
  State<AsrProjectListScreen> createState() => _AsrProjectListScreenState();
}

class _AsrProjectListScreenState extends State<AsrProjectListScreen> {
  List<AsrProject> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _loading = true);
    try {
      final projects = await AsrProjectService.getAllProjects();
      if (mounted) {
        setState(() {
          _projects = projects;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createProject() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('新建 ASR 合板工程'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '工程名称',
              hintText: '例如：拍摄Day1',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );

    if (name != null && name.isNotEmpty) {
      await AsrProjectService.createProject(name: name);
      await _loadProjects();
    }
  }

  Future<void> _deleteProject(AsrProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除工程「${project.name}」？\n不会删除源文件。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AsrProjectService.deleteProject(project.id);
      await _loadProjects();
    }
  }

  void _enterProject(AsrProject project) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AsrProjectDetailScreen(projectId: project.id),
      ),
    );
    _loadProjects(); // 返回后刷新
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 顶栏
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                const Text('ASR 自动合板', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _createProject,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建工程'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 内容区
          Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_projects.isEmpty) {
      return Center(
        child: Card(
          margin: const EdgeInsets.all(48),
          child: Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 64, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                const SizedBox(height: 16),
                const Text('还没有 ASR 合板工程', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                const Text('点击右上角「新建工程」开始', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _createProject,
                  icon: const Icon(Icons.add),
                  label: const Text('新建工程'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      int cols;
      if (constraints.maxWidth >= 1400) {
        cols = 4;
      } else if (constraints.maxWidth >= 1000) {
        cols = 3;
      } else if (constraints.maxWidth >= 700) {
        cols = 2;
      } else {
        cols = 1;
      }

      return GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 2.2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: _projects.length,
        itemBuilder: (context, index) => _ProjectCard(
          project: _projects[index],
          onTap: () => _enterProject(_projects[index]),
          onDelete: () => _deleteProject(_projects[index]),
        ),
      );
    });
  }
}

/// 工程卡片
class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap, required this.onDelete});

  final AsrProject project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  Color _statusColor() {
    switch (project.status) {
      case AsrProjectStatus.completed:
        return Colors.green.shade800;
      case AsrProjectStatus.matched:
        return Colors.lightGreen;
      case AsrProjectStatus.recognizing:
        return Colors.blue;
      case AsrProjectStatus.recognized:
        return Colors.teal;
      case AsrProjectStatus.ready:
        return Colors.orange;
      case AsrProjectStatus.error:
        return Colors.red;
      case AsrProjectStatus.empty:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      project.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: onDelete,
                    tooltip: '删除',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.videocam, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text('${project.videoCount} 个视频', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                  const SizedBox(width: 16),
                  Icon(Icons.mic, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text('${project.audioCount} 个音频', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _statusColor().withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      project.status.label,
                      style: TextStyle(fontSize: 12, color: _statusColor(), fontWeight: FontWeight.w500),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(project.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
