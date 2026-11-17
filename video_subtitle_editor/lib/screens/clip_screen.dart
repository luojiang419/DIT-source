
import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/timeline_model.dart';
import '../services/media_scan_service.dart';
import '../services/subtitle_service.dart';
import '../services/export_service.dart';
import '../services/waveform_service.dart';
import '../services/player_config_service.dart';
import '../services/trim_service.dart';
import '../services/timecode_service.dart';
import '../state/app_state.dart';
import '../services/auto_sync_service.dart';
import '../services/multipoint_sync_service.dart';
import '../services/sherpa_onnx_path_service.dart';
import '../services/sherpa_onnx_asr_service.dart';
import '../widgets/dialogs/auto_sync_dialog.dart';
import '../widgets/dialogs/trim_confirm_dialog.dart';
import '../widgets/timeline/timeline_panel.dart';

class ClipScreen extends StatefulWidget {
  const ClipScreen({super.key});

  @override
  State<ClipScreen> createState() => _ClipScreenState();
}

class _MultiMatchSelectionDialog extends StatefulWidget {
  final String keyword;
  final List<TimelineClip> videoMatches;
  final Map<int, List<TimelineClip>> audioMatches;
  final String Function(int) formatMs;

  const _MultiMatchSelectionDialog({
    required this.keyword,
    required this.videoMatches,
    required this.audioMatches,
    required this.formatMs,
  });

  @override
  State<_MultiMatchSelectionDialog> createState() => _MultiMatchSelectionDialogState();
}

class _MultiMatchSelectionDialogState extends State<_MultiMatchSelectionDialog> {
  late TimelineClip _selectedVideoClip;
  late Map<int, TimelineClip> _selectedAudioClips;

  @override
  void initState() {
    super.initState();
    _selectedVideoClip = widget.videoMatches.first;
    _selectedAudioClips = {};
    for (final entry in widget.audioMatches.entries) {
      _selectedAudioClips[entry.key] = entry.value.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('找到多处包含“${widget.keyword}”的台词'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请选择作为对齐基准的视频台词：', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...widget.videoMatches.map((clip) {
                return RadioListTile<TimelineClip>(
                  title: Text(clip.text ?? ''),
                  subtitle: Text('时间: ${widget.formatMs(clip.timelineStartMs)}'),
                  value: clip,
                  groupValue: _selectedVideoClip,
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedVideoClip = val);
                  },
                );
              }),
              const Divider(height: 32),
              const Text('请确认各音频轨道需要对齐的台词：', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...widget.audioMatches.entries.map((entry) {
                final trackIndex = entry.key;
                final matches = entry.value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('音频轨道 ${trackIndex + 1}:', style: const TextStyle(color: Colors.grey)),
                    ...matches.map((clip) {
                      return RadioListTile<TimelineClip>(
                        title: Text(clip.text ?? ''),
                        subtitle: Text('时间: ${widget.formatMs(clip.timelineStartMs)}'),
                        value: clip,
                        groupValue: _selectedAudioClips[trackIndex],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedAudioClips[trackIndex] = val);
                          }
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final result = <int, TimelineClip>{
              -1: _selectedVideoClip,
            };
            result.addAll(_selectedAudioClips);
            Navigator.pop(context, result);
          },
          child: const Text('确认对齐'),
        ),
      ],
    );
  }
}

class _ClipScreenState extends State<ClipScreen> {
  late final Player _player;
  late final VideoController _controller;
  final MediaScanService _scanService = MediaScanService();

  TimelineProject? _timelineProject;
  bool _isLoading = false;
  String? _loadedRoot;

  // Player State Sync
  int _currentGlobalMs = 0;
  int _currentClipIndex = 0;
  
  final TimelinePanelController _timelineController = TimelinePanelController();
  
  // 侧边栏搜索关键词与对齐选择
  String _sidebarSearchKeyword = '';
  TimelineClip? _selectedVideoSubtitleForSync;
  TimelineClip? _selectedAudioSubtitleForSync;
  int? _selectedAudioSubtitleTrackIndexForSync;

  StreamSubscription? _posSub;
  StreamSubscription? _playlistSub;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        // 如果当前焦点是输入框，不拦截空格键
        final primaryFocus = FocusManager.instance.primaryFocus;
        final focusContext = primaryFocus?.context;
        // 检查焦点是否在任何文本输入组件上（包括中文输入法场景）
        if (focusContext != null && focusContext.widget is EditableText) {
          return KeyEventResult.ignored;
        }
        // 额外检查：如果焦点节点本身声明接受文本输入，也不拦截
        if (primaryFocus != null && primaryFocus.context != null) {
          bool isInTextField = false;
          primaryFocus.context!.visitAncestorElements((element) {
            if (element.widget is TextField ||
                element.widget is EditableText ||
                element.widget is TextFormField) {
              isInTextField = true;
              return false;
            }
            return true;
          });
          if (isInTextField) return KeyEventResult.ignored;
        }

