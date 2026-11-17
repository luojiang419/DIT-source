
import 'package:flutter/material.dart';
import '../../models/timeline_model.dart';

class SubtitleBlockView extends StatelessWidget {
  const SubtitleBlockView({
    super.key,
    required this.clip,
    required this.pixelsPerSecond,
    this.color = Colors.orangeAccent,
  });

  final TimelineClip clip;
  final double pixelsPerSecond;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15), // 减淡背景色
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        clip.text ?? '',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.black87, // 浅色背景使用深色文字
          fontSize: 12,
          overflow: TextOverflow.ellipsis,
        ),
        maxLines: 2,
      ),
    );
  }
}
