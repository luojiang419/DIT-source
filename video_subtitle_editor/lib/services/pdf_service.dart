import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/video_metadata.dart';
import '../models/production_settings.dart';
import '../models/pdf_config.dart';

class PdfService {
  static Future<void> generateReport(
    List<VideoMetadata> videos,
    String outputPath, {
    ProductionSettings? productionSettings,
    PDFConfig? config,
  }) async {
    final pdfConfig = config ?? PDFConfig();
    final pdf = pw.Document();
    final now = DateTime.now();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final font = await _loadFont();

    if (videos.isEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: font),
          build: (context) => pw.Center(
            child: pw.Text('没有视频数据',
                style: pw.TextStyle(font: font, fontSize: 16)),
          ),
        ),
      );
      final file = File(outputPath);
      await file.writeAsBytes(await pdf.save());
      return;
    }

    const firstPageItems = 4;
    const normalPageItems = 8;
    for (var pageIndex = 0; pageIndex < videos.length;) {
      final isFirstPage = pageIndex == 0;
      final itemsPerPage = isFirstPage ? firstPageItems : normalPageItems;
      final pageVideos = videos.skip(pageIndex).take(itemsPerPage).toList();
      pageIndex += itemsPerPage;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.only(
            top: pdfConfig.marginTop,
            bottom: pdfConfig.marginBottom,
            left: pdfConfig.marginLeft,
            right: pdfConfig.marginRight,
          ),
          theme: pw.ThemeData.withFont(base: font),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (isFirstPage) ...[
                pw.Center(
                    child: pw.Text('视频元数据报表',
                        style: pw.TextStyle(
                            font: font,
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold))),
                pw.SizedBox(height: 8),
                pw.Center(
                    child: pw.Text(dateFormat.format(now),
                        style: pw.TextStyle(
                            font: font,
                            fontSize: 10,
                            color: PdfColors.grey700))),
                pw.SizedBox(height: 20),
                if (pdfConfig.referenceImagePath != null &&
                    File(pdfConfig.referenceImagePath!).existsSync()) ...[
                  pw.Center(
                    child: pw.Container(
                      width: 400,
                      height: 225,
                      decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey400)),
                      child: pw.Image(
                          pw.MemoryImage(
                              File(pdfConfig.referenceImagePath!)
                                  .readAsBytesSync()),
                          fit: pw.BoxFit.contain),
                    ),
                  ),
                  pw.SizedBox(height: 20),
                ],
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 12),
                _buildInfoRow('总视频数', '${videos.length} 个', font),
                pw.SizedBox(height: 8),
                _buildInfoRow('生成时间', dateFormat.format(now), font),
                pw.SizedBox(height: 12),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 8),
                pw.Text('职员名单',
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(
                              '制片', productionSettings?.production ?? '', font),
                          _buildInfoRow('摄影师',
                              productionSettings?.cinematographer ?? '', font),
                          _buildInfoRow(
                              '操作员', productionSettings?.operator ?? '', font),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 20),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(
                              '导演', productionSettings?.director ?? '', font),
                          _buildInfoRow('拍摄地点',
                              productionSettings?.location ?? '', font),
                          _buildInfoRow('制作公司',
                              productionSettings?.company ?? '', font),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 12),
              ],
              ...pageVideos
                  .map((video) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 8),
                        child: _buildVideoCard(video, font, pdfConfig),
                      ))
                  .toList(),
            ],
          ),
        ),
      );
    }

    final file = File(outputPath);
    await file.writeAsBytes(await pdf.save());
  }

  static pw.Widget _buildVideoCard(
      VideoMetadata video, pw.Font font, PDFConfig pdfConfig) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        color: PdfColors.white,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (video.thumbnailPath != null &&
              File(video.thumbnailPath!).existsSync())
            pw.Container(
              width: 120,
              height: 68,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
              child: pw.ClipRRect(
                horizontalRadius: 2,
                verticalRadius: 2,
                child: pw.Image(
                    pw.MemoryImage(
                        File(video.thumbnailPath!).readAsBytesSync()),
                    fit: pw.BoxFit.cover),
              ),
            ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(video.fileName,
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip),
                pw.SizedBox(height: 2),
                pw.Text(video.filePath,
                    style: pw.TextStyle(
                        font: font, fontSize: 6, color: PdfColors.grey600),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip),
                pw.SizedBox(height: 4),
                pw.Row(
                  children: [
                    pw.Expanded(
                        flex: 1,
                        child: _buildInfoItem('时长', video.duration, font)),
                    pw.Expanded(
                        flex: 1,
                        child:
                            _buildInfoItem('分辨率', video.resolution, font)),
                    pw.Expanded(
                        flex: 1,
                        child: _buildInfoItem('帧率', video.frameRate, font)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  children: [
                    pw.Expanded(
                        flex: 1,
                        child: _buildInfoItem('编码', video.codec, font)),
                    pw.Expanded(
                        flex: 1,
                        child: _buildInfoItem('码率', video.bitrate, font)),
                    pw.Expanded(
                        flex: 1,
                        child: _buildInfoItem('大小', video.fileSize, font)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInfoItem(String label, String? value, pw.Font font) {
    if (value == null || value.isEmpty) return pw.SizedBox();
    return pw.Row(
      children: [
        pw.Text('$label：',
            style: pw.TextStyle(
                font: font, fontSize: 7, color: PdfColors.grey700)),
        pw.Expanded(
            child: pw.Text(value,
                style: pw.TextStyle(
                    font: font, fontSize: 7, color: PdfColors.grey900),
                maxLines: 1,
                overflow: pw.TextOverflow.clip)),
      ],
    );
  }

  static pw.Widget _buildInfoRow(String label, String value, pw.Font font) {
    return pw.Row(
      children: [
        pw.SizedBox(
            width: 100,
            child: pw.Text('$label:',
                style: pw.TextStyle(
                    font: font,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold))),
        pw.Text(value, style: pw.TextStyle(font: font, fontSize: 10)),
      ],
    );
  }

  static Future<pw.Font> _loadFont() async {
    final fontPath = 'C:\\Windows\\Fonts\\simhei.ttf';
    if (File(fontPath).existsSync()) {
      final bytes = await File(fontPath).readAsBytes();
      return pw.Font.ttf(bytes.buffer.asByteData());
    }
    throw Exception('无法加载黑体字体');
  }
}
