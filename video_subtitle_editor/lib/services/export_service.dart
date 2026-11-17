import 'dart:io';
import 'package:xml/xml.dart';
import '../models/timeline_model.dart';

class ExportService {
  /// 生成 Final Cut Pro 7 XML (兼容 Premiere Pro 等大多数剪辑软件)
  String generateFcpXml(TimelineProject project, String projectName, double fps) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    
    // Determine timebase and ntsc
    int timebase = fps.round();
    bool ntsc = false;
    
    // Common NTSC frame rates
    if ((fps - 23.976).abs() < 0.01) {
      timebase = 24;
      ntsc = true;
    } else if ((fps - 29.97).abs() < 0.01) {
      timebase = 30;
      ntsc = true;
    } else if ((fps - 59.94).abs() < 0.01) {
      timebase = 60;
      ntsc = true;
    }

    builder.element('xmeml', attributes: {'version': '5'}, nest: () {
      builder.element('sequence', nest: () {
        builder.element('name', nest: projectName);
        builder.element('duration', nest: (project.durationMs * fps / 1000).round().toString());
        builder.element('rate', nest: () {
          builder.element('timebase', nest: timebase.toString());
          builder.element('ntsc', nest: ntsc ? 'TRUE' : 'FALSE');
        });
        
        builder.element('media', nest: () {
          // 视频轨道
          builder.element('video', nest: () {
            // 视频主轨道
            builder.element('track', nest: () {
              if (project.videoTrack != null) {
                _buildTrackClips(builder, project.videoTrack!.clips, fps);
              }
            });

            // 视频字幕轨道 (如果有) - 导出为 Text Generator
            if (project.videoTrack != null && project.videoTrack!.linkedSubtitleTrack != null) {
              builder.element('track', nest: () {
                _buildSubtitleClips(builder, project.videoTrack!.linkedSubtitleTrack!.clips, fps);
              });
            }
          });

          // 音频轨道
          builder.element('audio', nest: () {
            for (final track in project.audioTracks) {
              builder.element('track', nest: () {
                _buildTrackClips(builder, track.clips, fps);
              });
              // 移除音频字幕轨道的导出
            }
          });
        });
      });
    });

    return builder.buildDocument().toXmlString(pretty: true);
  }

  void _buildTrackClips(XmlBuilder builder, List<TimelineClip> clips, double fps) {
    for (final clip in clips) {
      builder.element('clipitem', nest: () {
        builder.element('name', nest: clip.fileName);

        final startFrame = (clip.timelineStartMs * fps / 1000).round();
        final durationFrame = (clip.durationMs * fps / 1000).round();
        final endFrame = startFrame + durationFrame;

        final sourceStartFrame = (clip.sourceStartMs * fps / 1000).round();
        final sourceEndFrame = sourceStartFrame + durationFrame;

        builder.element('start', nest: startFrame.toString());
        builder.element('end', nest: endFrame.toString());
        builder.element('in', nest: sourceStartFrame.toString());
        builder.element('out', nest: sourceEndFrame.toString());

        builder.element('file', nest: () {
          builder.element('name', nest: clip.fileName);
          builder.element('pathurl', nest: Uri.file(clip.filePath).toString());
        });
      });
    }
  }

  void _buildSubtitleClips(XmlBuilder builder, List<TimelineClip> clips, double fps) {
    for (final clip in clips) {
      if (clip.text == null || clip.text!.isEmpty) continue;

      builder.element('clipitem', nest: () {
        builder.element('name', nest: clip.text);
        
        final startFrame = (clip.timelineStartMs * fps / 1000).round();
        final durationFrame = (clip.durationMs * fps / 1000).round();
        final endFrame = startFrame + durationFrame;
        
        builder.element('start', nest: startFrame.toString());
        builder.element('end', nest: endFrame.toString());
        builder.element('in', nest: '0');
        builder.element('out', nest: durationFrame.toString());

        // 使用 FCP7 XML 的 Text generator 格式
        builder.element('generatoritem', nest: () {
          builder.element('name', nest: clip.text);
          builder.element('effect', nest: () {
            builder.element('name', nest: 'Text');
            builder.element('effectid', nest: 'Text');
            builder.element('effectcategory', nest: 'Text');
            builder.element('effecttype', nest: 'generator');
            builder.element('mediatype', nest: 'video');
            
            builder.element('parameter', nest: () {
              builder.element('name', nest: 'Text');
              builder.element('parameterid', nest: 'str');
              builder.element('value', nest: clip.text);
            });
          });
        });
      });
    }
  }

  Future<void> saveXmlToFile(String xmlContent, String filePath) async {
    final file = File(filePath);
    await file.writeAsString(xmlContent);
  }
}
