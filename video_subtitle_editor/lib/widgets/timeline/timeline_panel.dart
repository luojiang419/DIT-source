import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/timeline_model.dart';
import 'filmstrip_view.dart';
import 'subtitle_view.dart';
import 'waveform_view.dart';

typedef OnClipMove = void Function(TimelineClip clip, int newStartMs);

class TimelinePanelController {
  _TimelinePanelState? _state;

  void attach(_TimelinePanelState state) {
    _state = state;
  }

  void detach() {
    _state = null;
  }

  void scrollToTime(int timeMs) {
    _state?.scrollToTime(timeMs);
  }
}

class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    super.key,
    required this.project,
    required this.currentPosMs,
    required this.onSeek,
    this.onClipMove,
    this.onTrackMove,
    this.onTrim,
    this.controller,
  });

  final TimelineProject project;
  final int currentPosMs;
  final ValueChanged<int> onSeek;
  final OnClipMove? onClipMove;
  final void Function(int deltaMs, int trackIndex)? onTrackMove;
  final VoidCallback? onTrim; // 一键修剪回调
  final TimelinePanelController? controller;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  double _pixelsPerSecond = 50.0; // Zoom level
  bool _isAltPressed = false;
  bool _isTracksLocked = false; // 新增锁定轨道状态

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    widget.controller?.attach(this);
  }

  @override
  void didUpdateWidget(TimelinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      widget.controller?.attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _scrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  void scrollToTime(int timeMs) {
    if (!_scrollController.hasClients) return;
    
    // Calculate target X
    final targetX = (timeMs / 1000.0) * _pixelsPerSecond;
    
    // Center it in viewport
    final viewportWidth = _scrollController.position.viewportDimension;
    final halfViewport = viewportWidth / 2;
    
    final offset = (targetX - halfViewport).clamp(0.0, _scrollController.position.maxScrollExtent);
    
    _scrollController.animateTo(
      offset, 
      duration: const Duration(milliseconds: 300), 
      curve: Curves.easeInOut,
    );
  }

  bool _handleKeyEvent(KeyEvent event) {
    final isAlt = event.logicalKey == LogicalKeyboardKey.altLeft || 
                  event.logicalKey == LogicalKeyboardKey.altRight;
    
    if (isAlt) {
      final newAltPressed = HardwareKeyboard.instance.logicalKeysPressed
          .any((key) => key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight);
      
      if (newAltPressed != _isAltPressed) {
        setState(() {
          _isAltPressed = newAltPressed;
        });
      }
    }
    return false; // Allow other handlers to process
  }

  void _handleScroll(PointerScrollEvent event, double viewportWidth) {
    if (_isAltPressed) {
      final delta = event.scrollDelta.dy;
      if (delta == 0) return;
      
      final scaleFactor = delta > 0 ? 0.9 : 1.1;
      
      // Calculate current time at mouse position
      final mouseX = event.localPosition.dx;
      // Real absolute X in the scroll view
      final absoluteX = _scrollController.offset + mouseX;
      // Time at that X
      final timeAtMouse = absoluteX / _pixelsPerSecond;

      setState(() {
        // Lower the max zoom limit to prevent Stack width overflow
        _pixelsPerSecond = (_pixelsPerSecond * scaleFactor).clamp(0.1, 200.0);
      });

      // Calculate new absolute X for the same time
      final newAbsoluteX = timeAtMouse * _pixelsPerSecond;
      // Keep mouse position same relative to viewport
      final newScrollOffset = (newAbsoluteX - mouseX).clamp(0.0, _scrollController.position.maxScrollExtent);
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(newScrollOffset);
        }
      });
    }
  }

  void _zoomToFit(double maxWidth) {
    if (widget.project.durationMs <= 0) return;
    
    final durationSec = widget.project.durationMs / 1000.0;
    // Leave a small margin
    final availableWidth = maxWidth - 20; 
    
    if (availableWidth > 0) {
      setState(() {
        _pixelsPerSecond = (availableWidth / durationSec).clamp(0.1, 200.0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalDurationSec = widget.project.durationMs / 1000.0;
    // Cap total width to prevent rendering overflow
    double totalWidth = totalDurationSec * _pixelsPerSecond;
    if (totalWidth > 100000) {
      totalWidth = 100000; 
    }
    final scrollWidth = totalWidth + 200.0; 

    return LayoutBuilder(
      builder: (context, constraints) {
        double timelineHeight = 30;
        if (widget.project.videoTrack != null) {
          timelineHeight += 60;
          if (widget.project.videoTrack!.linkedSubtitleTrack != null) {
            timelineHeight += 42;
          }
          timelineHeight += 10;
        }
        for (final track in widget.project.audioTracks) {
          if (track.linkedSubtitleTrack != null) {
            timelineHeight += 42;
          }
          timelineHeight += 60;
          timelineHeight += 10;
        }
        timelineHeight += 40;

        return Column(
          children: [
            // Toolbar (Zoom, etc.)
            Container(
              height: 40,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.zoom_out),
                    onPressed: () {
                      setState(() {
                        _pixelsPerSecond = (_pixelsPerSecond * 0.8).clamp(0.1, 200.0);
                      });
                    },
                    tooltip: '缩小',
                  ),
                  IconButton(
                    icon: const Icon(Icons.zoom_in),
                    onPressed: () {
                      setState(() {
                        _pixelsPerSecond = (_pixelsPerSecond * 1.25).clamp(0.1, 200.0);
                      });
                    },
                    tooltip: '放大',
                  ),
                  IconButton(
                    icon: const Icon(Icons.fit_screen),
                    onPressed: () => _zoomToFit(constraints.maxWidth),
                    tooltip: '适应窗口',
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      _isTracksLocked ? Icons.lock : Icons.lock_open,
                      color: _isTracksLocked ? Theme.of(context).colorScheme.primary : null,
                    ),
                    onPressed: () {
                      setState(() {
                        _isTracksLocked = !_isTracksLocked;
                      });
                    },
                    tooltip: _isTracksLocked ? '解锁轨道 (仅移动单条素材)' : '锁定轨道 (整体移动整条轨道)',
                  ),
                  if (widget.onTrim != null) ...[
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      onPressed: widget.onTrim,
                      icon: const Icon(Icons.content_cut, size: 16),
                      label: const Text('一键修剪'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '总时长: ${_formatDuration(widget.project.durationMs)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            // Timeline Area
            Expanded(
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _handleScroll(event, constraints.maxWidth);
                  }
                },
                onPointerMove: (event) {
                  // kMiddleMouseButton is 4
                  if (event.buttons == 4) {
                    if (_scrollController.hasClients) {
                      final newX = (_scrollController.offset - event.delta.dx)
                          .clamp(0.0, _scrollController.position.maxScrollExtent);
                      _scrollController.jumpTo(newX);
                    }
                    if (_verticalScrollController.hasClients) {
                      final newY = (_verticalScrollController.offset - event.delta.dy)
                          .clamp(0.0, _verticalScrollController.position.maxScrollExtent);
                      _verticalScrollController.jumpTo(newY);
                    }
                  }
                },
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  interactive: true,
                  thickness: 8.0,
                  radius: const Radius.circular(4),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: _isAltPressed
                        ? const NeverScrollableScrollPhysics() 
                        : const AlwaysScrollableScrollPhysics(),
                    child: SingleChildScrollView(
                      controller: _verticalScrollController,
                      scrollDirection: Axis.vertical,
                    child: GestureDetector(
                      onTapUp: (details) {
                        final dx = details.localPosition.dx;
                        final timeSec = dx / _pixelsPerSecond;
                        final timeMs = (timeSec * 1000).toInt();
                        widget.onSeek(timeMs.clamp(0, widget.project.durationMs));
                      },
                      onHorizontalDragUpdate: (details) {
                        final dx = details.localPosition.dx;
                        final timeSec = dx / _pixelsPerSecond;
                        final timeMs = (timeSec * 1000).toInt();
                        widget.onSeek(timeMs.clamp(0, widget.project.durationMs));
                      },
                      child: Container(
                        width: scrollWidth,
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                          minHeight: constraints.maxHeight,
                        ),
                        color: Theme.of(context).colorScheme.surfaceContainer, // 修改为浅色背景
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Dummy box to provide height
                            SizedBox(
                              height: timelineHeight,
                            ),
                            // Ruler
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 24,
                              child: CustomPaint(
                                painter: _RulerPainter(
                                  pixelsPerSecond: _pixelsPerSecond,
                                  totalDurationSec: totalDurationSec,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant, // 修改标尺颜色
                                ),
                              ),
                            ),
                            
                            // Tracks
                            // Video Track Group (Video + Linked Subtitle)
                            if (widget.project.videoTrack != null)
                              ...[
                                // Video Track
                                Positioned(
                                  top: 30,
                                  left: 0,
                                  right: 0,
                                  height: 60,
                                  child: _TrackView(
                                    track: widget.project.videoTrack!,
                                    pixelsPerSecond: _pixelsPerSecond,
                                    color: Colors.blue.withValues(alpha: 0.15), // 浅色背景视频轨
                                    label: 'Video 1',
                                    trackIndex: -1, // Video track index
                                    onClipMove: _isTracksLocked ? null : widget.onClipMove,
                                    onTrackMove: _isTracksLocked ? widget.onTrackMove : null,
                                  ),
                                ),
                                // Linked Subtitle (Below Video)
                                if (widget.project.videoTrack!.linkedSubtitleTrack != null)
                                  Positioned(
                                    top: 92, // 30 + 60 + 2
                                    left: 0,
                                    right: 0,
                                    height: 40,
                                    child: _TrackView(
                                      track: widget.project.videoTrack!.linkedSubtitleTrack!,
                                      pixelsPerSecond: _pixelsPerSecond,
                                      color: Colors.orange.withValues(alpha: 0.15), // 浅色背景字幕轨
                                      label: 'Video Sub',
                                      // Subtitles are read-only or move with parent
                                      onClipMove: null, 
                                    ),
                                  ),
                              ],
                            
                            // Audio Tracks Group (Linked Subtitle + Audio)
                            ...widget.project.audioTracks.asMap().entries.expand((entry) {
                              final index = entry.key;
                              final track = entry.value;
                              
                              double currentTop = 30;
                              if (widget.project.videoTrack != null) {
                                currentTop += 60;
                                if (widget.project.videoTrack!.linkedSubtitleTrack != null) {
                                  currentTop += 42;
                                }
                                currentTop += 10;
                              }
                              
                              // Add previous audio tracks height
                              for (int i = 0; i < index; i++) {
                                final prevTrack = widget.project.audioTracks[i];
                                currentTop += (prevTrack.linkedSubtitleTrack != null ? 42 : 0) + 60 + 10;
                              }

                              return [
                                // Linked Subtitle (Above Audio)
                                if (track.linkedSubtitleTrack != null)
                                  Positioned(
                                    top: currentTop,
                                    left: 0,
                                    right: 0,
                                    height: 40,
                                    child: _TrackView(
                                      track: track.linkedSubtitleTrack!,
                                      pixelsPerSecond: _pixelsPerSecond,
                                      color: Colors.orange.withValues(alpha: 0.15), // 浅色背景字幕轨
                                      label: 'Audio ${index + 1} Sub',
                                      onClipMove: null,
                                    ),
                                  ),
                                
                                // Audio Track
                                Positioned(
                                  top: currentTop + (track.linkedSubtitleTrack != null ? 42 : 0),
                                  left: 0,
                                  right: 0,
                                  height: 60,
                                  child: _TrackView(
                                    track: track,
                                    pixelsPerSecond: _pixelsPerSecond,
                                    color: Colors.green.withValues(alpha: 0.15), // 浅色背景音频轨
                                    label: 'Audio ${index + 1}',
                                    trackIndex: index, // Audio track index
                                    onClipMove: _isTracksLocked ? null : widget.onClipMove,
                                    onTrackMove: _isTracksLocked ? widget.onTrackMove : null,
                                  ),
                                ),
                              ];
                            }),

                            // Playhead
                            Positioned(
                              left: (widget.currentPosMs / 1000.0) * _pixelsPerSecond,
                              top: 0,
                              bottom: 0,
                              width: 2,
                              child: Container(color: Colors.red),
                            ),
                            // Playhead Cap
                            Positioned(
                              left: (widget.currentPosMs / 1000.0) * _pixelsPerSecond - 5,
                              top: 0,
                              width: 10,
                              height: 10,
                              child: CustomPaint(
                                painter: _PlayheadCapPainter(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ],
        );
      },
    );
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _TrackView extends StatelessWidget {
  const _TrackView({
    required this.track,
    required this.pixelsPerSecond,
    required this.color,
    required this.label,
    this.trackIndex = 0,
    this.onClipMove,
    this.onTrackMove,
  });

  final TimelineTrack track;
  final double pixelsPerSecond;
  final Color color;
  final String label;
  final int trackIndex;
  final OnClipMove? onClipMove;
  final void Function(int deltaMs, int trackIndex)? onTrackMove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Track Background
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3), // 浅色轨道背景
        ),
        // Clips
        ...track.clips.map((clip) {
          final left = (clip.timelineStartMs / 1000.0) * pixelsPerSecond;
          final width = (clip.durationMs / 1000.0) * pixelsPerSecond;
          return Positioned(
            left: left,
            width: width,
            top: 2,
            bottom: 2,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                final deltaMs = (details.delta.dx / pixelsPerSecond * 1000).toInt();
                if (onTrackMove != null) {
                  onTrackMove!(deltaMs, trackIndex);
                } else if (onClipMove != null) {
                  onClipMove!(clip, clip.timelineStartMs + deltaMs);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.black12, width: 1), // 调整边框颜色适应浅色
                ),
                clipBehavior: Clip.hardEdge,
                child: Stack(
                  children: [
                    // Content (Filmstrip / Waveform)
                    Positioned.fill(
                      child: _buildTrackContent(clip),
                    ),
                    
                    // Filename Overlay
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                          ),
                        ),
                        child: Text(
                          clip.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white, 
                            fontSize: 10,
                            shadows: [
                              Shadow(blurRadius: 2, color: Colors.black, offset: Offset(1, 1)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTrackContent(TimelineClip clip) {
    if (track.type == TrackType.video) {
      return FilmstripView(
        clip: clip,
        pixelsPerSecond: pixelsPerSecond,
      );
    } else if (track.type == TrackType.audio) {
      return WaveformView(
        clip: clip,
        pixelsPerSecond: pixelsPerSecond,
        color: Colors.black87, // 音频波形颜色在浅色背景下加深
      );
    } else if (track.type == TrackType.subtitle) {
      return SubtitleBlockView(
        clip: clip,
        pixelsPerSecond: pixelsPerSecond,
        color: color,
      );
    }
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Text(
        'No Preview',
        style: TextStyle(color: Colors.black38, fontSize: 8), // 浅色背景下的占位文字颜色
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.pixelsPerSecond,
    required this.totalDurationSec,
    required this.color,
  });

  final double pixelsPerSecond;
  final double totalDurationSec;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Determine interval based on zoom
    // We want ticks roughly every 50-100 pixels
    double intervalSec = 1.0;
    if (pixelsPerSecond < 20) {
      intervalSec = 10.0;
    } else if (pixelsPerSecond < 50) {
      intervalSec = 5.0;
    } else {
      intervalSec = 1.0;
    }

    for (double t = 0; t <= totalDurationSec; t += intervalSec) {
      final x = t * pixelsPerSecond;
      if (x > size.width) break;

      final isMajor = (t % (intervalSec * 5) == 0);
      final height = isMajor ? 12.0 : 6.0;

      canvas.drawLine(Offset(x, 0), Offset(x, height), paint);

      if (isMajor) {
        final duration = Duration(seconds: t.toInt());
        final label = '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
        textPainter.text = TextSpan(
          text: label,
          style: TextStyle(color: color, fontSize: 10),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 2, 0));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) {
    return oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.totalDurationSec != totalDurationSec;
  }
}

class _PlayheadCapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.red;
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