        if (_player.state.playing) {
          _player.pause();
        } else {
          _player.play();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    // Use optimized configuration with hardware acceleration
    _player = Player(
      configuration: PlayerConfigService.getOptimizedConfiguration(),
    );
    _controller = VideoController(_player);

    // Enable hardware decoding (CUDA/NVDEC on NVIDIA GPUs)
    PlayerConfigService.enableHardwareDecoding(_player);

    _posSub = _player.stream.position.listen((pos) {
      if (_timelineProject == null) return;
      if (_currentClipIndex >= _timelineProject!.videoTrack!.clips.length) return;
      
      final clip = _timelineProject!.videoTrack!.clips[_currentClipIndex];
      final global = clip.timelineStartMs + pos.inMilliseconds;
      
      if (global != _currentGlobalMs) {
        setState(() {
          _currentGlobalMs = global;
        });
      }
    });

    _playlistSub = _player.stream.playlist.listen((event) {
      setState(() {
        _currentClipIndex = event.index;
      });
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playlistSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadProject(String rootDir) async {
    if (_loadedRoot == rootDir) return;
    
    setState(() {
      _isLoading = true;
      _loadedRoot = rootDir;
    });

    try {
      final appState = context.read<AppState>();
      final projectData = appState.selectedProject;
      
      // 如果本地已保存 TimelineProject 数据，直接恢复
      // 但如果没有 sourceTimecodes（旧版本数据），强制重新扫描以应用源时间码平铺
      if (projectData != null && projectData.timelineProject != null) {
        final savedTimeline = projectData.timelineProject!;

        // 旧数据没有源时间码记录，需要重新扫描
        if (savedTimeline.sourceTimecodes.isNotEmpty) {
          // 构建播放列表
          final medias = <Media>[];
          if (savedTimeline.videoTrack != null) {
            for (final clip in savedTimeline.videoTrack!.clips) {
              medias.add(Media(File(clip.filePath).uri.toString()));
            }
          }

          await _player.open(Playlist(medias), play: false);

          if (mounted) {
            setState(() {
              _timelineProject = savedTimeline;
              _isLoading = false;
            });
          }
          return;
        }
        // sourceTimecodes 为空 → 旧版本数据，继续往下走重新扫描
      }

      // 如果没有本地保存的 TimelineProject 数据，执行首次初始化扫描
      // 1. Scan files
      final files = await _scanService.scanVideos(rootDir);

      // 2. Build Timeline & Playlist
      final videoClips = <TimelineClip>[];
      final medias = <Media>[];
      final timecodeService = TimecodeService();
      final sourceTimecodes = <String, SourceTimecode>{};

      // 先获取所有文件时长
      final fileDurations = <String, int>{};
      for (final f in files) {
        final durationMs = await _scanService.getDurationMs(f.path);
        if (durationMs > 0) fileDurations[f.path] = durationMs;
      }

      // 批量读取源时间码
      final timecodes = await timecodeService.extractTimecodes(
        fileDurations.keys.toList(),
        fileDurations,
      );
      sourceTimecodes.addAll(timecodes);

      // ── 排列方式选择 ────────────────────────────────────────
      // 有时间码时弹窗让用户选择排列方式
      bool useTimecodeLayout = false;
      if (timecodes.isNotEmpty && mounted) {
        final tcFileCount = fileDurations.keys
            .where((p) => timecodes.containsKey(p))
            .length;
        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('导入视频'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('共 ${fileDurations.length} 个视频文件，'
                    '${tcFileCount} 个有源时间码。'),
                const SizedBox(height: 16),
                const Text('时间轴排列方式：',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'compact'),
                child: const Text('紧凑排列'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'timecode'),
                child: const Text('按时间码平铺（推荐）'),
              ),
            ],
          ),
        );
        useTimecodeLayout = choice == 'timecode';
      }

      // ── 构建视频片段 ────────────────────────────────────────
      int maxEndMs = 0;

      if (useTimecodeLayout && timecodes.isNotEmpty) {
        // 时间码平铺模式：按源时间码排列，保留录制间隔空白
        final earliestMs = timecodes.values
            .map((tc) => tc.startMs)
            .reduce(min);

        for (final f in files) {
          final durationMs = fileDurations[f.path];
          if (durationMs == null || durationMs <= 0) continue;

          final tc = timecodes[f.path];
          int timelineStart;
          if (tc != null) {
            timelineStart = tc.startMs - earliestMs;
            if (timelineStart < 0) timelineStart = 0;
          } else {
            // 无时间码的文件排到最后
            timelineStart = maxEndMs;
          }

          final videoClip = TimelineClip(
            filePath: f.path,
            fileName: f.name,
            timelineStartMs: timelineStart,
            durationMs: durationMs,
            mediaIndex: medias.length,
          );
          videoClips.add(videoClip);
          medias.add(Media(File(f.path).uri.toString()));

          final endMs = timelineStart + durationMs;
          if (endMs > maxEndMs) maxEndMs = endMs;
        }
      } else {
        // 紧凑排列模式（原有逻辑）：首尾相接
        int accumulatedMs = 0;

        for (final f in files) {
          final durationMs = fileDurations[f.path];
          if (durationMs == null || durationMs <= 0) continue;

          final videoClip = TimelineClip(
            filePath: f.path,
            fileName: f.name,
            timelineStartMs: accumulatedMs,
            durationMs: durationMs,
            mediaIndex: medias.length,
          );
          videoClips.add(videoClip);
          medias.add(Media(File(f.path).uri.toString()));

          accumulatedMs += durationMs;
          if (accumulatedMs > maxEndMs) maxEndMs = accumulatedMs;
        }
      }

      final project = TimelineProject(
        videoTrack: TimelineTrack(type: TrackType.video, clips: videoClips),
        audioTracks: const [],
        durationMs: maxEndMs > 0 ? maxEndMs : 0,
        sourceTimecodes: sourceTimecodes,
      );

      // 3. Initialize Player
      await _player.open(Playlist(medias), play: false);

      if (mounted) {
        setState(() {
          _timelineProject = project;
          _isLoading = false;
        });
        
        // 自动保存初始扫描状态
        if (projectData != null) {
          await appState.updateTimelineProject(projectData.id, project);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载工程失败: $e')),
        );
      }
    }
  }

  void _handleSeek(int ms) {
    if (_timelineProject == null) return;
    
    // 自动滚动时间轴
    _timelineController.scrollToTime(ms);

    // Find which clip contains this time
    final clips = _timelineProject!.videoTrack!.clips;
    TimelineClip? targetClip;
    
    for (final clip in clips) {
      if (ms >= clip.timelineStartMs && ms < clip.timelineEndMs) {
        targetClip = clip;
        break;
      }
    }
    
    if (targetClip != null) {
      if (_currentClipIndex != targetClip.mediaIndex) {
        _player.jump(targetClip.mediaIndex);
      }
      final localPos = ms - targetClip.timelineStartMs;
      _player.seek(Duration(milliseconds: localPos));
    } else {
      // 自由播放模式：如果点击的位置没有视频片段（例如音频超出视频时长），
      // 我们仍然允许跳转，但此时播放器应该处于暂停或停止状态（或者播放最后一帧）
      // 这里我们简单地让播放器跳转到视频末尾并暂停，或者如果支持，可以尝试不做任何播放器操作只移动时间轴
      
      // 现在的逻辑是：如果点击了视频之外的区域，就不操作播放器跳转了？
      // 不，用户说“播放光标会自动跳回到视频轨道最末尾的视频的尾部”，这说明之前的逻辑强制了 targetClip = clips.last
      
      // 修复：当没有找到 targetClip 时，不强制设置 targetClip，
      // 而是允许时间轴光标停留在该位置。
      // 但播放器本身是播放视频的，如果超出了视频范围，播放器应该怎么办？
      // 通常做法是：如果超出所有视频范围，暂停播放器，或者显示黑屏。
      // 由于我们使用的是 media_kit，它可能不支持“无媒体”播放。
      // 所以我们只更新 UI 上的 _currentGlobalMs (这在 onSeek 回调中应该已经由 TimelinePanel 更新了?)
      // 不，TimelinePanel 只是回调了 onSeek，并没有自己更新状态，状态是由 ClipScreen 的 _currentGlobalMs 控制的。
      
      // 我们需要手动更新 _currentGlobalMs
      setState(() {
        _currentGlobalMs = ms;
      });
      
      // 如果超出了视频范围，暂停播放
      if (clips.isNotEmpty && ms >= clips.last.timelineEndMs) {
         _player.pause();
      }
    }
  }

  Future<void> _saveCurrentTimeline() async {
    if (_timelineProject == null) return;
    final appState = context.read<AppState>();
    final project = appState.selectedProject;
    if (project != null) {
      await appState.updateTimelineProject(project.id, _timelineProject!);
    }
  }

  Future<void> _importAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path!;
      final name = result.files.single.name;
      
      setState(() {
        _isLoading = true;
      });
      
      final durationMs = await _scanService.getDurationMs(path);
      
      if (durationMs <= 0) {
        if (mounted) {
          setState(() { _isLoading = false; });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取音频时长')));
        }
        return;
      }

      final newClip = TimelineClip(
        filePath: path,
        fileName: name,
        timelineStartMs: 0,
        durationMs: durationMs,
        mediaIndex: -1,
      );

