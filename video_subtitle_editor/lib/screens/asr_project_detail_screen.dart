import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';

import '../models/asr_project.dart';
import '../models/timeline_model.dart';
import '../services/asr_project_service.dart';
import '../services/asr_match_service.dart';
import '../services/sherpa_onnx_asr_service.dart';
import '../services/sherpa_onnx_path_service.dart';
import '../state/app_state.dart';
import 'clip_screen.dart';

/// ASR 合板工程操作页（5步骤引导）
class AsrProjectDetailScreen extends StatefulWidget {
  const AsrProjectDetailScreen({super.key, required this.projectId});
  final String projectId;

  @override
  State<AsrProjectDetailScreen> createState() => _AsrProjectDetailScreenState();
}

class _AsrProjectDetailScreenState extends State<AsrProjectDetailScreen> {
  AsrProject? _project;
  bool _loading = true;
  int _currentStep = 0;

  // Step 1: 素材导入状态
  final List<String> _videoFileList = [];
  final List<String> _audioFileList = [];

  // Step 2: ASR 识别状态
  bool _isRecognizing = false;
  int _recognizedVideoCount = 0;
  int _recognizedAudioCount = 0;
  String _currentRecognizingFile = '';
  double _currentFileProgress = 0;
  String? _recognizeError;
  Map<String, List<TimelineClip>> _videoSubs = {};
  Map<String, List<TimelineClip>> _audioSubs = {};

  // Step 3: 匹配结果
  List<MatchPair> _matchPairs = [];

  // Step 2（字幕审阅）状态
  String _searchKeyword = '';
  String? _selectedVideoPath;
  String? _selectedAudioPath;
  Set<String> _expandedVideoFiles = {};
  Set<String> _expandedAudioFiles = {};
  TimelineClip? _selectedVideoClip;
  TimelineClip? _selectedAudioClip;

  // 模型选择
  String _selectedModelVariant = '';

  // 支持的视频/音频扩展名
  static const _videoExts = ['.mp4', '.mov', '.avi', '.mkv', '.mxf', '.wmv', '.flv', '.webm', '.m4v', '.mpg', '.mpeg'];
  static const _audioExts = ['.wav', '.mp3', '.aac', '.flac', '.ogg', '.wma', '.m4a', '.aiff'];

  @override
  void initState() {
    super.initState();
    _initModelSelection();
    _loadProject();
  }

  void _initModelSelection() {
    // 优先选 Qwen3-ASR，其次 SenseVoice
    for (final m in SherpaOnnxPathService.availableModels) {
      if (SherpaOnnxPathService.isModelAvailable(m.variant)) {
        _selectedModelVariant = m.variant;
        return;
      }
    }
    // 回退：检查所有模型目录
    final available = SherpaOnnxPathService.listAvailableModels();
    if (available.isNotEmpty) {
      _selectedModelVariant = available.first.variant;
    }
  }

  Future<void> _loadProject() async {
    final project = await AsrProjectService.getProject(widget.projectId);
    if (mounted && project != null) {
      setState(() {
        _project = project;
        _loading = false;
        _videoFileList.addAll(project.videoFiles);
        _audioFileList.addAll(project.audioFiles);
        _videoSubs = Map.from(project.videoSubtitles);
        _audioSubs = Map.from(project.audioSubtitles);
        _matchPairs = List.from(project.matchPairs);
        _expandedVideoFiles = Set.from(project.videoFiles);
        _expandedAudioFiles = Set.from(project.audioFiles);
        _restoreStep();
      });
    }
  }

  /// 根据工程状态恢复步骤
  void _restoreStep() {
    final proj = _project!;
    if (proj.status == AsrProjectStatus.empty) {
      _currentStep = 0;
    } else if (proj.status == AsrProjectStatus.ready) {
      _currentStep = 0;
    } else if (proj.status == AsrProjectStatus.recognizing) {
      _currentStep = 1;
    } else if (proj.status == AsrProjectStatus.recognized) {
      _currentStep = 2;
    } else if (proj.status == AsrProjectStatus.matched || proj.status == AsrProjectStatus.completed) {
      _currentStep = 3;
    }
  }

  // ========== Step 1: 素材导入 ==========

  Future<void> _pickVideoDir() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择视频目录');
    if (dir == null) return;

