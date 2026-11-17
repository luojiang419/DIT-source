import 'dart:io';
import 'dart:convert';
import 'package:excel/excel.dart';
import '../models/video_metadata.dart';

class MetadataExportService {
  static Future<String> exportToExcel(List<VideoMetadata> videos, String outputPath) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null) {
      excel.delete(defaultSheet);
    }
    final sheet = excel['视频元数据'];

    final headers = [
      '文件名', '时长', '分辨率', '编码', '帧率', '码率', '文件大小',
      '音频编码', '音频采样率', '音频声道', '音频码率',
      '色彩空间', '色彩原色', '色彩传输', '色彩范围', '像素格式',
      '相机品牌', '相机型号', '镜头型号', 'ISO', '白平衡',
      '场景', '镜次', '卷名',
      '相机序列号', '镜头序列号', '快门角度', 'Gamma', 'Look名称',
      '帧率(Sensor)', '制作', '导演', '摄影师',
      '文件路径',
    ];

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (var video in videos) {
      sheet.appendRow([
        TextCellValue(video.fileName),
        TextCellValue(video.duration ?? ''),
        TextCellValue(video.resolution ?? ''),
        TextCellValue(video.codec ?? ''),
        TextCellValue(video.frameRate ?? ''),
        TextCellValue(video.bitrate ?? ''),
        TextCellValue(video.fileSize ?? ''),
        TextCellValue(video.audioCodec ?? ''),
        TextCellValue(video.audioSampleRate ?? ''),
        TextCellValue(video.audioChannels ?? ''),
        TextCellValue(video.audioBitrate ?? ''),
        TextCellValue(video.colorSpace ?? ''),
        TextCellValue(video.colorPrimaries ?? ''),
        TextCellValue(video.colorTransfer ?? ''),
        TextCellValue(video.colorRange ?? ''),
        TextCellValue(video.pixelFormat ?? ''),
        TextCellValue(video.cameraMake ?? ''),
        TextCellValue(video.cameraModel ?? ''),
        TextCellValue(video.lensModel ?? ''),
        TextCellValue(video.iso ?? ''),
        TextCellValue(video.whiteBalance ?? ''),
        TextCellValue(video.scene ?? ''),
        TextCellValue(video.take ?? ''),
        TextCellValue(video.reelName ?? ''),
        TextCellValue(video.cameraSn ?? ''),
        TextCellValue(video.lensSn ?? ''),
        TextCellValue(video.shutterAngle ?? ''),
        TextCellValue(video.gamma ?? ''),
        TextCellValue(video.lookName ?? ''),
        TextCellValue(video.sensorFps ?? ''),
        TextCellValue(video.production ?? ''),
        TextCellValue(video.director ?? ''),
        TextCellValue(video.cinematographer ?? ''),
        TextCellValue(video.filePath),
      ]);
    }

    final fileBytes = excel.encode();
    if (fileBytes == null) {
      throw Exception('Excel 编码失败');
    }
    final file = File(outputPath);
    await file.writeAsBytes(fileBytes);
    return outputPath;
  }

  static Future<String> exportToJson(List<VideoMetadata> videos, String outputPath) async {
    final data = videos.map((v) => {
      'fileName': v.fileName,
      'duration': v.duration,
      'resolution': v.resolution,
      'codec': v.codec,
      'frameRate': v.frameRate,
      'bitrate': v.bitrate,
      'fileSize': v.fileSize,
      'audioCodec': v.audioCodec,
      'audioSampleRate': v.audioSampleRate,
      'audioChannels': v.audioChannels,
      'audioBitrate': v.audioBitrate,
      'colorSpace': v.colorSpace,
      'colorPrimaries': v.colorPrimaries,
      'colorTransfer': v.colorTransfer,
      'colorRange': v.colorRange,
      'pixelFormat': v.pixelFormat,
      'cameraMake': v.cameraMake,
      'cameraModel': v.cameraModel,
      'lensModel': v.lensModel,
      'iso': v.iso,
      'whiteBalance': v.whiteBalance,
      'scene': v.scene,
      'take': v.take,
      'reelName': v.reelName,
      'cameraSn': v.cameraSn,
      'lensSn': v.lensSn,
      'shutterAngle': v.shutterAngle,
      'gamma': v.gamma,
      'lookName': v.lookName,
      'sensorFps': v.sensorFps,
      'production': v.production,
      'director': v.director,
      'cinematographer': v.cinematographer,
      'filePath': v.filePath,
    }).toList();

    final file = File(outputPath);
    await file.writeAsString(JsonEncoder.withIndent('  ').convert(data));
    return outputPath;
  }
}
