import 'package:flutter/material.dart';
import '../../models/video_metadata.dart';
import '../../services/database_service.dart';

class MetadataEditor extends StatefulWidget {
  final VideoMetadata video;
  final VoidCallback onSaved;

  const MetadataEditor({super.key, required this.video, required this.onSaved});

  @override
  State<MetadataEditor> createState() => _MetadataEditorState();
}

class _MetadataEditorState extends State<MetadataEditor> {
  late TextEditingController _sceneController;
  late TextEditingController _takeController;
  late TextEditingController _cameraModelController;
  late TextEditingController _lensModelController;

  @override
  void initState() {
    super.initState();
    _sceneController = TextEditingController(text: widget.video.scene ?? '');
    _takeController = TextEditingController(text: widget.video.take ?? '');
    _cameraModelController = TextEditingController(text: widget.video.cameraModel ?? '');
    _lensModelController = TextEditingController(text: widget.video.lensModel ?? '');
  }

  @override
  void dispose() {
    _sceneController.dispose();
    _takeController.dispose();
    _cameraModelController.dispose();
    _lensModelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final updated = widget.video.copyWith(
        cameraModel: _cameraModelController.text.isEmpty ? null : _cameraModelController.text,
        lensModel: _lensModelController.text.isEmpty ? null : _lensModelController.text,
        scene: _sceneController.text.isEmpty ? null : _sceneController.text,
        take: _takeController.text.isEmpty ? null : _takeController.text,
      );

      await DatabaseService.updateVideoMetadata(updated);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('编辑元数据', style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            TextField(
              controller: _sceneController,
              decoration: const InputDecoration(
                labelText: '场景',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _takeController,
              decoration: const InputDecoration(
                labelText: '镜次',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cameraModelController,
              decoration: const InputDecoration(
                labelText: '相机型号',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _lensModelController,
              decoration: const InputDecoration(
                labelText: '镜头型号',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
