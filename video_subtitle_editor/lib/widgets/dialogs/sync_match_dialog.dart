import 'package:flutter/material.dart';

import '../../services/context_matching_service.dart';

/// 多匹配选择对话框
/// 当同一段对白在多处出现时，让用户选择正确的合板基准
class SyncMatchDialog extends StatefulWidget {
  const SyncMatchDialog({super.key, required this.matches});

  final List<SyncMatch> matches;

  @override
  State<SyncMatchDialog> createState() => _SyncMatchDialogState();
}

class _SyncMatchDialogState extends State<SyncMatchDialog> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('找到多处匹配，请选择合板基准'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '找到 ${widget.matches.length} 处字幕上下文匹配，请选择正确的一处作为合板基准：',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.matches.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final match = widget.matches[index];
                  final isSelected = index == _selectedIndex;
                  return _MatchCard(
                    match: match,
                    isSelected: isSelected,
                    onTap: () => setState(() => _selectedIndex = index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(widget.matches[_selectedIndex]),
          child: const Text('确认合板'),
        ),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.isSelected,
    required this.onTap,
  });

  final SyncMatch match;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 18,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '置信度：${(match.confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? colorScheme.primary : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ContextRow(label: '视频', context: match.videoContext),
            const SizedBox(height: 4),
            _ContextRow(label: '音频', context: match.audioContext),
          ],
        ),
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({required this.label, required this.context});

  final String label;
  final SubtitleContext context;

  @override
  Widget build(BuildContext context_) {
    final colorScheme = Theme.of(context_).colorScheme;
    final prev = this.context.prev?.text ?? '—';
    final target = this.context.target.text ?? '';
    final next = this.context.next?.text ?? '—';
    final time = _formatMs(this.context.target.timelineStartMs);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: label == '视频'
                ? colorScheme.primaryContainer
                : colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: label == '视频'
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '"$prev" → "$target" → "$next"  [$time]',
            style: Theme.of(context_).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatMs(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
