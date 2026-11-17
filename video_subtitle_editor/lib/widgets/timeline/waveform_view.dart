import 'package:flutter/material.dart';
import '../../models/timeline_model.dart';
import '../../services/waveform_service.dart';

class WaveformView extends StatefulWidget {
  const WaveformView({
    super.key,
    required this.clip,
    required this.pixelsPerSecond,
    required this.color,
  });

  final TimelineClip clip;
  final double pixelsPerSecond;
  final Color color;

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  final WaveformService _service = WaveformService();
  Future<List<double>>? _future;
  
  // Sample rate used for extraction. 
  // 100 samples/sec means 1 sample covers 10ms.
  // At 50px/sec zoom, 1 sec = 50px. 100 samples fit in 50px. 2 samples per pixel.
  // At 200px/sec zoom, 1 sec = 200px. 100 samples fit in 200px. 0.5 samples per pixel.
  static const int _sampleRate = 100;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _service.extractWaveform(
      widget.clip.filePath,
      samplesPerSecond: _sampleRate,
    );
  }

  @override
  void didUpdateWidget(covariant WaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.filePath != widget.clip.filePath) {
      _load();
    }
  }

  @override
  void dispose() {
    _service.cancelAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<double>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
           return Container(
            color: Colors.black12,
            child: const Center(
              child: SizedBox(
                width: 16, 
                height: 16, 
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          // Empty or error
          return Container(color: Colors.black12);
        }

        final samples = snapshot.data!;
        return CustomPaint(
          painter: _WaveformPainter(
            samples: samples,
            color: widget.color,
            samplesPerSecond: _sampleRate,
            pixelsPerSecond: widget.pixelsPerSecond,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.samples,
    required this.color,
    required this.samplesPerSecond,
    required this.pixelsPerSecond,
  });

  final List<double> samples;
  final Color color;
  final int samplesPerSecond;
  final double pixelsPerSecond;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final centerY = size.height / 2;
    final maxAmp = size.height / 2;
    
    // Optimization: Draw only visible range if possible, but CustomPainter is usually clipped by widget size.
    // However, if we iterate millions of points, it's slow.
    // We should stride based on pixelsPerSecond.
    
    // Calculate pixels per sample:
    // 1 second = samplesPerSecond samples = pixelsPerSecond pixels
    // pixelsPerSample = pixelsPerSecond / samplesPerSecond
    final pixelsPerSample = pixelsPerSecond / samplesPerSecond;
    
    // If pixelsPerSample is very small (e.g. 0.01), we have 100 samples per pixel.
    // We should draw min/max for each pixel column.
    
    if (pixelsPerSample < 1.0) {
      // High density: multiple samples per pixel
      // We iterate by pixels
      for (double x = 0; x < size.width; x++) {
        // Find sample range for this pixel x
        // startSample = x / pixelsPerSample
        // endSample = (x + 1) / pixelsPerSample
        
        final startSample = (x / pixelsPerSample).floor();
        final endSample = ((x + 1) / pixelsPerSample).ceil();
        
        if (startSample >= samples.length) break;
        
        var maxVal = 0.0;
        // Optimization: don't loop if startSample is way out
        
        for (var i = startSample; i < endSample && i < samples.length; i++) {
          if (samples[i] > maxVal) maxVal = samples[i];
        }
        
        if (maxVal > 0) {
           final amp = maxVal * maxAmp;
           canvas.drawLine(Offset(x, centerY - amp), Offset(x, centerY + amp), paint);
        }
      }
    } else {
      // Low density: multiple pixels per sample (zoomed in extremely)
      // Just draw lines between samples or bars
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final x = i * pixelsPerSample;
        if (x > size.width) break;
        
        final amp = samples[i] * maxAmp;
        path.moveTo(x, centerY - amp);
        path.lineTo(x, centerY + amp);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.color != color;
  }
}
