import 'package:flutter/material.dart';

class ProgressDialog extends StatelessWidget {
  final String title;
  final String currentFile;
  final int processed;
  final int total;
  final VoidCallback? onCancel;

  const ProgressDialog({
    super.key,
    required this.title,
    required this.currentFile,
    required this.processed,
    required this.total,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? processed / total : 0.0;
    final percentage = (progress * 100).toStringAsFixed(0);

    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(24),
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: progress, minHeight: 8),
            const SizedBox(height: 12),
            Text('$percentage% ($processed/$total)',
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            Text('当前: $currentFile',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (onCancel != null) ...[
              const SizedBox(height: 20),
              TextButton(onPressed: onCancel, child: const Text('取消')),
            ],
          ],
        ),
      ),
    );
  }
}
