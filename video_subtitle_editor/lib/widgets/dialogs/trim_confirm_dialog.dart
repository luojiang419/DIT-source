import 'package:flutter/material.dart';

import '../../models/timeline_model.dart';
import '../../services/trim_service.dart';

/// 一键修剪确认对话框
class TrimConfirmDialog extends StatelessWidget {
  const TrimConfirmDialog({super.key, required this.project});

  final TimelineProject project;

  @override
  Widget build(BuildContext context) {
    final videoCount = project.videoTrack?.clips.length ?? 0;
    final audioCount = project.audioTracks.length;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.content_cut, size: 20),
          SizedBox(width: 8),
          Text('一键修剪'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '确认视频和音频对齐正确后，点击修剪。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              '修剪将执行：',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            _BulletItem(text: '按 $videoCount 个视频片段范围裁切 $audioCount 条音频'),
            const _BulletItem(text: '压缩视频间空白间距，轨道无缝排列'),
            const _BulletItem(text: '字幕跟随对应媒体同步调整'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .errorContainer
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber,
                      size: 16,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Text(
                    '此操作不可撤销',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.content_cut, size: 16),
          label: const Text('确认修剪'),
        ),
      ],
    );
  }
}

/// 修剪完成结果对话框
class TrimResultDialog extends StatelessWidget {
  const TrimResultDialog({super.key, required this.result});

  final TrimResult result;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 20),
          SizedBox(width: 8),
          Text('修剪完成'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResultRow(
            label: '音频已裁切为',
            value: '${result.audioTracks.fold<int>(0, (s, t) => s + t.clips.length)} 段',
          ),
          _ResultRow(
            label: '清理空白间距',
            value: result.formattedGapRemoved,
          ),
          _ResultRow(
            label: '总时长',
            value:
                '${_formatMs(result.originalDurationMs)} → ${_formatMs(result.newDurationMs)}',
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('确定'),
        ),
      ],
    );
  }

  String _formatMs(int ms) {
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return '$m 分 $s 秒';
  }
}

class _BulletItem extends StatelessWidget {
  const _BulletItem({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 14)),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label：',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
