import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/timeline_model.dart';
import '../../services/thumbnail_service.dart';

class FilmstripView extends StatefulWidget {
  const FilmstripView({
    super.key,
    required this.clip,
    required this.pixelsPerSecond,
  });

  final TimelineClip clip;
  final double pixelsPerSecond;

  @override
  State<FilmstripView> createState() => _FilmstripViewState();
}

class _FilmstripViewState extends State<FilmstripView> {
  late final ThumbnailService _service;
  Future<List<File>>? _future;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _service = ThumbnailService();
    _future = _load();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    // Note: This cancels ALL running thumbnail processes.
    // In a multi-track editor, we might want to track specific processes per widget.
    // For now, this is a safety net.
    _service.cancelAll();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FilmstripView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip != widget.clip) {
       _debounceTimer?.cancel();
       _future = _load();
       setState(() {});
    } else if (oldWidget.pixelsPerSecond != widget.pixelsPerSecond) {
      // Debounce zoom events
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _future = _load();
          });
        }
      });
    }
  }

  Future<List<File>> _load() async {
    final width = (widget.clip.durationMs / 1000.0) * widget.pixelsPerSecond;
    final targetTile = 120.0;
    // Calculate how many thumbnails we need based on current zoom level
    final count = width <= 0 ? 1 : (width / targetTile).ceil();
    
    // Fix FPS to 1.0 to avoid re-generating frames on zoom and stable cache key
    const double fps = 1.0;

    return _service.ensureThumbnails(
      widget.clip.filePath,
      fps: fps,
      height: 120,
      maxFrames: count.clamp(1, 1000), // Limit max frames to prevent OOM
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = (widget.clip.durationMs / 1000.0) * widget.pixelsPerSecond;
    if (width <= 0) {
      return const SizedBox.shrink();
    }
    
    return FutureBuilder<List<File>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Container(color: Colors.black26);
        }
        final frames = snapshot.data!;
        
        return LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = width / frames.length;
            
            // Use ListView.builder for virtualization if we have many frames
            return ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: frames.length,
              itemBuilder: (context, index) {
                return SizedBox(
                  width: tileWidth,
                  height: double.infinity,
                  child: Image.file(
                    frames[index], 
                    fit: BoxFit.cover,
                    cacheWidth: 200, // Optimize memory usage
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