    final files = await _scanFiles(dir, _videoExts);
    setState(() => _videoFileList.clear());
    _videoFileList.addAll(files);
    await _saveFileLists();
  }

  Future<void> _pickAudioDir() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择音频目录');
    if (dir == null) return;

    final files = await _scanFiles(dir, _audioExts);
    setState(() => _audioFileList.clear());
    _audioFileList.addAll(files);
    await _saveFileLists();
  }

  Future<List<String>> _scanFiles(String dir, List<String> exts) async {
    final directory = Directory(dir);
    final files = <String>[];
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        if (exts.contains(ext)) {
          files.add(entity.path);
        }
      }
    }
    files.sort();
    return files;
  }

  Future<void> _saveFileLists() async {
    final proj = _project!;
    await AsrProjectService.setVideoFiles(proj, proj.videoDirectory ?? '', List.from(_videoFileList));
    await AsrProjectService.setAudioFiles(proj, proj.audioDirectory ?? '', List.from(_audioFileList));
    setState(() {});
  }

  // ========== Step 2: ASR 识别 ==========

  Future<void> _startRecognition() async {
    if (_project == null) return;
    final proj = _project!;

    // 检查引擎可用性
    final modelVariant = _selectedModelVariant;
    if (!SherpaOnnxPathService.isAvailable || modelVariant.isEmpty || !SherpaOnnxPathService.isModelAvailable(modelVariant)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ASR 引擎不可用，请检查 sherpa-onnx 目录和模型')),
        );
      }
      return;
    }

    setState(() {
      _isRecognizing = true;
      _recognizeError = null;
      _recognizedVideoCount = 0;
      _recognizedAudioCount = 0;
    });

    proj.status = AsrProjectStatus.recognizing;
    await AsrProjectService.updateProject(proj);

    try {
      final sherpaService = SherpaOnnxAsrService();

      // 识别视频文件
      for (int i = 0; i < _videoFileList.length; i++) {
        if (!mounted) break;
        final filePath = _videoFileList[i];
        setState(() {
          _currentRecognizingFile = path.basename(filePath);
          _currentFileProgress = 0;
        });

        try {
          final result = await sherpaService.recognize(
            filePath: filePath,
            modelVariant: modelVariant,
            language: proj.asrLanguage,
            provider: 'auto',
            onProgress: (progress) => setState(() => _currentFileProgress = progress),
          );
          _videoSubs[filePath] = result.clips;
        } catch (e) {
          print('[ASR合板] 视频识别失败 $filePath: $e');
        }

        setState(() => _recognizedVideoCount = i + 1);
      }

      // 识别音频文件
      for (int i = 0; i < _audioFileList.length; i++) {
        if (!mounted) break;
        final filePath = _audioFileList[i];
        setState(() {
          _currentRecognizingFile = path.basename(filePath);
          _currentFileProgress = 0;
        });

        try {
          final result = await sherpaService.recognize(
            filePath: filePath,
            modelVariant: modelVariant,
            language: proj.asrLanguage,
            provider: 'auto',
            onProgress: (progress) => setState(() => _currentFileProgress = progress),
          );
          _audioSubs[filePath] = result.clips;
        } catch (e) {
          print('[ASR合板] 音频识别失败 $filePath: $e');
        }

        setState(() => _recognizedAudioCount = i + 1);
      }

      // 保存结果
      proj.videoSubtitles = Map.from(_videoSubs);
      proj.audioSubtitles = Map.from(_audioSubs);
      proj.status = AsrProjectStatus.recognized;
      await AsrProjectService.updateProject(proj);

      // 默认展开所有文件
      _expandedVideoFiles = Set.from(_videoFileList);
      _expandedAudioFiles = Set.from(_audioFileList);

      setState(() {
        _isRecognizing = false;
        _currentStep = 2;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecognizing = false;
          _recognizeError = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('识别出错: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ========== Step 4: 创建时间线 ==========

  void _createTimeline() {
    final proj = _project!;
    final matchedPairs = _matchPairs.where((mp) => mp.confidence >= 0.7 || mp.isUserConfirmed).toList();

    if (matchedPairs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有有效匹配，无法创建时间线')),
      );
      return;
    }

    // 构建视频轨道（所有视频紧凑排列）
    int cursor = 0;
    final videoClips = <TimelineClip>[];
    final videoDurationMap = <String, int>{};

    for (final vf in _videoFileList) {
      // 获取视频时长（从 ASR 字幕推断，或用默认 5 分钟）
      final subs = _videoSubs[vf];
      int durationMs = 300000; // 默认 5 分钟
      if (subs != null && subs.isNotEmpty) {
        durationMs = subs.last.timelineEndMs;
      }
      videoDurationMap[vf] = durationMs;

      videoClips.add(TimelineClip(
        filePath: vf,
        fileName: path.basename(vf),
        timelineStartMs: cursor,
        durationMs: durationMs,
        mediaIndex: videoClips.length,
      ));
      cursor += durationMs;
    }

    // 构建音频轨道（根据匹配结果裁切）
    final audioClips = <TimelineClip>[];
    final videoTimelineMap = <String, int>{};
    for (final vc in videoClips) {
      videoTimelineMap[vc.filePath] = vc.timelineStartMs;
    }

    for (final mp in matchedPairs) {
      final videoStart = videoTimelineMap[mp.videoFilePath] ?? 0;
      final videoDuration = videoDurationMap[mp.videoFilePath] ?? 300000;
      final sourceStartMs = mp.offsetMs.abs();

      audioClips.add(TimelineClip(
        filePath: mp.audioFilePath,
        fileName: path.basename(mp.audioFilePath),
        timelineStartMs: videoStart,
        durationMs: videoDuration,
        sourceStartMs: sourceStartMs,
        mediaIndex: -1,
      ));
    }

    // 构建字幕轨道（视频 ASR 字幕跟随视频位置）
    final subtitleClips = <TimelineClip>[];
    for (final vc in videoClips) {
      final subs = _videoSubs[vc.filePath];
      if (subs != null) {
        for (final sub in subs) {
          subtitleClips.add(TimelineClip(
            filePath: '',
            fileName: '',
            timelineStartMs: vc.timelineStartMs + sub.timelineStartMs,
            durationMs: sub.durationMs,
            mediaIndex: -1,
            text: sub.text,
          ));
        }
      }
    }

    final timelineProject = TimelineProject(
      videoTrack: TimelineTrack(type: TrackType.video, clips: videoClips),
      audioTracks: [
        TimelineTrack(
          type: TrackType.audio,
          clips: audioClips,
          linkedSubtitleTrack: TimelineTrack(
            type: TrackType.subtitle,
            clips: subtitleClips,
          ),
        ),
      ],
      durationMs: cursor,
      isSyncedProject: true,
    );

    // 通过 AppState 创建项目并跳转
    final appState = AppState();
    final projectName = '${proj.name}-ASR合板';
    appState.addAsrSyncedProject(projectName, timelineProject);

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const ClipScreen()));
    }
  }

  // ========== UI 构建 ==========

  @override
  Widget build(BuildContext context) {
    if (_loading || _project == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final proj = _project!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: Text('${proj.name} — ASR 自动合板'),
      ),
      body: Column(
        children: [
          // 步骤条
          _buildStepIndicator(),
          const Divider(height: 1),
          // 内容区
          Expanded(child: _buildCurrentStep()),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['导入素材', 'ASR 识别', '字幕匹配', '匹配确认', '创建时间线'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isActive = i == _currentStep;
          final isDone = i < _currentStep;
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _currentStep = i),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: isDone
                                  ? Colors.green
                                  : isActive
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey.shade300,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: isDone || isActive ? Colors.white : Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              steps[i],
                              style: TextStyle(
                                fontSize: 13,
                                color: isActive ? Theme.of(context).colorScheme.primary : Colors.grey,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: isDone ? 1 : isActive ? 0.5 : 0,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ],
                    ),
                  ),
                  if (i < steps.length - 1) const SizedBox(width: 16),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Import();
      case 1:
        return _buildStep2Recognize();
      case 2:
        return _buildStep3SubtitleReview();
      case 3:
        return _buildStep4MatchConfirm();
      case 4:
        return _buildStep5Timeline();
      default:
        return _buildStep1Import();
    }
  }

  // ========== Step 1 UI ==========

  Widget _buildStep1Import() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 视频面板
                Expanded(child: _buildMediaPanel('视频素材', _videoFileList, Icons.videocam, _pickVideoDir, () {
                  setState(() { _videoFileList.clear(); });
                  _saveFileLists();
                })),
                const SizedBox(width: 16),
                // 音频面板
                Expanded(child: _buildMediaPanel('音频素材', _audioFileList, Icons.mic, _pickAudioDir, () {
                  setState(() { _audioFileList.clear(); });
                  _saveFileLists();
                })),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 开始按钮
          FilledButton.icon(
            onPressed: _videoFileList.isNotEmpty && _audioFileList.isNotEmpty ? () {
              setState(() => _currentStep = 1);
            } : null,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('开始 ASR 识别'),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPanel(String title, List<String> files, IconData icon, VoidCallback onPick, VoidCallback onClear) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('选择目录'),
                ),
                if (files.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onClear,
                    child: const Text('清空'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: files.isEmpty
                  ? Center(
                      child: Text('点击「选择目录」添加${title.replaceAll('素材', '')}', style: TextStyle(color: Colors.grey.shade500)),
                    )
                  : ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        leading: Icon(icon, size: 16, color: Colors.grey),
                        title: Text(path.basename(files[index]), style: const TextStyle(fontSize: 13)),
                        subtitle: Text(files[index], style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
            ),
            if (files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('共 ${files.length} 个文件', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
          ],
        ),
      ),
    );
  }

  // ========== Step 2 UI ==========

  Widget _buildStep2Recognize() {
    final total = _videoFileList.length + _audioFileList.length;
    final done = _recognizedVideoCount + _recognizedAudioCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 可滚动内容区
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildProgressSection('视频识别', _videoFileList, _recognizedVideoCount, _videoSubs),
                const SizedBox(height: 16),
                _buildProgressSection('音频识别', _audioFileList, _recognizedAudioCount, _audioSubs),
              ],
            ),
          ),
        ),
        // 固定底部操作栏
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isRecognizing)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(value: total > 0 ? done / total : 0),
                ),
              Text(
                _isRecognizing
                    ? '总进度: $done/$total    当前: $_currentRecognizingFile'
                    : _recognizeError != null
                        ? '识别出错: $_recognizeError'
                        : '识别完成',
                style: TextStyle(color: _recognizeError != null ? Colors.red : Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (!_isRecognizing) ...[
                _buildModelSelector(),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _startRecognition,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_recognizeError != null ? '重新识别' : '开始识别'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelSelector() {
    final availableModels = SherpaOnnxPathService.listAvailableModels();
    if (availableModels.isEmpty) {
      return const Text('未检测到可用模型', style: TextStyle(color: Colors.red, fontSize: 12));
    }
    return Row(
      children: [
        const Text('识别模型: ', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            value: _selectedModelVariant.isNotEmpty && availableModels.any((m) => m.variant == _selectedModelVariant)
                ? _selectedModelVariant
                : availableModels.first.variant,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: availableModels.map((m) => DropdownMenuItem(
              value: m.variant,
              child: Text(m.displayLabel, style: const TextStyle(fontSize: 12)),
            )).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedModelVariant = v);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProgressSection(String title, List<String> files, int doneCount, Map<String, List<TimelineClip>> subs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...files.map((f) {
              final isDone = subs.containsKey(f);
              final isCurrent = _isRecognizing && _currentRecognizingFile == path.basename(f);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      isDone ? Icons.check_circle : isCurrent ? Icons.sync : Icons.hourglass_empty,
                      size: 16,
                      color: isDone ? Colors.green : isCurrent ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(path.basename(f), style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (isDone) Text('${subs[f]?.length ?? 0} 条字幕', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      SizedBox(width: 80, child: LinearProgressIndicator(value: _currentFileProgress)),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ========== Step 3 UI（字幕审阅与匹配）==========

  Widget _buildStep3SubtitleReview() {
    final matchedVideos = _matchPairs.map((m) => m.videoFilePath).toSet();
    final matchedAudios = _matchPairs.map((m) => m.audioFilePath).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部操作栏（固定）
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索字幕内容...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchKeyword = v.trim()),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _autoMatch,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('自动匹配'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _oneClickAutoSync,
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('一键自动合板'),
              ),
              const SizedBox(width: 8),
              Chip(
                avatar: const Icon(Icons.link, size: 16),
                label: Text('已匹配 ${_matchPairs.length}/${_videoFileList.length} 对'),
              ),
            ],
          ),
        ),
        // 提示
        if (_selectedVideoClip != null || _selectedAudioClip != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            color: (_selectedVideoClip != null && _selectedAudioClip != null)
                ? Colors.green.withOpacity(0.15)
                : Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            child: Text(
              _selectedVideoClip != null && _selectedAudioClip != null
                  ? '匹配成功! 点击其他字幕可重新匹配'
                  : _selectedVideoClip != null
                      ? '已选视频字幕，请在右栏点击对应音频字幕'
                      : '已选音频字幕，请在左栏点击对应视频字幕',
              style: TextStyle(
                fontSize: 12,
                color: (_selectedVideoClip != null && _selectedAudioClip != null)
                    ? Colors.green
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        // 双栏内容区
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildFileColumn(
                    files: _videoFileList, subs: _videoSubs,
                    badgeColor: Colors.blue, badgeLabel: '视频',
                    selectedPath: _selectedVideoPath, selectedClip: _selectedVideoClip,
                    expandedFiles: _expandedVideoFiles, matchedPaths: matchedVideos,
                    onToggleExpand: (p) => setState(() {
                      _expandedVideoFiles.contains(p) ? _expandedVideoFiles.remove(p) : _expandedVideoFiles.add(p);
                    }),
                    onSelectClip: (filePath, clip) => setState(() {
                      _selectedVideoPath = filePath;
                      _selectedVideoClip = clip;
                      _tryCreateManualMatch();
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                const VerticalDivider(width: 1),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFileColumn(
                    files: _audioFileList, subs: _audioSubs,
                    badgeColor: Colors.green, badgeLabel: '音频',
                    selectedPath: _selectedAudioPath, selectedClip: _selectedAudioClip,
                    expandedFiles: _expandedAudioFiles, matchedPaths: matchedAudios,
                    onToggleExpand: (p) => setState(() {
                      _expandedAudioFiles.contains(p) ? _expandedAudioFiles.remove(p) : _expandedAudioFiles.add(p);
                    }),
                    onSelectClip: (filePath, clip) => setState(() {
                      _selectedAudioPath = filePath;
                      _selectedAudioClip = clip;
                      _tryCreateManualMatch();
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 固定底部操作栏
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _currentStep = 1),
                child: const Text('返回重新识别'),
              ),
              FilledButton.icon(
                onPressed: _matchPairs.isNotEmpty ? () {
                  _saveMatchResults();
                  setState(() => _currentStep = 3);
                } : null,
                icon: const Icon(Icons.check),
                label: const Text('确认匹配，下一步'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建单栏文件列表（视频或音频）
  Widget _buildFileColumn({
    required List<String> files,
    required Map<String, List<TimelineClip>> subs,
    required Color badgeColor,
    required String badgeLabel,
    required String? selectedPath,
    required TimelineClip? selectedClip,
    required Set<String> expandedFiles,
    required Set<String> matchedPaths,
    required void Function(String) onToggleExpand,
    required void Function(String filePath, TimelineClip clip) onSelectClip,
  }) {
    if (files.isEmpty) {
      return Center(child: Text('无$badgeLabel文件', style: TextStyle(color: Colors.grey.shade500)));
    }

    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final filePath = files[index];
        final fileName = path.basename(filePath);
        final clips = subs[filePath] ?? [];
        final isExpanded = expandedFiles.contains(filePath);
        final isMatched = matchedPaths.contains(filePath);
        final isFileSelected = selectedPath == filePath;

        final matchPair = _matchPairs.where((m) =>
          (badgeLabel == '视频' && m.videoFilePath == filePath) ||
          (badgeLabel == '音频' && m.audioFilePath == filePath)
        ).firstOrNull;

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: isFileSelected
                ? BorderSide(color: badgeColor, width: 2)
                : isMatched
                    ? BorderSide(color: Colors.green.shade300, width: 1)
                    : BorderSide.none,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 文件头
              InkWell(
                onTap: () => onToggleExpand(filePath),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(badgeLabel, style: TextStyle(fontSize: 10, color: badgeColor, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(fileName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (isMatched && matchPair != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text('${matchPair.confidenceLabel}置信', style: const TextStyle(fontSize: 10, color: Colors.green)),
                        ),
                      const SizedBox(width: 4),
                      Text('${clips.length}条', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              // 展开的字幕列表（含搜索上下文）
              if (isExpanded && clips.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                    color: isFileSelected ? badgeColor.withOpacity(0.05) : null,
                  ),
                  constraints: const BoxConstraints(maxHeight: 350),
                  child: _buildSubtitleList(clips, filePath, badgeColor, selectedClip, onSelectClip),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 构建字幕列表，搜索时显示上下文
  Widget _buildSubtitleList(
    List<TimelineClip> clips,
    String filePath,
    Color badgeColor,
    TimelineClip? selectedClip,
    void Function(String, TimelineClip) onSelectClip,
  ) {
    // 无搜索时显示全部字幕
    if (_searchKeyword.isEmpty) {
      return ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: clips.length,
        itemBuilder: (context, i) => _buildSubtitleRow(
          clips[i], filePath, badgeColor, selectedClip, onSelectClip, false,
        ),
      );
    }

    // 有搜索时：找到匹配索引，构建带上下文的显示列表
    final kw = _searchKeyword.toLowerCase();
    final matchIndices = <int>[];
    for (int i = 0; i < clips.length; i++) {
      if ((clips[i].text ?? '').toLowerCase().contains(kw)) {
        matchIndices.add(i);
      }
    }

    if (matchIndices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('未找到匹配字幕', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
      );
    }

    // 收集需要显示的索引（匹配项 ± 2条上下文）
    final displayIndices = <int>{};
    for (final mi in matchIndices) {
      for (int j = (mi - 2).clamp(0, clips.length - 1); j <= (mi + 2).clamp(0, clips.length - 1); j++) {
        displayIndices.add(j);
      }
    }
    final sorted = displayIndices.toList()..sort();

    // 在不同匹配组之间插入分隔
    final items = <int?>[];
    for (int i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) {
        items.add(null); // 分隔标记
      }
      items.add(sorted[i]);
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      itemBuilder: (context, i) {
        if (items[i] == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Divider(height: 1, color: Colors.grey.shade300),
          );
        }
        final idx = items[i]!;
        final isMatch = (clips[idx].text ?? '').toLowerCase().contains(kw);
        return _buildSubtitleRow(
          clips[idx], filePath, badgeColor, selectedClip, onSelectClip, !isMatch,
        );
      },
    );
  }

  /// 单行字幕条目
  Widget _buildSubtitleRow(
    TimelineClip clip,
    String filePath,
    Color badgeColor,
    TimelineClip? selectedClip,
    void Function(String, TimelineClip) onSelectClip,
    bool isContext,
  ) {
    final isSelected = selectedClip == clip;
    final text = clip.text ?? '';
    final startMs = clip.timelineStartMs;
    final endMs = clip.timelineEndMs;

    return InkWell(
      onTap: () => onSelectClip(filePath, clip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        color: isSelected
            ? badgeColor.withOpacity(0.2)
            : isContext
                ? Colors.transparent
                : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(
                '${_formatMs(startMs)} - ${_formatMs(endMs)}',
                style: TextStyle(
                  fontSize: 10,
                  color: isContext ? Colors.grey.shade400 : Colors.grey.shade500,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: isContext ? Colors.grey.shade400 : null,
                  fontWeight: isContext ? FontWeight.normal : (isSelected ? FontWeight.bold : FontWeight.normal),
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, size: 14, color: badgeColor),
          ],
        ),
      ),
    );
  }

  /// 格式化毫秒为 MM:SS
  String _formatMs(int ms) {
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  /// 尝试创建手动匹配（字幕级别）
  void _tryCreateManualMatch() {
    if (_selectedVideoPath == null || _selectedAudioPath == null) return;
    if (_selectedVideoClip == null || _selectedAudioClip == null) return;

    final vp = _selectedVideoPath!;
    final ap = _selectedAudioPath!;

    // 移除已存在的匹配
    _matchPairs.removeWhere((m) => m.videoFilePath == vp || m.audioFilePath == ap);

    // 用点击的字幕时间戳计算偏移
    final offsetMs = _selectedVideoClip!.timelineStartMs - _selectedAudioClip!.timelineStartMs;

    _matchPairs.add(MatchPair(
      videoFilePath: vp,
      audioFilePath: ap,
      confidence: 1.0,
      offsetMs: offsetMs,
      matchedWindowCount: 1,
      totalWindowCount: 1,
      isManualMatch: true,
      isUserConfirmed: true,
    ));
  }

  /// 全自动匹配
  void _autoMatch() {
    setState(() {
      _matchPairs = AsrMatchService.matchAll(_videoSubs, _audioSubs);
      _selectedVideoPath = null;
      _selectedAudioPath = null;
    });
    _saveMatchResults();
  }

  /// 一键自动合板：匹配 → 创建时间线 → 跳转编辑器
  void _oneClickAutoSync() {
    final pairs = AsrMatchService.matchAll(_videoSubs, _audioSubs);
    if (pairs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到可匹配的视频-音频对，请检查字幕内容')),
      );
      return;
    }
    setState(() {
      _matchPairs = pairs;
      _selectedVideoPath = null;
      _selectedAudioPath = null;
      _selectedVideoClip = null;
      _selectedAudioClip = null;
    });
    _saveMatchResults();
    _createTimeline();
  }

  /// 保存匹配结果到数据库
  Future<void> _saveMatchResults() async {
    final proj = _project!;
    proj.matchPairs = List.from(_matchPairs);
    proj.status = AsrProjectStatus.matched;
    await AsrProjectService.updateProject(proj);
  }

  // ========== Step 4 UI（匹配确认）==========

  Widget _buildStep4MatchConfirm() {
    final matched = _matchPairs.where((m) => m.confidence >= 0.7).toList();
    final unmatched = _matchPairs.where((m) => m.confidence < 0.7).toList();
    final matchedVideos = _matchPairs.map((m) => m.videoFilePath).toSet();
    final unmatchedVideos = _videoFileList.where((f) => !matchedVideos.contains(f)).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '自动匹配完成：成功匹配 ${matched.length} 对，${unmatched.length + unmatchedVideos.length} 个视频未匹配',
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                // 匹配结果
                ...matched.map((mp) => _buildMatchCard(mp, true)),
                // 低置信度
                ...unmatched.map((mp) => _buildMatchCard(mp, false)),
                // 未匹配视频
                ...unmatchedVideos.map((vf) => ListTile(
                      leading: const Icon(Icons.close, color: Colors.red, size: 16),
                      title: Text(path.basename(vf), style: const TextStyle(fontSize: 13)),
                      subtitle: const Text('未匹配到音频'),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _currentStep = 2),
                child: const Text('返回修改'),
              ),
              FilledButton.icon(
                onPressed: matched.isNotEmpty ? () => setState(() => _currentStep = 4) : null,
                icon: const Icon(Icons.check),
                label: const Text('确认匹配，创建时间线'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMatchCard(MatchPair mp, bool isGood) {
    Color confColor;
    if (mp.confidence >= 0.9) {
      confColor = Colors.green;
    } else if (mp.confidence >= 0.7) {
      confColor = Colors.orange;
    } else {
      confColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(isGood ? Icons.link : Icons.warning_amber, color: confColor),
        title: Row(
          children: [
            Flexible(child: Text(path.basename(mp.videoFilePath), style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.sync_alt, size: 14)),
            Flexible(child: Text(path.basename(mp.audioFilePath), style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
          ],
        ),
        subtitle: Text('置信度 ${(mp.confidence * 100).toStringAsFixed(0)}% | 匹配 ${mp.matchedWindowCount} 窗口 | 偏移 ${mp.offsetMs}ms'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: confColor.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
          child: Text('${mp.confidenceLabel}置信', style: TextStyle(fontSize: 11, color: confColor)),
        ),
      ),
    );
  }

  // ========== Step 5 UI ==========

  Widget _buildStep5Timeline() {
    final validPairs = _matchPairs.where((mp) => mp.confidence >= 0.7 || mp.isUserConfirmed).toList();
    final matchedVideos = validPairs.map((m) => m.videoFilePath).toSet();
    final unmatchedVideos = _videoFileList.where((f) => !matchedVideos.contains(f)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 可滚动内容区
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('裁切方案', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...validPairs.map((mp) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(width: 200, child: Text(path.basename(mp.videoFilePath), style: const TextStyle(fontSize: 13))),
                              const Text(' ← '),
                              Flexible(
                                child: Text(
                                  '${path.basename(mp.audioFilePath)} (偏移 ${mp.offsetMs}ms)',
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )),
                    if (unmatchedVideos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('未匹配视频: ${unmatchedVideos.map((f) => path.basename(f)).join(', ')}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        // 固定底部操作栏
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _currentStep = 3),
                child: const Text('返回修改匹配'),
              ),
              FilledButton.icon(
                onPressed: _createTimeline,
                icon: const Icon(Icons.movie_creation),
                label: const Text('创建时间线并打开编辑器'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
