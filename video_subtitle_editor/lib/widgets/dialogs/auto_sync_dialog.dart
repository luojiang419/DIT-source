import 'package:flutter/material.dart';

import '../../models/timeline_model.dart';
import '../../services/auto_sync_service.dart';
import '../../services/context_matching_service.dart';
import 'sync_match_dialog.dart';

/// 全自动合板进度对话框
/// 显示合板进度，完成后返回 AutoSyncResult
class AutoSyncDialog extends StatefulWidget {
  const AutoSyncDialog({
    super.key,
    required this.project,
  });

  final TimelineProject project;

  @override
  State<AutoSyncDialog> createState() => _AutoSyncDialogState();
}

class _AutoSyncDialogState extends State<AutoSyncDialog> {
  String _currentStep = '准备中...';
  double _progress = 0.0;
  String? _errorMessage;
  bool _done = false;
  AutoSyncResult? _result;

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    final service = AutoSyncService(
      onProgress: (step, progress) {
        if (mounted) {
          setState(() {
            _currentStep = step;
            _progress = progress;
          });
        }
      },
    );

    try {
      // 先预览匹配结果（用于多匹配时让用户选择）
      final previewMatches = service.previewMatches(widget.project);

      SyncMatch? selectedMatch;

      // 如果有多个匹配，让用户选择
      if (previewMatches.length > 1 && mounted) {
        setState(() => _currentStep = '找到多处匹配，等待用户确认...');
        selectedMatch = await showDialog<SyncMatch>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => SyncMatchDialog(matches: previewMatches),
        );
        if (selectedMatch == null) {
          if (mounted) Navigator.of(context).pop(null);
          return;
        }
      } else if (previewMatches.length == 1) {
        selectedMatch = previewMatches.first;
      }
      // previewMatches 为空时 selectedMatch 保持 null，让 performSync 自己处理并报错

      final result = await service.performSync(
        originalProject: widget.project,
        selectedMatch: selectedMatch,
      );

      if (mounted) {
        setState(() {
          _done = true;
          _result = result;
          _currentStep = '合板完成！';
          _progress = 1.0;
        });
        // 短暂显示完成状态后关闭
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.of(context).pop(result);
      }
    } on AutoSyncException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _currentStep = '合板失败';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '发生未知错误：$e';
          _currentStep = '合板失败';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.movie_filter, size: 20),
          SizedBox(width: 8),
          Text('全自动合板'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null) ...[
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ] else ...[
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_done)
                    const Icon(Icons.check_circle, color: Colors.green, size: 18)
                  else
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentStep,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              if (_result != null) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                _InfoRow(label: '视频片段', value: '${_result!.videoCount} 个'),
                _InfoRow(label: '视频字幕', value: '${_result!.videoSubtitleCount} 条'),
                _InfoRow(label: '音频字幕', value: '${_result!.audioSubtitleCount} 条'),
                _InfoRow(
                  label: '匹配置信度',
                  value: '${(_result!.matches.first.confidence * 100).toStringAsFixed(0)}%',
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (_errorMessage != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('关闭'),
          )
        else if (!_done)
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label：',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
