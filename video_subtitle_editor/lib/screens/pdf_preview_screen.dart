import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/video_metadata.dart';
import '../models/production_settings.dart';
import '../models/pdf_config.dart';
import '../services/pdf_service.dart';
import '../services/database_service.dart';

class PdfPreviewScreen extends StatefulWidget {
  final List<VideoMetadata> videos;

  const PdfPreviewScreen({super.key, required this.videos});

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  PDFConfig _config = PDFConfig();
  bool _isExporting = false;
  String? _referenceImagePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF导出预览'),
      ),
      body: Row(
        children: [
          Expanded(flex: 2, child: _buildPreview()),
          SizedBox(width: 300, child: _buildControls()),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    const a4Ratio = 1 / 1.414;
    return Container(
      margin: const EdgeInsets.all(16),
      child: AspectRatio(
        aspectRatio: a4Ratio,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: SingleChildScrollView(
            child: Container(
              padding: EdgeInsets.only(
                top: _config.marginTop,
                bottom: _config.marginBottom,
                left: _config.marginLeft,
                right: _config.marginRight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.videos.take(8).map((video) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildVideoCard(video),
                )).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoCard(VideoMetadata video) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
        borderRadius: BorderRadius.circular(4),
        color: Colors.white,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (video.thumbnailPath != null && File(video.thumbnailPath!).existsSync())
            Container(
              width: _config.thumbnailWidth,
              height: _config.thumbnailWidth * 9 / 16,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300, width: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Image.file(File(video.thumbnailPath!), fit: BoxFit.cover),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(video.fileName,
                    style: TextStyle(fontSize: _config.fontSize + 2, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(flex: 1, child: _buildInfoItem('时长', video.duration)),
                  Expanded(flex: 1, child: _buildInfoItem('分辨率', video.resolution)),
                  Expanded(flex: 1, child: _buildInfoItem('帧率', video.frameRate)),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(flex: 1, child: _buildInfoItem('编码', video.codec)),
                  Expanded(flex: 1, child: _buildInfoItem('码率', video.bitrate)),
                  Expanded(flex: 1, child: _buildInfoItem('大小', video.fileSize)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox();
    return Row(
      children: [
        Text('$label：', style: TextStyle(fontSize: _config.fontSize, color: Colors.grey.shade700)),
        Expanded(child: Text(value, style: TextStyle(fontSize: _config.fontSize, color: Colors.grey.shade900), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('导出设置', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 24),
                  _buildSlider('缩略图宽度', _config.thumbnailWidth, 20, 800, (v) => _config = _config.copyWith(thumbnailWidth: v)),
                  _buildSlider('文字大小', _config.fontSize, 1, 40, (v) => _config = _config.copyWith(fontSize: v)),
                  _buildSlider('上边距', _config.marginTop, 3, 120, (v) => _config = _config.copyWith(marginTop: v)),
                  _buildSlider('下边距', _config.marginBottom, 3, 120, (v) => _config = _config.copyWith(marginBottom: v)),
                  _buildSlider('左边距', _config.marginLeft, 3, 120, (v) => _config = _config.copyWith(marginLeft: v)),
                  _buildSlider('右边距', _config.marginRight, 3, 120, (v) => _config = _config.copyWith(marginRight: v)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isExporting ? null : _exportPDF,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _isExporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('导出PDF报表'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          label: '${value.toInt()}px',
          onChanged: (v) => setState(() => onChanged(v)),
        ),
        Text('${value.toInt()}px', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _exportPDF() async {
    setState(() => _isExporting = true);

    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存PDF报表',
        fileName: 'metadata_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (outputPath == null) {
        setState(() => _isExporting = false);
        return;
      }

      // 从数据库读取职员设置
      final settingsMap = await DatabaseService.getProductionSettings(null);
      ProductionSettings? productionSettings;
      if (settingsMap != null) {
        productionSettings = ProductionSettings.fromMap(settingsMap);
      }

      await PdfService.generateReport(widget.videos, outputPath,
          productionSettings: productionSettings, config: _config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF导出成功')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF导出失败: $e')));
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }
}