      // 提取音频源时间码
      final timecodeService = TimecodeService();
      final audioTC = await timecodeService.extractTimecode(path, durationMs);

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_timelineProject != null) {
            final newTrack = TimelineTrack(type: TrackType.audio, clips: [newClip]);
            final currentTracks = List<TimelineTrack>.from(_timelineProject!.audioTracks);
            currentTracks.add(newTrack);

            int newDuration = _timelineProject!.durationMs;
            if (newClip.timelineEndMs > newDuration) {
              newDuration = newClip.timelineEndMs;
            }

            // 合并音频时间码到 sourceTimecodes
            final newTimecodes = Map<String, SourceTimecode>.from(_timelineProject!.sourceTimecodes);
            if (audioTC != null) {
              newTimecodes[path] = audioTC;
            }

            _timelineProject = TimelineProject(
              videoTrack: _timelineProject!.videoTrack,
              audioTracks: currentTracks,
              subtitleTrack: _timelineProject!.subtitleTrack,
              durationMs: newDuration,
              sourceTimecodes: newTimecodes,
            );
            _saveCurrentTimeline();
          } else {
            final newTrack = TimelineTrack(type: TrackType.audio, clips: [newClip]);
            final newTimecodes = <String, SourceTimecode>{};
            if (audioTC != null) {
              newTimecodes[path] = audioTC;
            }
            _timelineProject = TimelineProject(
              audioTracks: [newTrack],
              durationMs: newClip.timelineEndMs,
              sourceTimecodes: newTimecodes,
            );
            _saveCurrentTimeline();
          }
        });
      }

      // 自动提示识别字幕
      if (mounted && SherpaOnnxPathService.isAvailable) {
        _promptAsrIfAvailable();
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入音频失败: $e')));
      }
    }
  }

  Future<void> _importAudioFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择音频文件夹',
      );
      if (result == null) return;

      setState(() => _isLoading = true);
      
      final audioFiles = await _scanService.scanAudios(result);
      if (audioFiles.isEmpty) {
        if (mounted) {
           setState(() => _isLoading = false);
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该文件夹没有找到音频文件')));
        }
        return;
      }
      
      final newClips = <TimelineClip>[];
      final audioTimecodes = <String, SourceTimecode>{};
      int currentStart = 0;
      final timecodeService = TimecodeService();

      for (final f in audioFiles) {
         final durationMs = await _scanService.getDurationMs(f.path);
         if (durationMs > 0) {
           newClips.add(TimelineClip(
             filePath: f.path,
             fileName: f.name,
             timelineStartMs: currentStart,
             durationMs: durationMs,
             mediaIndex: -1,
           ));
           currentStart += durationMs;

           // 提取音频源时间码
           final tc = await timecodeService.extractTimecode(f.path, durationMs);
           if (tc != null) {
             audioTimecodes[f.path] = tc;
           }
         }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_timelineProject != null && newClips.isNotEmpty) {
            final newTrack = TimelineTrack(type: TrackType.audio, clips: newClips);
            final currentTracks = List<TimelineTrack>.from(_timelineProject!.audioTracks);
            currentTracks.add(newTrack);

            int newDuration = _timelineProject!.durationMs;
            if (currentStart > newDuration) {
              newDuration = currentStart;
            }

            // 合并音频时间码到 sourceTimecodes
            final newTimecodes = Map<String, SourceTimecode>.from(_timelineProject!.sourceTimecodes);
            newTimecodes.addAll(audioTimecodes);

            _timelineProject = TimelineProject(
              videoTrack: _timelineProject!.videoTrack,
              audioTracks: currentTracks,
              subtitleTrack: _timelineProject!.subtitleTrack,
              durationMs: newDuration,
              sourceTimecodes: newTimecodes,
            );
            _saveCurrentTimeline();
          } else if (newClips.isNotEmpty) {
            final newTrack = TimelineTrack(type: TrackType.audio, clips: newClips);
            _timelineProject = TimelineProject(
              audioTracks: [newTrack],
              durationMs: currentStart,
              sourceTimecodes: audioTimecodes,
            );
            _saveCurrentTimeline();
          }
        });
      }

      // 自动提示识别字幕
      if (mounted && SherpaOnnxPathService.isAvailable) {
        _promptAsrIfAvailable();
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入音频目录失败: $e')));
      }
    }
  }

  Future<void> _importSubtitle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt'],
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path!;
      
      // Ask user which track to bind to
      if (!mounted) return;
      final target = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('将字幕绑定到哪个轨道？'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'video'),
              child: const Text('视频轨道'),
            ),
            if (_timelineProject != null)
              ..._timelineProject!.audioTracks.asMap().entries.map((e) => 
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, 'audio_${e.key}'),
                  child: Text('音频轨道 ${e.key + 1}'),
                ),
              ),
          ],
        ),
      );
      
      if (target == null) return;

      setState(() {
        _isLoading = true;
      });

      final service = SubtitleService();
      final clips = await service.parseSrt(path);
      final subtitleTrack = TimelineTrack(type: TrackType.subtitle, clips: clips);

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_timelineProject != null) {
            TimelineTrack? newVideoTrack = _timelineProject!.videoTrack;
            List<TimelineTrack> newAudioTracks = List.from(_timelineProject!.audioTracks);

            if (target == 'video' && newVideoTrack != null) {
              newVideoTrack = TimelineTrack(
                type: newVideoTrack.type,
                clips: newVideoTrack.clips,
                linkedSubtitleTrack: subtitleTrack,
              );
            } else if (target.startsWith('audio_')) {
              final index = int.parse(target.split('_')[1]);
              if (index < newAudioTracks.length) {
                final oldTrack = newAudioTracks[index];
                newAudioTracks[index] = TimelineTrack(
                  type: oldTrack.type,
                  clips: oldTrack.clips,
                  linkedSubtitleTrack: subtitleTrack,
                );
              }
            }

            _timelineProject = TimelineProject(
              videoTrack: newVideoTrack,
              audioTracks: newAudioTracks,
              subtitleTrack: _timelineProject!.subtitleTrack, // Legacy track, maybe keep or remove
              durationMs: _calculateDuration(
                newVideoTrack,
                newAudioTracks,
                _timelineProject!.subtitleTrack,
              ),
            );
            _saveCurrentTimeline();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('解析字幕失败: $e')));
      }
    }
  }

  Future<void> _autoSyncByText() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('一键对齐 (基于字幕)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('输入一句视频和音频中都存在的台词（如“你叫什么名字”）：'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '输入对齐台词',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('对齐'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;
    final keyword = result.trim();

    setState(() => _isLoading = true);

    try {
      // 1. 查找所有匹配的视频字幕片段
      final videoMatches = <TimelineClip>[];
      if (_timelineProject?.videoTrack?.linkedSubtitleTrack != null) {
        for (final clip in _timelineProject!.videoTrack!.linkedSubtitleTrack!.clips) {
          if (clip.text != null && clip.text!.contains(keyword)) {
            videoMatches.add(clip);
          }
        }
      }

      if (videoMatches.isEmpty) {
        throw Exception('在视频字幕中未找到“$keyword”');
      }

      // 2. 查找所有匹配的音频字幕片段
      // 结构: audioTrackIndex -> 匹配的clip列表
      final audioMatches = <int, List<TimelineClip>>{};
      
      for (int i = 0; i < _timelineProject!.audioTracks.length; i++) {
        final audioTrack = _timelineProject!.audioTracks[i];
        if (audioTrack.linkedSubtitleTrack == null) continue;
        
        final trackMatches = <TimelineClip>[];
        for (final clip in audioTrack.linkedSubtitleTrack!.clips) {
          if (clip.text != null && clip.text!.contains(keyword)) {
            trackMatches.add(clip);
          }
        }
        
        if (trackMatches.isNotEmpty) {
          audioMatches[i] = trackMatches;
        }
      }

      if (audioMatches.isEmpty) {
        throw Exception('在音频字幕中未找到“$keyword”');
      }

      // 3. 如果存在多处匹配，需要用户选择基准
      TimelineClip? selectedVideoClip = videoMatches.first;
      
      // 我们为每个有匹配的音频轨道，挑选一条字幕。默认选第一条，如果有多个匹配则让用户选
      // 简化交互：为了同时处理多轨和多匹配，我们弹出一个综合确认对话框
      final Map<int, TimelineClip>? userSelections = await _showMultiMatchSelectionDialog(
        keyword,
        videoMatches,
        audioMatches,
      );
      
      if (userSelections == null) {
        // 用户取消了对齐
        setState(() => _isLoading = false);
        return;
      }

      // 从用户选择中获取视频基准字幕
      selectedVideoClip = userSelections[-1]; // -1 代表视频轨
      if (selectedVideoClip == null) {
        throw Exception('未选择有效的视频基准字幕');
      }

      // 4. 执行对齐
      int alignedCount = 0;
      bool audioUpdated = false;
      List<TimelineTrack> newAudioTracks = List.from(_timelineProject!.audioTracks);

      for (final entry in userSelections.entries) {
        final trackIndex = entry.key;
        if (trackIndex == -1) continue; // 跳过视频轨记录

        final selectedAudioClip = entry.value;
        final audioTrack = newAudioTracks[trackIndex];
        
        final offsetMs = selectedVideoClip.timelineStartMs - selectedAudioClip.timelineStartMs;
        
        if (offsetMs != 0 && audioTrack.clips.isNotEmpty) {
           // 将偏移量应用到音频轨道的所有片段
           final newAudioClips = audioTrack.clips.map((c) {
             return TimelineClip(
               id: c.id,
               filePath: c.filePath,
               fileName: c.fileName,
               timelineStartMs: c.timelineStartMs + offsetMs,
               durationMs: c.durationMs,
               mediaIndex: c.mediaIndex,
               text: c.text,
             );
           }).toList();

           // 将偏移量应用到绑定的字幕片段
           TimelineTrack? newLinkedSub;
           if (audioTrack.linkedSubtitleTrack != null) {
             final newSubClips = audioTrack.linkedSubtitleTrack!.clips.map((c) {
               return TimelineClip(
                 id: c.id,
                 filePath: c.filePath,
                 fileName: c.fileName,
                 timelineStartMs: c.timelineStartMs + offsetMs,
                 durationMs: c.durationMs,
                 mediaIndex: c.mediaIndex,
                 text: c.text,
               );
             }).toList();
             newLinkedSub = TimelineTrack(
               type: TrackType.subtitle,
               clips: newSubClips,
             );
           }

           newAudioTracks[trackIndex] = TimelineTrack(
             type: audioTrack.type,
             clips: newAudioClips,
             linkedSubtitleTrack: newLinkedSub,
           );
           
           alignedCount++;
           audioUpdated = true;
        }
      }

      if (audioUpdated) {
        setState(() {
          _timelineProject = TimelineProject(
            videoTrack: _timelineProject!.videoTrack,
            audioTracks: newAudioTracks,
            subtitleTrack: _timelineProject!.subtitleTrack,
            durationMs: _calculateDuration(
               _timelineProject!.videoTrack,
               newAudioTracks,
               _timelineProject!.subtitleTrack
            ),
          );
          _saveCurrentTimeline();
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(alignedCount > 0 ? '已对齐 $alignedCount 个音频轨道' : '对齐完成，未产生位移')),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('对齐失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 弹窗让用户在多个匹配项中进行选择，返回每个轨道（视频=-1，音频=index）最终选中的字幕 Clip
  Future<Map<int, TimelineClip>?> _showMultiMatchSelectionDialog(
    String keyword,
    List<TimelineClip> videoMatches,
    Map<int, List<TimelineClip>> audioMatches,
  ) async {
    // 如果视频只有1个匹配，且所有匹配音频也都只有1个匹配，直接返回无需弹窗
    bool needDialog = videoMatches.length > 1;
    for (final matches in audioMatches.values) {
      if (matches.length > 1) {
        needDialog = true;
        break;
      }
    }

    if (!needDialog) {
      final result = <int, TimelineClip>{};
      result[-1] = videoMatches.first;
      for (final entry in audioMatches.entries) {
        result[entry.key] = entry.value.first;
      }
      return result;
    }

    // 需要弹窗确认
    return showDialog<Map<int, TimelineClip>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _MultiMatchSelectionDialog(
          keyword: keyword,
          videoMatches: videoMatches,
          audioMatches: audioMatches,
          formatMs: _formatMs,
        );
      },
    );
  }

  void _handleClipMove(TimelineClip clip, int newStartMs) {
    if (_timelineProject == null) return;
    final startMs = newStartMs; // 允许片段起始时间为负数，以支持超出左边界的裁剪

    TimelineTrack? updateTrack(TimelineTrack? track) {
      if (track == null) return null;
      
      final index = track.clips.indexWhere((c) => c.id == clip.id);
      
      // If we are moving a clip in this track directly
      if (index != -1) {
        final newClips = List<TimelineClip>.from(track.clips);
        final oldClip = newClips[index];
        
        final deltaMs = startMs - oldClip.timelineStartMs;

        newClips[index] = TimelineClip(
          id: oldClip.id,
          filePath: oldClip.filePath,
          fileName: oldClip.fileName,
          timelineStartMs: startMs,
          durationMs: oldClip.durationMs,
          mediaIndex: oldClip.mediaIndex,
          text: oldClip.text,
        );
        
        // Also update linked subtitle track if exists
        TimelineTrack? newLinkedSub;
        if (track.linkedSubtitleTrack != null) {
          final subClips = track.linkedSubtitleTrack!.clips.map((c) {
            return TimelineClip(
              id: c.id,
              filePath: c.filePath,
              fileName: c.fileName,
              timelineStartMs: c.timelineStartMs + deltaMs,
              durationMs: c.durationMs,
              mediaIndex: c.mediaIndex,
              text: c.text,
            );
          }).toList();
          
          newLinkedSub = TimelineTrack(
            type: TrackType.subtitle,
            clips: subClips,
          );
        }
        
        return TimelineTrack(
          type: track.type, 
          clips: newClips,
          linkedSubtitleTrack: newLinkedSub ?? track.linkedSubtitleTrack,
        );
      }
      
      return null;
    }

    final newVideoTrack = updateTrack(_timelineProject!.videoTrack);
    // final newSubtitleTrack = updateTrack(_timelineProject!.subtitleTrack); // Legacy
    
    List<TimelineTrack> newAudioTracks = List.from(_timelineProject!.audioTracks);
    bool audioUpdated = false;
    for (int i = 0; i < newAudioTracks.length; i++) {
      final updated = updateTrack(newAudioTracks[i]);
      if (updated != null) {
        newAudioTracks[i] = updated;
        audioUpdated = true;
        break;
      }
    }

    if (newVideoTrack != null || audioUpdated) {
      setState(() {
        _timelineProject = TimelineProject(
          videoTrack: newVideoTrack ?? _timelineProject!.videoTrack,
          audioTracks: audioUpdated ? newAudioTracks : _timelineProject!.audioTracks,
          subtitleTrack: _timelineProject!.subtitleTrack,
          durationMs: _calculateDuration(
             newVideoTrack ?? _timelineProject!.videoTrack,
             audioUpdated ? newAudioTracks : _timelineProject!.audioTracks,
             _timelineProject!.subtitleTrack
          ),
        );
        _saveCurrentTimeline();
      });
    }
  }

  void _handleTrackMove(int deltaMs, int trackIndex) {
    if (_timelineProject == null || deltaMs == 0) return;

    TimelineTrack? shiftTrack(TimelineTrack? track) {
      if (track == null) return null;

      final newClips = track.clips.map((c) {
        int newStart = c.timelineStartMs + deltaMs;
        int newDuration = c.durationMs;
        // 允许片段起始时间为负数，以支持超出左边界的裁剪
        return c.copyWith(timelineStartMs: newStart, durationMs: newDuration);
      }).toList();

      TimelineTrack? newLinkedSub;
      if (track.linkedSubtitleTrack != null) {
        final subClips = track.linkedSubtitleTrack!.clips.map((c) {
          int newStart = c.timelineStartMs + deltaMs;
          int newDuration = c.durationMs;
          return c.copyWith(timelineStartMs: newStart, durationMs: newDuration);
        }).toList();
        newLinkedSub = TimelineTrack(
          type: TrackType.subtitle,
          clips: subClips,
        );
      }

      return TimelineTrack(
        type: track.type,
        clips: newClips,
        linkedSubtitleTrack: newLinkedSub ?? track.linkedSubtitleTrack,
      );
    }

    TimelineTrack? newVideoTrack = _timelineProject!.videoTrack;
    List<TimelineTrack> newAudioTracks = List.from(_timelineProject!.audioTracks);
    bool changed = false;

    if (trackIndex == -1) {
      // 移动视频轨
      final updated = shiftTrack(_timelineProject!.videoTrack);
      if (updated != null) {
        newVideoTrack = updated;
        changed = true;
      }
    } else if (trackIndex >= 0 && trackIndex < newAudioTracks.length) {
      // 移动指定音频轨
      final updated = shiftTrack(newAudioTracks[trackIndex]);
      if (updated != null) {
        newAudioTracks[trackIndex] = updated;
        changed = true;
      }
    }

    if (changed) {
      setState(() {
        _timelineProject = TimelineProject(
          videoTrack: newVideoTrack,
          audioTracks: newAudioTracks,
          subtitleTrack: _timelineProject!.subtitleTrack,
          durationMs: _calculateDuration(
            newVideoTrack,
            newAudioTracks,
            _timelineProject!.subtitleTrack,
          ),
        );
        _saveCurrentTimeline();
      });
    }
  }

  int _calculateDuration(TimelineTrack? v, List<TimelineTrack> aTracks, TimelineTrack? s) {
     int max = 0;
     final all = [v, ...aTracks, s];
     for (final t in all) {
       if (t != null && t.clips.isNotEmpty) {
         for (final c in t.clips) {
           if (c.timelineEndMs > max) max = c.timelineEndMs;
         }
       }
     }
     return max;
  }

  String? _getCurrentSubtitleText() {
    if (_timelineProject == null) return null;
    
    final texts = <String>[];

    // 1. 查找视频轨道字幕
    if (_timelineProject!.videoTrack != null && _timelineProject!.videoTrack!.linkedSubtitleTrack != null) {
      final videoFileName = _timelineProject!.videoTrack!.clips.isNotEmpty 
          ? _timelineProject!.videoTrack!.clips.first.fileName 
          : '视频';
          
      for (final clip in _timelineProject!.videoTrack!.linkedSubtitleTrack!.clips) {
        if (_currentGlobalMs >= clip.timelineStartMs && _currentGlobalMs < clip.timelineEndMs) {
          if (clip.text != null && clip.text!.isNotEmpty) {
            texts.add('$videoFileName: ${clip.text!}');
          }
          break; // 当前时间点通常只有一个有效字幕
        }
      }
    }

    // 2. 查找音频轨道字幕
    for (final audioTrack in _timelineProject!.audioTracks) {
      if (audioTrack.linkedSubtitleTrack != null) {
        final audioFileName = audioTrack.clips.isNotEmpty 
            ? audioTrack.clips.first.fileName 
            : '音频';
            
        for (final clip in audioTrack.linkedSubtitleTrack!.clips) {
          if (_currentGlobalMs >= clip.timelineStartMs && _currentGlobalMs < clip.timelineEndMs) {
            if (clip.text != null && clip.text!.isNotEmpty) {
              texts.add('$audioFileName: ${clip.text!}');
            }
            break;
          }
        }
      }
    }

    if (texts.isEmpty) return null;
    // 如果有多条匹配（如视频和音频都有字幕），换行显示
    return texts.join('\n');
  }

  String _formatMs(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final h = m ~/ 60;
    final sec = s % 60;
    final min = m % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  // 手动音视频合板逻辑
  Future<void> _handleManualSync() async {
    if (_selectedVideoSubtitleForSync == null || _selectedAudioSubtitleForSync == null || _selectedAudioSubtitleTrackIndexForSync == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在视频和音频字幕列表中各选择一条基准字幕')),
      );
      return;
    }

    if (_timelineProject == null) return;

    // 计算偏移量 = 视频字幕入点 - 音频字幕入点
    final offsetMs = _selectedVideoSubtitleForSync!.timelineStartMs - _selectedAudioSubtitleForSync!.timelineStartMs;

    if (offsetMs == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两行字幕的入点时间一致，无需对齐')),
      );
      return;
    }

    final trackIndex = _selectedAudioSubtitleTrackIndexForSync!;
    if (trackIndex < 0 || trackIndex >= _timelineProject!.audioTracks.length) return;

    final audioTrack = _timelineProject!.audioTracks[trackIndex];
    
    // 应用偏移量到整条音频轨道
    final updatedClips = <TimelineClip>[];
    for (final clip in audioTrack.clips) {
      int newStart = clip.timelineStartMs + offsetMs;
      int newDuration = clip.durationMs;
      if (newStart < 0) {
        newDuration += newStart; // newStart is negative, so duration decreases
        newStart = 0;
      }
      updatedClips.add(clip.copyWith(timelineStartMs: newStart, durationMs: newDuration));
    }

    // 同时应用到该轨道的音频字幕（如果有的话）
    TimelineTrack? updatedLinkedSubtitleTrack = audioTrack.linkedSubtitleTrack;
    if (updatedLinkedSubtitleTrack != null) {
      final updatedSubtitleClips = <TimelineClip>[];
      for (final clip in updatedLinkedSubtitleTrack.clips) {
        int newStart = clip.timelineStartMs + offsetMs;
        int newDuration = clip.durationMs;
        if (newStart < 0) {
          newDuration += newStart;
          newStart = 0;
        }
        updatedSubtitleClips.add(clip.copyWith(timelineStartMs: newStart, durationMs: newDuration));
      }
      updatedLinkedSubtitleTrack = updatedLinkedSubtitleTrack.copyWith(clips: updatedSubtitleClips);
    }

    final updatedAudioTrack = audioTrack.copyWith(
      clips: updatedClips,
      linkedSubtitleTrack: updatedLinkedSubtitleTrack,
    );

    final updatedAudioTracks = List<TimelineTrack>.from(_timelineProject!.audioTracks);
    updatedAudioTracks[trackIndex] = updatedAudioTrack;

    _timelineProject = _timelineProject!.copyWith(audioTracks: updatedAudioTracks);

    setState(() {
      // 触发 UI 刷新
      _selectedVideoSubtitleForSync = null;
      _selectedAudioSubtitleForSync = null;
      _selectedAudioSubtitleTrackIndexForSync = null;
    });

    // 保存状态
    _saveCurrentTimeline();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('音视频合板完成，已偏移音频轨道 $offsetMs 毫秒')),
    );
  }

  // ── 合板相关方法 ──────────────────────────────────────────────

  /// 判断是否可以执行智能合板
  /// 条件满足其一即可：
  /// 1. 视频和音频都有字幕（字幕匹配模式）
  /// 2. 视频和音频都有源时间码（时间码同步模式）
  bool _canAutoSync() {
    if (_timelineProject == null) return false;

    // 检查字幕匹配条件
    final hasVideoSub =
        _timelineProject!.videoTrack?.linkedSubtitleTrack?.clips.isNotEmpty == true;
    final hasAudioSub = _timelineProject!.audioTracks.any(
      (t) => t.linkedSubtitleTrack?.clips.isNotEmpty == true,
    );
    if (hasVideoSub && hasAudioSub) return true;

    // 检查时间码同步条件
    final tcs = _timelineProject!.sourceTimecodes;
    final hasVideoTC = _timelineProject!.videoTrack?.clips.any(
          (c) => tcs.containsKey(c.filePath),
        ) ?? false;
    final hasAudioTC = _timelineProject!.audioTracks.any(
      (t) => t.clips.any((c) => tcs.containsKey(c.filePath)),
    );
    return hasVideoTC && hasAudioTC;
  }

  // ── ASR 语音识别相关 ──────────────────────────────────────────

  /// 导入音/视频后自动提示是否识别字幕
  Future<void> _promptAsrIfAvailable() async {
    if (_timelineProject == null) return;
    if (!SherpaOnnxPathService.isAvailable) return;

    // 检查是否有没有字幕的轨道
    final hasUnrecognizedVideo = _timelineProject!.videoTrack?.clips.isNotEmpty == true &&
        (_timelineProject!.videoTrack?.linkedSubtitleTrack?.clips.isEmpty ?? true);
    final hasUnrecognizedAudio = _timelineProject!.audioTracks.any(
      (t) => t.clips.isNotEmpty && (t.linkedSubtitleTrack?.clips.isEmpty ?? true),
    );

    if (!hasUnrecognizedVideo && !hasUnrecognizedAudio) return;

    // 延迟弹出，避免与其他 SnackBar 冲突
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final shouldRecognize = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('检测到无字幕轨道'),
        content: const Text('是否使用语音识别自动生成字幕？\n'
            '识别可能需要较长时间，取决于音频时长。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('跳过'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始识别'),
          ),
        ],
      ),
    );

    if (shouldRecognize == true) {
      _recognizeSubtitles();
    }
  }

  /// 显示 ASR 识别对话框并执行识别
  Future<void> _recognizeSubtitles() async {
    if (_timelineProject == null) return;

    // 选择要识别的轨道
    final tracks = <String, dynamic>{};
    if (_timelineProject!.videoTrack?.clips.isNotEmpty == true) {
      tracks['视频轨道'] = _timelineProject!.videoTrack;
    }
    for (int i = 0; i < _timelineProject!.audioTracks.length; i++) {
      tracks['音频轨道 ${i + 1}'] = _timelineProject!.audioTracks[i];
    }

    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可识别的轨道')),
      );
      return;
    }

    // 选择轨道
    final config = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _AsrConfigDialog(
        tracks: tracks.keys.toList(),
      ),
    );

    if (config == null) return;

    final trackName = config['track']!;
    final language = config['language'] ?? 'chinese';

    // 获取目标轨道的文件列表
    final targetTrack = tracks[trackName] as TimelineTrack?;
    if (targetTrack == null || targetTrack.clips.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final allClips = <TimelineClip>[];
      int processedCount = 0;
      final totalFiles = targetTrack.clips.length;
      final sherpaService = SherpaOnnxAsrService();

      for (final clip in targetTrack.clips) {
        // 显示进度
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '识别中 (${processedCount + 1}/$totalFiles): ${clip.fileName}',
              ),
              duration: const Duration(seconds: 30),
            ),
          );
        }

        try {
          final result = await sherpaService.recognize(
            filePath: clip.filePath,
            modelVariant: 'sense-voice-small',
            language: language == 'chinese' ? 'zh' : language,
            timelineStartMs: clip.timelineStartMs,
          );
          allClips.addAll(result.clips);
        } catch (e) {
          print('[ASR] ${clip.fileName} 识别失败: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${clip.fileName} 识别失败: $e'),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
        processedCount++;
      }

      if (allClips.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未识别到任何字幕')),
          );
        }
        return;
      }

      // 将识别的字幕绑定到目标轨道
      final subtitleTrack = TimelineTrack(
        type: TrackType.subtitle,
        clips: allClips,
      );

      setState(() {
        if (trackName == '视频轨道') {
          _timelineProject = TimelineProject(
            videoTrack: _timelineProject!.videoTrack?.copyWith(
              linkedSubtitleTrack: subtitleTrack,
            ),
            audioTracks: _timelineProject!.audioTracks,
            subtitleTrack: _timelineProject!.subtitleTrack,
            durationMs: _timelineProject!.durationMs,
            sourceTimecodes: _timelineProject!.sourceTimecodes,
          );
        } else {
          final trackIndex = int.tryParse(
                RegExp(r'(\d+)').firstMatch(trackName)?.group(1) ?? '1',
              ) ?? 1;
          final audioIndex = trackIndex - 1;
          final newAudioTracks = List<TimelineTrack>.from(_timelineProject!.audioTracks);
          if (audioIndex < newAudioTracks.length) {
            newAudioTracks[audioIndex] = newAudioTracks[audioIndex].copyWith(
              linkedSubtitleTrack: subtitleTrack,
            );
          }
          _timelineProject = TimelineProject(
            videoTrack: _timelineProject!.videoTrack,
            audioTracks: newAudioTracks,
            subtitleTrack: _timelineProject!.subtitleTrack,
            durationMs: _timelineProject!.durationMs,
            sourceTimecodes: _timelineProject!.sourceTimecodes,
          );
        }
        _saveCurrentTimeline();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('识别完成：${allClips.length} 条字幕')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('识别失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 批量识别所有轨道的字幕
  Future<void> _batchRecognizeAll({
    String language = 'chinese',
  }) async {
    if (_timelineProject == null) return;

    // 检查引擎可用性
    if (!SherpaOnnxPathService.isAvailable ||
        !SherpaOnnxPathService.isSenseVoiceAvailable('sense-voice-small')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到 SenseVoice ASR 引擎，请检查 sherpa-onnx 目录')),
      );
      return;
    }

    // 收集所有需要识别的轨道
    final tasks = <({String name, TimelineTrack track, bool isVideo})>[];
    if (_timelineProject!.videoTrack?.clips.isNotEmpty == true &&
        _timelineProject!.videoTrack?.linkedSubtitleTrack?.clips.isEmpty != false) {
      tasks.add((
        name: '视频轨道',
        track: _timelineProject!.videoTrack!,
        isVideo: true,
      ));
    }
    for (int i = 0; i < _timelineProject!.audioTracks.length; i++) {
      final track = _timelineProject!.audioTracks[i];
      if (track.clips.isNotEmpty &&
          track.linkedSubtitleTrack?.clips.isEmpty != false) {
        tasks.add((
          name: '音频轨道 ${i + 1}',
          track: track,
          isVideo: false,
        ));
      }
    }

    if (tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所有轨道已有字幕，无需识别')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final sherpaService = SherpaOnnxAsrService();
      int totalTasks = tasks.fold(0, (sum, t) => sum + t.track.clips.length);
      int processed = 0;

      for (final task in tasks) {
        final allClips = <TimelineClip>[];
        for (final clip in task.track.clips) {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '批量识别 $processed/$totalTasks: ${clip.fileName}',
                ),
                duration: const Duration(seconds: 30),
              ),
            );
          }

          try {
            final result = await sherpaService.recognize(
              filePath: clip.filePath,
              modelVariant: 'sense-voice-small',
              language: language == 'chinese' ? 'zh' : language,
              timelineStartMs: clip.timelineStartMs,
            );
            allClips.addAll(result.clips);
          } catch (e) {
            print('[ASR] 批量识别 ${clip.fileName} 失败: $e');
          }
          processed++;
        }

        if (allClips.isEmpty) continue;

        final subtitleTrack = TimelineTrack(
          type: TrackType.subtitle,
          clips: allClips,
        );

        if (mounted) {
          setState(() {
            if (task.isVideo) {
              _timelineProject = TimelineProject(
                videoTrack: _timelineProject!.videoTrack?.copyWith(
                  linkedSubtitleTrack: subtitleTrack,
                ),
                audioTracks: _timelineProject!.audioTracks,
                subtitleTrack: _timelineProject!.subtitleTrack,
                durationMs: _timelineProject!.durationMs,
                sourceTimecodes: _timelineProject!.sourceTimecodes,
              );
            } else {
              final audioTrackIndex = _timelineProject!.audioTracks.indexOf(task.track);
              if (audioTrackIndex >= 0) {
                final newAudioTracks = List<TimelineTrack>.from(_timelineProject!.audioTracks);
                newAudioTracks[audioTrackIndex] = newAudioTracks[audioTrackIndex].copyWith(
                  linkedSubtitleTrack: subtitleTrack,
                );
                _timelineProject = TimelineProject(
                  videoTrack: _timelineProject!.videoTrack,
                  audioTracks: newAudioTracks,
                  subtitleTrack: _timelineProject!.subtitleTrack,
                  durationMs: _timelineProject!.durationMs,
                  sourceTimecodes: _timelineProject!.sourceTimecodes,
                );
              }
            }
            _saveCurrentTimeline();
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量识别完成：处理了 $totalTasks 个文件')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量识别失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 执行多点字幕锚点智能合板
  Future<void> _performMultiPointSync() async {
    if (_timelineProject == null) return;
    setState(() => _isLoading = true);

    try {
      final service = MultiPointSyncService();

      // 判断是否有音视频时间码，决定同步策略
      final videoTCs = _timelineProject!.sourceTimecodes;
      final hasVideoTC = _timelineProject!.videoTrack?.clips.any(
            (c) => videoTCs.containsKey(c.filePath),
          ) ?? false;
      final hasAudioTC = _timelineProject!.audioTracks.any(
        (t) => t.clips.any((c) => videoTCs.containsKey(c.filePath)),
      );
      final useTimecode = hasVideoTC && hasAudioTC;

      final result = await service.performSync(
        originalProject: _timelineProject!,
      );

      final anchors = result.anchorPoints;
      final strategyDesc = useTimecode
          ? '时间码同步'
          : '字幕匹配';
      final modeDesc = result.isSegmented
          ? '$strategyDesc · 分段裁切为 ${result.segmentCount} 段'
          : '$strategyDesc · 全局偏移';

      // 显示结果摘要
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('智能合板结果'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('策略：$modeDesc'),
                Text('匹配到 ${anchors.length} 个锚点'),
                const SizedBox(height: 12),
                ...anchors.map((a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          (a.videoSubtitle.text ?? '').length > 20
                              ? '"${a.videoSubtitle.text?.substring(0, 20)}..."'
                              : '"${a.videoSubtitle.text}"',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        a.confidence >= 1.0
                            ? '精确'
                            : '${a.offsetMs >= 0 ? '+' : ''}${(a.offsetMs / 1000).toStringAsFixed(1)}s',
                        style: TextStyle(
                          fontSize: 12,
                          color: a.confidence >= 1.0
                              ? Colors.blue
                              : (a.offsetMs.abs() > 50 ? Colors.orange : Colors.green),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('应用'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() => _isLoading = false);
        return;
      }

      // 应用合板结果
      setState(() {
        _timelineProject = result.syncedProject;
        _saveCurrentTimeline();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '智能合板完成：${anchors.length}个锚点，$modeDesc',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('智能合板失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 执行全自动合板
  Future<void> _performAutoSync() async {
    if (_timelineProject == null) return;

    // 诊断：检查当前数据状态
    final diagLines = <String>[];
    diagLines.add('视频字幕：${_timelineProject!.videoTrack?.linkedSubtitleTrack?.clips.length ?? 0} 条');
    for (int i = 0; i < _timelineProject!.audioTracks.length; i++) {
      final t = _timelineProject!.audioTracks[i];
      final subCount = t.linkedSubtitleTrack?.clips.length ?? 0;
      diagLines.add('音频轨道${i + 1}：${t.clips.length}个片段，$subCount条字幕');
    }

    // 先显示诊断信息（帮助排查问题）
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('合板诊断：${diagLines.join(' | ')}'),
          duration: const Duration(seconds: 6),
        ),
      );
    }

    // 如果没有有字幕的音频轨道，直接提示
    final hasAudioSub = _timelineProject!.audioTracks
        .any((t) => t.linkedSubtitleTrack?.clips.isNotEmpty == true);
    if (!hasAudioSub) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('无法执行合板'),
            content: Text(
              '所有音频轨道都没有字幕。\n\n${diagLines.join('\n')}\n\n'
              '请确认：导入字幕时选择了正确的音频轨道（不是视频轨道）',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // 快照当前 _timelineProject，避免 builder 延迟执行时数据变化
    final projectSnapshot = _timelineProject!;

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AutoSyncDialog(project: projectSnapshot),
    );

    if (result == null || result is! AutoSyncResult) return;
    if (!mounted) return;

    // 创建合板项目标签页
    final appState = context.read<AppState>();
    final originalProject = appState.selectedProject;
    if (originalProject == null) return;

    await appState.createSyncedProject(
      originalProject: originalProject,
      syncedTimeline: result.syncedProject,
    );

    // 跳转到合板标签页（通过重新加载选中项目触发）
    if (mounted) {
      setState(() {
        _timelineProject = result.syncedProject;
        _loadedRoot = null; // 重置，让新项目正常加载
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '合板完成！已创建"${originalProject.displayName}-合板"标签页，'
            '找到 ${result.matches.length} 处匹配',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// 执行一键修剪
  Future<void> _performTrim() async {
    if (_timelineProject == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => TrimConfirmDialog(project: _timelineProject!),
    );

    if (confirmed != true || !mounted) return;

    final trimService = TrimService();
    final trimResult = trimService.trim(_timelineProject!);

    final newTimeline = _timelineProject!.copyWith(
      videoTrack: trimResult.videoTrack,
      audioTracks: trimResult.audioTracks,
      durationMs: trimResult.newDurationMs,
      compactInfo: CompactInfo(
        totalGapRemovedMs: trimResult.totalGapRemovedMs,
        clipOffsets: {},
      ),
    );

    setState(() {
      _timelineProject = newTimeline;
    });

    // 保存修剪后的状态
    final appState = context.read<AppState>();
    final project = appState.selectedProject;
    if (project != null) {
      await appState.updateTimelineProject(project.id, newTimeline);
    }
    // 重建播放列表
    final medias = <Media>[];
    for (final clip in trimResult.videoTrack.clips) {
      medias.add(Media(File(clip.filePath).uri.toString()));
    }
    if (medias.isNotEmpty) {
      await _player.open(Playlist(medias), play: false);
    }

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => TrimResultDialog(result: trimResult),
      );
    }
  }

  Future<void> _exportXml() async {
    if (_timelineProject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可导出的工程')),
      );
      return;
    }

    try {
      final appState = context.read<AppState>();
      final projectData = appState.selectedProject;
      final projectName = projectData?.displayName ?? 'Project';

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '导出 XML',
        fileName: '$projectName.xml',
        type: FileType.custom,
        allowedExtensions: ['xml'],
      );

      if (outputFile == null) {
        return; // 用户取消
      }

      setState(() => _isLoading = true);

      // Detect frame rate from the first video clip
      double fps = 30.0;
      if (_timelineProject!.videoTrack != null && _timelineProject!.videoTrack!.clips.isNotEmpty) {
        final firstClip = _timelineProject!.videoTrack!.clips.first;
        fps = await _scanService.getFrameRate(firstClip.filePath);
      }

      final exportService = ExportService();
      final xmlContent = exportService.generateFcpXml(_timelineProject!, projectName, fps);
      await exportService.saveXmlToFile(xmlContent, outputFile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('XML 导出成功 (FPS: ${fps.toStringAsFixed(2)}): $outputFile')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSubtitleSidebar() {
    if (_timelineProject == null) {
      return const Center(child: Text('无字幕'));
    }

    final videoSubtitles = <Map<String, dynamic>>[];
    final audioSubtitles = <Map<String, dynamic>>[];

    // 收集视频字幕
    if (_timelineProject!.videoTrack != null && _timelineProject!.videoTrack!.linkedSubtitleTrack != null) {
      final videoFileName = _timelineProject!.videoTrack!.clips.isNotEmpty 
          ? _timelineProject!.videoTrack!.clips.first.fileName 
          : '';
          
      for (final clip in _timelineProject!.videoTrack!.linkedSubtitleTrack!.clips) {
        if (clip.text != null && clip.text!.isNotEmpty) {
          if (_sidebarSearchKeyword.isEmpty || clip.text!.toLowerCase().contains(_sidebarSearchKeyword.toLowerCase())) {
            videoSubtitles.add({
              'source': '视频',
              'fileName': videoFileName,
              'clip': clip,
              'trackIndex': -1, // -1 代表视频轨
            });
          }
        }
      }
    }

    // 收集音频字幕
    for (int i = 0; i < _timelineProject!.audioTracks.length; i++) {
      final audioTrack = _timelineProject!.audioTracks[i];
      if (audioTrack.linkedSubtitleTrack != null) {
        final audioFileName = audioTrack.clips.isNotEmpty 
            ? audioTrack.clips.first.fileName 
            : '';
            
        for (final clip in audioTrack.linkedSubtitleTrack!.clips) {
          if (clip.text != null && clip.text!.isNotEmpty) {
            if (_sidebarSearchKeyword.isEmpty || clip.text!.toLowerCase().contains(_sidebarSearchKeyword.toLowerCase())) {
              audioSubtitles.add({
                'source': '音频 ${i + 1}',
                'fileName': audioFileName,
                'clip': clip,
                'trackIndex': i, // 音频轨索引
              });
            }
          }
        }
      }
    }

    // 按照起始时间排序
    videoSubtitles.sort((a, b) {
      final clipA = a['clip'] as TimelineClip;
      final clipB = b['clip'] as TimelineClip;
      return clipA.timelineStartMs.compareTo(clipB.timelineStartMs);
    });
    audioSubtitles.sort((a, b) {
      final clipA = a['clip'] as TimelineClip;
      final clipB = b['clip'] as TimelineClip;
      return clipA.timelineStartMs.compareTo(clipB.timelineStartMs);
    });

    Widget buildSubtitleList(List<Map<String, dynamic>> list, String title, Color badgeColor) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: list.isEmpty 
              ? const Center(child: Text('无', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final item = list[index];
                    final clip = item['clip'] as TimelineClip;
                    final source = item['source'] as String;
                    final trackIndex = item['trackIndex'] as int;
                    
                    final isCurrent = _currentGlobalMs >= clip.timelineStartMs && 
                                      _currentGlobalMs < clip.timelineEndMs;
                                      
                    final isSelected = clip == _selectedVideoSubtitleForSync || clip == _selectedAudioSubtitleForSync;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (trackIndex == -1) {
                            if (_selectedVideoSubtitleForSync == clip) {
                              _selectedVideoSubtitleForSync = null;
                            } else {
                              _selectedVideoSubtitleForSync = clip;
                            }
                          } else {
                            if (_selectedAudioSubtitleForSync == clip) {
                              _selectedAudioSubtitleForSync = null;
                              _selectedAudioSubtitleTrackIndexForSync = null;
                            } else {
                              _selectedAudioSubtitleForSync = clip;
                              _selectedAudioSubtitleTrackIndexForSync = trackIndex;
                            }
                          }
                        });
                        _handleSeek(clip.timelineStartMs);
                      },
                      child: Container(
                        color: isSelected 
                            ? badgeColor.withValues(alpha: 0.3) 
                            : (isCurrent ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : null),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          source,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: badgeColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          item['fileName'] ?? '',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${_formatMs(clip.timelineStartMs)} - ${_formatMs(clip.timelineEndMs)}',
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    clip.text ?? '',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isCurrent || isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4.0),
                                    child: Icon(Icons.check, color: Colors.green, size: 16),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // 搜索框及合板按钮
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    hintText: '搜索字幕...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _sidebarSearchKeyword = value.trim();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _handleManualSync,
                icon: const Icon(Icons.sync_alt, size: 18),
                label: const Text('音视频合板'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 双栏字幕列表
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: buildSubtitleList(videoSubtitles, '视频字幕', Colors.blue),
              ),
              VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
              Expanded(
                child: buildSubtitleList(audioSubtitles, '音频字幕', Colors.green),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = context.watch<AppState>().selectedProject;

    if (project == null) {
      return const Scaffold(
        body: Center(child: Text('请先从合板工作台选择一个视频目录')),
      );
    }

    // Trigger load if needed
    if (_loadedRoot != project.rootDir) {
      _loadProject(project.rootDir);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('合板操作 - ${project.displayName}'),
        actions: [
          // 识别字幕按钮（ASR语音识别）
          IconButton(
            icon: const Icon(Icons.mic),
            onPressed: _timelineProject != null ? _recognizeSubtitles : null,
            tooltip: '识别字幕（语音识别）',
          ),
          // 批量识别按钮
          IconButton(
            icon: const Icon(Icons.playlist_play),
            onPressed: _timelineProject != null &&
                    SherpaOnnxPathService.isAvailable
                ? _batchRecognizeAll
                : null,
            tooltip: '批量识别所有轨道',
          ),
          // 智能合板按钮（多点字幕锚点同步）
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            onPressed: _canAutoSync() ? _performMultiPointSync : null,
            tooltip: '智能合板（多点字幕对齐）',
          ),
          // 一键合板按钮（仅在有视频+音频字幕时激活）
          IconButton(
            icon: const Icon(Icons.movie_filter),
            onPressed: _canAutoSync() ? _performAutoSync : null,
            tooltip: '一键合板（全自动）',
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _autoSyncByText,
            tooltip: '一键对齐 (基于字幕)',
          ),
          IconButton(
            icon: const Icon(Icons.library_music),
            onPressed: _importAudioFolder,
            tooltip: '导入音频目录',
          ),
          IconButton(
            icon: const Icon(Icons.music_note),
            onPressed: _importAudio,
            tooltip: '导入音频文件',
          ),
          IconButton(
            icon: const Icon(Icons.subtitles),
            onPressed: _importSubtitle,
            tooltip: '导入字幕',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportXml,
            tooltip: '导出 XML (FCP7)',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadProject(project.rootDir),
            tooltip: '重新扫描',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Focus(
              autofocus: true,
              onKeyEvent: _handleKeyEvent,
              child: Column(
                children: [
                  // Top: Video Preview & Subtitle Sidebar
                  Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      // Video Preview Area
                      Expanded(
                        flex: 3,
                        child: Container(
                          color: Colors.black,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Stack(
                                children: [
                                  Video(controller: _controller),
                                  // Subtitle Overlay
                                  if (_getCurrentSubtitleText() != null)
                                    Positioned(
                                      bottom: 20,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.6),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            _getCurrentSubtitleText()!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Subtitle Sidebar
                      Container(
                        width: 600, // 调整宽度以适应双栏
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                        ),
                        child: _buildSubtitleSidebar(),
                      ),
                    ],
                  ),
                ),
                // Bottom: Timeline
                Expanded(
                  flex: 2,
                  child: _timelineProject == null
                              ? const Center(child: Text('没有可播放的视频'))
                              : TimelinePanel(
                                  project: _timelineProject!,
                                  currentPosMs: _currentGlobalMs,
                                  onSeek: _handleSeek,
                                  onClipMove: _handleClipMove,
                                  onTrackMove: _handleTrackMove,
                                  onTrim: _performTrim,
                                  controller: _timelineController,
                                ),
                        ),
              ],
            ),
          ),
    );
  }
}

/// ASR 识别配置对话框
class _AsrConfigDialog extends StatefulWidget {
  final List<String> tracks;

  const _AsrConfigDialog({
    required this.tracks,
  });

  @override
  State<_AsrConfigDialog> createState() => _AsrConfigDialogState();
}

class _AsrConfigDialogState extends State<_AsrConfigDialog> {
  late String _selectedTrack;
  String _selectedLanguage = 'chinese';

  @override
  void initState() {
    super.initState();
    _selectedTrack = widget.tracks.first;
  }

  @override
  Widget build(BuildContext context) {
    final hasEngine = SherpaOnnxPathService.isAvailable &&
        SherpaOnnxPathService.isSenseVoiceAvailable('sense-voice-small');

    return AlertDialog(
      title: const Text('识别字幕 (SenseVoice)'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 引擎信息
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.mic, size: 16, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SenseVoice: 高精度中文语音识别，自动检测语言',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            // 轨道选择
            const Text('目标轨道：', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...widget.tracks.map((t) => RadioListTile<String>(
                  title: Text(t),
                  value: t,
                  groupValue: _selectedTrack,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedTrack = v);
                  },
                )),
            const Divider(),
            // 语言选择
            const Text('语言：', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('中文'),
                  selected: _selectedLanguage == 'chinese',
                  onSelected: (_) => setState(() => _selectedLanguage = 'chinese'),
                ),
                ChoiceChip(
                  label: const Text('英文'),
                  selected: _selectedLanguage == 'en',
                  onSelected: (_) => setState(() => _selectedLanguage = 'en'),
                ),
                ChoiceChip(
                  label: const Text('自动'),
                  selected: _selectedLanguage == 'auto',
                  onSelected: (_) => setState(() => _selectedLanguage = 'auto'),
                ),
              ],
            ),
            if (!hasEngine)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '注意：未找到 SenseVoice 引擎，请检查 sherpa-onnx 目录',
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: hasEngine
              ? () => Navigator.pop(context, {
                    'track': _selectedTrack,
                    'language': _selectedLanguage,
                  })
              : null,
          child: const Text('开始识别'),
        ),
      ],
    );
  }
}
