import '../models/timeline_model.dart';

/// 三段式上下文（前一条 + 目标 + 后一条）
class SubtitleContext {
  const SubtitleContext({
    this.prev,
    required this.target,
    this.next,
    required this.trackIndex, // -1=视频轨, >=0=音频轨索引
  });

  final TimelineClip? prev;
  final TimelineClip target;
  final TimelineClip? next;
  final int trackIndex;

  /// 上下文指纹（用于匹配）
  String get fingerprint =>
      '${_norm(prev?.text)}|${_norm(target.text)}|${_norm(next?.text)}';

  static String _norm(String? s) {
    if (s == null || s.isEmpty) return '_';
    // 去除标点、空格，统一为纯文字
    return s
        .replaceAll(RegExp(r'[，。！？、；：""''【】（）《》…—\s,.!?;:\'"()\[\]{}]'), '')
        .trim();
  }
}

/// 匹配结果
class SyncMatch {
  const SyncMatch({
    required this.videoContext,
    required this.audioContext,
    required this.confidence,
  });

  final SubtitleContext videoContext;
  final SubtitleContext audioContext;
  final double confidence; // 0.0 ~ 1.0
}

/// 三段式上下文匹配服务
class ContextMatchingService {
  /// 从字幕列表构建所有三段式上下文
  List<SubtitleContext> buildContexts(
    List<TimelineClip> subtitles,
    int trackIndex,
  ) {
    final contexts = <SubtitleContext>[];
    for (int i = 0; i < subtitles.length; i++) {
      contexts.add(SubtitleContext(
        prev: i > 0 ? subtitles[i - 1] : null,
        target: subtitles[i],
        next: i < subtitles.length - 1 ? subtitles[i + 1] : null,
        trackIndex: trackIndex,
      ));
    }
    return contexts;
  }

  /// 在视频上下文和音频上下文之间查找所有匹配对
  List<SyncMatch> findMatches(
    List<SubtitleContext> videoContexts,
    List<SubtitleContext> audioContexts, {
    double threshold = 0.85,
  }) {
    final matches = <SyncMatch>[];

    for (final vCtx in videoContexts) {
      for (final aCtx in audioContexts) {
        final confidence = _calcConfidence(vCtx, aCtx);
        if (confidence >= threshold) {
          matches.add(SyncMatch(
            videoContext: vCtx,
            audioContext: aCtx,
            confidence: confidence,
          ));
        }
      }
    }

    // 按置信度降序排列
    matches.sort((a, b) => b.confidence.compareTo(a.confidence));
    return matches;
  }

  /// 一对一匹配：每个视频字幕和音频字幕最多匹配一次
  /// 使用贪心算法，按置信度从高到低选择，确保不重复
  List<SyncMatch> findOneToOneMatches(
    List<SubtitleContext> videoContexts,
    List<SubtitleContext> audioContexts, {
    double threshold = 0.85,
  }) {
    final allMatches = findMatches(videoContexts, audioContexts, threshold: threshold);

    final usedVideoIds = <String>{};
    final usedAudioIds = <String>{};
    final oneToOne = <SyncMatch>[];

    for (final match in allMatches) {
      final vId = match.videoContext.target.id;
      final aId = match.audioContext.target.id;
      if (!usedVideoIds.contains(vId) && !usedAudioIds.contains(aId)) {
        oneToOne.add(match);
        usedVideoIds.add(vId);
        usedAudioIds.add(aId);
      }
    }

    return oneToOne;
  }

  // ── 私有方法 ──────────────────────────────────────────────────

  double _calcConfidence(SubtitleContext a, SubtitleContext b) {
    // 目标字幕相似度（权重最高）
    final targetSim = _similarity(
      SubtitleContext._norm(a.target.text),
      SubtitleContext._norm(b.target.text),
    );

    // 前一条字幕相似度
    final prevSim = _similarity(
      SubtitleContext._norm(a.prev?.text),
      SubtitleContext._norm(b.prev?.text),
    );

    // 后一条字幕相似度
    final nextSim = _similarity(
      SubtitleContext._norm(a.next?.text),
      SubtitleContext._norm(b.next?.text),
    );

    // 加权平均：目标60%，前后各20%
    return targetSim * 0.6 + prevSim * 0.2 + nextSim * 0.2;
  }

  /// 计算两个字符串的相似度（0.0 ~ 1.0）
  /// 使用 Levenshtein 编辑距离
  double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final maxLen = a.length > b.length ? a.length : b.length;
    final dist = _levenshtein(a, b);
    return 1.0 - dist / maxLen;
  }

  int _levenshtein(String a, String b) {
    final m = a.length;
    final n = b.length;
    // 使用滚动数组节省内存
    var prev = List<int>.generate(n + 1, (i) => i);
    var curr = List<int>.filled(n + 1, 0);

    for (int i = 1; i <= m; i++) {
      curr[0] = i;
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          curr[j] = prev[j - 1];
        } else {
          curr[j] = 1 +
              [prev[j], curr[j - 1], prev[j - 1]]
                  .reduce((x, y) => x < y ? x : y);
        }
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }
}
