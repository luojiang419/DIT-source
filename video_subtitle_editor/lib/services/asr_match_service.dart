import 'dart:math';
import '../models/timeline_model.dart';
import '../models/asr_project.dart';

/// ASR 字幕上下文匹配算法
///
/// 通过比较视频和音频的 ASR 字幕文本内容，自动找出对应的视频-音频配对。
/// 核心思路：同一段录制的视频和音频，ASR 识别出的字幕内容必然相同。
class AsrMatchService {
  /// 滑动窗口大小
  static const int windowSize = 3;

  /// 最少匹配窗口数
  static const int minMatchCount = 3;

  /// 模糊匹配相似度阈值
  static const double similarityThreshold = 0.85;

  /// 偏移一致性容差（毫秒）
  static const int offsetConsistencyMs = 3000;

  /// 执行全量匹配
  ///
  /// 对每个视频文件和每个音频文件进行字幕上下文匹配，
  /// 返回最佳匹配对列表。
  static List<MatchPair> matchAll(
    Map<String, List<TimelineClip>> videoSubtitles,
    Map<String, List<TimelineClip>> audioSubtitles,
  ) {
    // Step 1: 为每个文件生成字幕指纹
    final videoFingerprints = <String, Map<String, _WindowInfo>>{};
    for (final entry in videoSubtitles.entries) {
      final fps = _generateFingerprints(entry.value);
      if (fps.isNotEmpty) videoFingerprints[entry.key] = fps;
    }

    final audioFingerprints = <String, Map<String, _WindowInfo>>{};
    for (final entry in audioSubtitles.entries) {
      final fps = _generateFingerprints(entry.value);
      if (fps.isNotEmpty) audioFingerprints[entry.key] = fps;
    }

    // Step 2: 交叉匹配
    final candidates = <_Candidate>[];
    for (final vEntry in videoFingerprints.entries) {
      for (final aEntry in audioFingerprints.entries) {
        final score = _computeMatchScore(vEntry.value, aEntry.value);
        if (score.matchedCount >= minMatchCount) {
          candidates.add(_Candidate(
            videoPath: vEntry.key,
            audioPath: aEntry.key,
            confidence: score.confidence,
            offsetMs: score.offset,
            matchedWindowCount: score.matchedCount,
            totalWindowCount: vEntry.value.length,
            isConsistent: score.isConsistent,
          ));
        }
      }
    }

    // Step 3: 贪心 1-to-1 分配（按置信度降序，每个 video/audio 最多出现一次）
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));

    final usedVideos = <String>{};
    final usedAudios = <String>{};
    final matched = <MatchPair>[];

    for (final c in candidates) {
      if (usedVideos.contains(c.videoPath) || usedAudios.contains(c.audioPath)) continue;
      usedVideos.add(c.videoPath);
      usedAudios.add(c.audioPath);
      matched.add(MatchPair(
        videoFilePath: c.videoPath,
        audioFilePath: c.audioPath,
        confidence: c.confidence,
        offsetMs: c.offsetMs,
        matchedWindowCount: c.matchedWindowCount,
        totalWindowCount: c.totalWindowCount,
        isConsistent: c.isConsistent,
      ));
    }

    return matched;
  }

  /// 为字幕列表生成滑动窗口指纹集合
  static Map<String, _WindowInfo> _generateFingerprints(List<TimelineClip> clips) {
    if (clips.length < windowSize) return {};

    final fingerprints = <String, _WindowInfo>{};
    final texts = clips.map((c) => _normalize((c.text ?? '').trim())).toList();

    for (int i = 0; i <= texts.length - windowSize; i++) {
      final windowTexts = texts.sublist(i, i + windowSize);
      // 跳过空窗口
      if (windowTexts.every((t) => t.isEmpty)) continue;

      final key = windowTexts.join('|');
      if (!fingerprints.containsKey(key)) {
        fingerprints[key] = _WindowInfo(
          startIndex: i,
          startMs: clips[i].timelineStartMs,
        );
      }
    }

    return fingerprints;
  }

  /// 计算两个指纹集合的匹配分数
  static _MatchScore _computeMatchScore(
    Map<String, _WindowInfo> videoFps,
    Map<String, _WindowInfo> audioFps,
  ) {
    int matchedCount = 0;
    final offsets = <int>[];

    for (final vKey in videoFps.keys) {
      // 精确匹配
      if (audioFps.containsKey(vKey)) {
        matchedCount++;
        final vStart = videoFps[vKey]!.startMs;
        final aStart = audioFps[vKey]!.startMs;
        offsets.add(vStart - aStart);
        continue;
      }

      // 模糊匹配
      bool found = false;
      for (final aKey in audioFps.keys) {
        if (_similarity(vKey, aKey) >= similarityThreshold) {
          matchedCount++;
          final vStart = videoFps[vKey]!.startMs;
          final aStart = audioFps[aKey]!.startMs;
          offsets.add(vStart - aStart);
          found = true;
          break;
        }
      }
    }

    if (matchedCount < minMatchCount) {
      return _MatchScore(confidence: 0, offset: 0, matchedCount: 0, isConsistent: false);
    }

    final confidence = matchedCount / videoFps.length;

    // 偏移量 = 中位数
    offsets.sort();
    final medianOffset = offsets[offsets.length ~/ 2];

    // 偏移一致性
    final isConsistent = _stdDev(offsets) < offsetConsistencyMs;

    return _MatchScore(
      confidence: isConsistent ? confidence : confidence * 0.5,
      offset: medianOffset,
      matchedCount: matchedCount,
      isConsistent: isConsistent,
    );
  }

  /// 文本归一化：去除标点、空白
  static String _normalize(String text) {
    return text
        .replaceAll(RegExp(r'[?？。！，、；：!.,;:\s]'), '')
        .toLowerCase();
  }

  /// 简单的 Levenshtein 相似度
  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final maxLen = max(a.length, b.length);
    final dist = _levenshtein(a, b);
    return 1.0 - dist / maxLen;
  }

  /// Levenshtein 编辑距离
  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    List<int> prev = List.generate(b.length + 1, (i) => i);
    List<int> curr = List.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          prev[j] + 1,      // 删除
          curr[j - 1] + 1,   // 插入
          prev[j - 1] + cost // 替换
        ].reduce(min);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }

    return prev[b.length];
  }

  /// 标准差
  static double _stdDev(List<int> values) {
    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
    return sqrt(variance);
  }
}

/// 滑动窗口信息
class _WindowInfo {
  final int startIndex;
  final int startMs;
  const _WindowInfo({required this.startIndex, required this.startMs});
}

/// 匹配分数
class _MatchScore {
  final double confidence;
  final int offset;
  final int matchedCount;
  final bool isConsistent;
  const _MatchScore({
    required this.confidence,
    required this.offset,
    required this.matchedCount,
    required this.isConsistent,
  });
}

/// 匹配候选
class _Candidate {
  final String videoPath;
  final String audioPath;
  final double confidence;
  final int offsetMs;
  final int matchedWindowCount;
  final int totalWindowCount;
  final bool isConsistent;
  const _Candidate({
    required this.videoPath,
    required this.audioPath,
    required this.confidence,
    required this.offsetMs,
    required this.matchedWindowCount,
    required this.totalWindowCount,
    required this.isConsistent,
  });
}
