import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../models/video_metadata.dart';
import '../models/video_directory.dart';
import '../models/tree_node.dart';
import '../services/database_service.dart';
import '../services/dit_ffmpeg_service.dart';
import '../services/ffmpeg_path_service.dart';
import '../services/ale_service.dart';
import '../services/metadata_export_service.dart';
import '../services/tree_builder.dart';
import '../state/app_state.dart';
import '../widgets/dit/metadata_editor.dart';
import '../widgets/dit/progress_dialog.dart';
import '../widgets/dit/tree_view.dart';
import 'pdf_preview_screen.dart';

class DitDataScreen extends StatefulWidget {
  const DitDataScreen({super.key});

  @override
  State<DitDataScreen> createState() => _DitDataScreenState();
}

class _DitDataScreenState extends State<DitDataScreen> {
  List<VideoDirectory> _directories = [];
  VideoDirectory? _selectedDirectory;
  List<VideoMetadata> _videos = [];
  List<VideoMetadata> _filteredVideos = [];
  VideoMetadata? _selectedVideo;
  Set<int> _selectedVideoIds = {};

  String _searchText = '';
  String? _filterCodec;
  String? _filterResolution;
  List<String> _availableCodecs = [];
  List<String> _availableResolutions = [];

  bool _isScanning = false;
  int _scanProgress = 0;
  int _scanTotal = 0;
  String _scanCurrentFile = '';
  bool _showTreeView = false;

  @override
  void initState() {
    super.initState();
    _loadDirectories();
  }

  Future<void> _loadDirectories() async {
    final dirs = await DatabaseService.getVideoDirectories();
    if (!mounted) return;
    setState(() {
      _directories = dirs;
    });
    // 如果有选中的项目，自动选中匹配的目录
    final project = context.read<AppState>().selectedProject;
    if (project != null) {
      final matchDir = dirs.where((d) => project.rootDir.startsWith(d.path) || d.path.startsWith(project.rootDir)).firstOrNull;
      if (matchDir != null) {
        _selectDirectory(matchDir);
      }
    }
  }

  Future<void> _selectDirectory(VideoDirectory dir) async {
    setState(() {
      _selectedDirectory = dir;
      _selectedVideo = null;
      _selectedVideoIds.clear();
      _searchText = '';
      _filterCodec = null;
      _filterResolution = null;
    });
    await _loadVideos();
  }

  Future<void> _loadVideos() async {
    if (_selectedDirectory == null) return;
    final videos = await DatabaseService.getVideosByRootPath(_selectedDirectory!.path);
    if (!mounted) return;
    setState(() {
      _videos = videos;
      _applyFilters();
    });
    // 加载可用的筛选选项
    _availableCodecs = await DatabaseService.getDistinctCodecs(_selectedDirectory!.path);
    _availableResolutions = await DatabaseService.getDistinctResolutions(_selectedDirectory!.path);
    if (mounted) setState(() {});
  }

  void _applyFilters() {
    _filteredVideos = _videos.where((v) {
      if (_searchText.isNotEmpty && !v.fileName.toLowerCase().contains(_searchText.toLowerCase())) {
        return false;
      }
      if (_filterCodec != null && v.codec != _filterCodec) return false;
      if (_filterResolution != null && v.resolution != _filterResolution) return false;
      return true;
    }).toList();
  }

  Future<void> _addDirectory() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择视频目录');
    if (dir == null) return;

    final videoDir = VideoDirectory(
      path: dir,
      projectId: context.read<AppState>().selectedProject?.id,
      addedAt: DateTime.now(),
    );

    try {
      await DatabaseService.addVideoDirectory(videoDir);
      await _loadDirectories();
      if (_directories.isNotEmpty) {
        _selectDirectory(_directories.first);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('目录已存在或添加失败: $e')));
      }
    }
  }

  Future<void> _scanDirectory() async {
    if (_selectedDirectory == null) return;

    // 在方法开始时捕获引用，防止异步执行中 _selectedDirectory 变化
    final scanDir = _selectedDirectory!;
    final scanProjectId = context.read<AppState>().selectedProject?.id;

    // 预检查：FFprobe 是否可用
    final ffprobePath = FfmpegPathService.ffprobePath;
    if (!File(ffprobePath).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('FFprobe 未找到: $ffprobePath\n请在设置中配置 FFmpeg 路径'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    final dir = Directory(scanDir.path);
    if (!dir.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('目录不存在')));
      }
      return;
    }

    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.mxf'];
    final files = dir.listSync(recursive: true)
        .whereType<File>()
        .where((f) => videoExtensions.contains(path.extension(f.path).toLowerCase()))
        .toList();

    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到视频文件')));
      }
      return;
    }

    // 使用 ValueNotifier 驱动进度对话框更新
    final progressNotifier = ValueNotifier<int>(0);
    final currentFileNotifier = ValueNotifier<String>('');

    setState(() {
      _isScanning = true;
      _scanProgress = 0;
      _scanTotal = files.length;
      _scanCurrentFile = '';
    });

    // 显示进度对话框
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ValueListenableBuilder<int>(
          valueListenable: progressNotifier,
          builder: (ctx, progress, _) => ValueListenableBuilder<String>(
            valueListenable: currentFileNotifier,
            builder: (ctx, currentFile, _) => ProgressDialog(
              title: '正在扫描视频元数据',
              currentFile: currentFile,
              processed: progress,
              total: files.length,
            ),
          ),
        ),
      );
    }

    // 查找 ALE 文件
    Map<String, dynamic>? aleData;
    final alePath = AleService.findAleInDirectory(scanDir.path);
    if (alePath != null) {
      aleData = AleService.parseAleFile(alePath);
    }

    final imgDir = path.join(DatabaseService.appDir, 'data', 'img');
    int successCount = 0;
    int skipCount = 0;
    int failCount = 0;
    final errors = <String>[];

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileName = path.basename(file.path);
      final relativePath = path.relative(file.path, from: scanDir.path);

      progressNotifier.value = i + 1;
      currentFileNotifier.value = fileName;

      try {
        // 检查是否已存在
        final existing = await DatabaseService.getVideoMetadataByPath(file.path);
        if (existing != null) {
          skipCount++;
          continue;
        }

        // 提取元数据
        final metaMap = await DitFFmpegService.extractMetadata(file.path);

        // 提取缩略图
        String? thumbnailPath;
        try {
          thumbnailPath = await DitFFmpegService.extractThumbnail(file.path, imgDir);
        } catch (_) {}

        // 合并 ALE 数据
        Map<String, String>? aleClipData;
        if (aleData != null) {
          aleClipData = AleService.getAleMetadataForClip(aleData, fileName);
        }

        final metadata = VideoMetadata(
          rootPath: scanDir.path,
          projectId: scanProjectId,
          filePath: file.path,
          fileName: fileName,
          relativePath: relativePath,
          duration: metaMap['duration'],
          resolution: metaMap['resolution'],
          codec: metaMap['codec'],
          frameRate: metaMap['frameRate'],
          bitrate: metaMap['bitrate'],
          fileSize: metaMap['fileSize'],
          thumbnailPath: thumbnailPath,
          audioCodec: metaMap['audioCodec'],
          audioSampleRate: metaMap['audioSampleRate'],
          audioChannels: metaMap['audioChannels'],
          audioBitrate: metaMap['audioBitrate'],
          colorSpace: metaMap['colorSpace'],
          colorPrimaries: metaMap['colorPrimaries'],
          colorTransfer: metaMap['colorTransfer'],
          colorRange: metaMap['colorRange'],
          chromaLocation: metaMap['chromaLocation'],
          pixelFormat: metaMap['pixelFormat'],
          cameraMake: metaMap['cameraMake'],
          cameraModel: metaMap['cameraModel'],
          lensModel: metaMap['lensModel'],
          recordStartTime: metaMap['recordStartTime'],
          scene: aleClipData?['Scene'],
          take: aleClipData?['Take'],
          cameraSn: aleClipData?['Camera Serial Number'],
          lensSn: aleClipData?['Lens Serial Number'],
          shutterAngle: aleClipData?['Shutter Angle'],
          gamma: aleClipData?['Gamma'],
          lookName: aleClipData?['Look Name'],
          sensorFps: aleClipData?['Sensor FPS'],
          reelName: aleClipData?['Reel Name'],
          production: aleClipData?['Production'],
          director: aleClipData?['Director'],
          cinematographer: aleClipData?['Cinematographer'],
          operator: aleClipData?['Operator'],
          location: aleClipData?['Location'],
          company: aleClipData?['Company'],
          createdAt: DateTime.now(),
        );

        await DatabaseService.addVideoMetadata(metadata);
        successCount++;
      } catch (e) {
        failCount++;
        errors.add('$fileName: $e');
        print('扫描文件出错 $fileName: $e');
      }
    }

    progressNotifier.dispose();
    currentFileNotifier.dispose();

    setState(() => _isScanning = false);
    // 关闭进度对话框
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    await _loadVideos();
    if (mounted) {
      final msg = StringBuffer();
      msg.write('扫描完成：成功 $successCount 个');
      if (skipCount > 0) msg.write('，跳过 $skipCount 个（已存在）');
      if (failCount > 0) msg.write('，失败 $failCount 个');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.toString()),
          duration: Duration(seconds: failCount > 0 ? 5 : 3),
        ),
      );
      // 如果有失败，显示详情
      if (failCount > 0 && errors.isNotEmpty && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('扫描错误详情'),
            content: SizedBox(
              width: 500,
              height: 300,
              child: ListView(
                children: errors.map((e) => ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  title: Text(e, style: const TextStyle(fontSize: 12)),
                )).toList(),
              ),
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
    }
  }

  Future<void> _deleteDirectory(VideoDirectory dir) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定要删除目录 ${path.basename(dir.path)} 及其所有元数据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm != true) return;

    await DatabaseService.deleteVideoDirectory(dir.path);
    if (_selectedDirectory?.path == dir.path) {
      setState(() {
        _selectedDirectory = null;
        _videos = [];
        _filteredVideos = [];
        _selectedVideo = null;
      });
    }
    await _loadDirectories();
  }

  Future<void> _batchDelete() async {
    if (_selectedVideoIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 ${_selectedVideoIds.length} 个视频元数据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm != true) return;

    for (final id in _selectedVideoIds) {
      await DatabaseService.deleteVideoMetadata(id);
    }
    setState(() => _selectedVideoIds.clear());
    await _loadVideos();
  }

  Future<void> _exportExcel() async {
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出 Excel',
      fileName: 'video_metadata.xlsx',
      type: FileType.any,
    );
    if (outputPath == null) return;

    try {
      await MetadataExportService.exportToExcel(
        _selectedVideoIds.isNotEmpty ? _filteredVideos.where((v) => _selectedVideoIds.contains(v.id)).toList() : _filteredVideos,
        outputPath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出到 $outputPath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  Future<void> _exportJson() async {
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出 JSON',
      fileName: 'video_metadata.json',
      type: FileType.any,
    );
    if (outputPath == null) return;

    try {
      await MetadataExportService.exportToJson(
        _selectedVideoIds.isNotEmpty ? _filteredVideos.where((v) => _selectedVideoIds.contains(v.id)).toList() : _filteredVideos,
        outputPath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出到 $outputPath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  void _openPdfPreview() {
    if (_filteredVideos.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          videos: _selectedVideoIds.isNotEmpty
              ? _filteredVideos.where((v) => _selectedVideoIds.contains(v.id)).toList()
              : _filteredVideos,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 左栏：目录列表
          _buildDirectoryPanel(),
          const VerticalDivider(width: 1),
          // 中栏：视频列表
          Expanded(flex: 3, child: _buildVideoListPanel()),
          const VerticalDivider(width: 1),
          // 右栏：元数据详情
          Expanded(flex: 3, child: _buildMetadataDetailPanel()),
        ],
      ),
    );
  }

  Widget _buildDirectoryPanel() {
    return SizedBox(
      width: 260,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(child: Text('视频目录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '添加目录',
                  onPressed: _addDirectory,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _directories.isEmpty
                ? const Center(child: Text('暂无目录', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _directories.length,
                    itemBuilder: (ctx, i) {
                      final dir = _directories[i];
                      final isSelected = _selectedDirectory?.path == dir.path;
                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                        leading: const Icon(Icons.folder, color: Colors.amber),
                        title: Text(path.basename(dir.path),
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(dir.path,
                            style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _deleteDirectory(dir),
                        ),
                        onTap: () => _selectDirectory(dir),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoListPanel() {
    return Column(
      children: [
        // 工具栏
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (_selectedDirectory != null)
                FilledButton.icon(
                  onPressed: _scanDirectory,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('扫描目录'),
                ),
              IconButton(
                onPressed: _showTreeView ? null : _openPdfPreview,
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: '导出PDF报表',
              ),
              IconButton(
                onPressed: _exportExcel,
                icon: const Icon(Icons.table_chart),
                tooltip: '导出Excel',
              ),
              IconButton(
                onPressed: _exportJson,
                icon: const Icon(Icons.data_object),
                tooltip: '导出JSON',
              ),
              IconButton(
                onPressed: _selectedVideoIds.isEmpty ? null : _batchDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: '批量删除 (${_selectedVideoIds.length})',
              ),
              IconButton(
                onPressed: () => setState(() => _showTreeView = !_showTreeView),
                icon: Icon(_showTreeView ? Icons.list : Icons.account_tree),
                tooltip: _showTreeView ? '列表视图' : '树形视图',
              ),
            ],
          ),
        ),
        // 搜索和筛选
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '搜索文件名...',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _searchText = v;
                      _applyFilters();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    hintText: '编码',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  value: _filterCodec,
                  items: [null, ..._availableCodecs].map((c) => DropdownMenuItem(value: c, child: Text(c ?? '全部', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) {
                    setState(() {
                      _filterCodec = v;
                      _applyFilters();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    hintText: '分辨率',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  value: _filterResolution,
                  items: [null, ..._availableResolutions].map((r) => DropdownMenuItem(value: r, child: Text(r ?? '全部', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) {
                    setState(() {
                      _filterResolution = v;
                      _applyFilters();
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // 统计信息
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('共 ${_filteredVideos.length} 个视频' +
                (_selectedVideoIds.isNotEmpty ? ' (已选 ${_selectedVideoIds.length})' : '')),
          ),
        ),
        const Divider(height: 1),
        // 视频列表/树形视图
        Expanded(
          child: _selectedDirectory == null
              ? const Center(child: Text('请选择或添加一个视频目录'))
              : _showTreeView
                  ? _buildTreeContent()
                  : _buildVideoListContent(),
        ),
      ],
    );
  }

  Widget _buildVideoListContent() {
    if (_filteredVideos.isEmpty) {
      return const Center(child: Text('暂无视频数据，点击"扫描目录"开始'));
    }
    return ListView.builder(
      itemCount: _filteredVideos.length,
      itemBuilder: (ctx, i) {
        final video = _filteredVideos[i];
        final isSelected = _selectedVideo?.id == video.id;
        final isChecked = _selectedVideoIds.contains(video.id);
        return ListTile(
          selected: isSelected,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: isChecked,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedVideoIds.add(video.id!);
                    } else {
                      _selectedVideoIds.remove(video.id);
                    }
                  });
                },
              ),
              if (video.thumbnailPath != null && File(video.thumbnailPath!).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(File(video.thumbnailPath!), width: 64, height: 36, fit: BoxFit.cover),
                )
              else
                Container(
                  width: 64,
                  height: 36,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                  child: const Icon(Icons.videocam, size: 20),
                ),
            ],
          ),
          title: Text(video.fileName, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          subtitle: Text('${video.resolution ?? '-'} | ${video.duration ?? '-'}',
              style: const TextStyle(fontSize: 10)),
          onTap: () => setState(() => _selectedVideo = video),
        );
      },
    );
  }

  Widget _buildTreeContent() {
    if (_videos.isEmpty) {
      return const Center(child: Text('暂无视频数据'));
    }
    final tree = TreeBuilder.buildFromVideos(_videos, _selectedDirectory!.path);
    return TreeView(
      root: tree,
      onVideoSelected: (videoId) {
        final video = _videos.where((v) => v.id == videoId).firstOrNull;
        if (video != null) setState(() => _selectedVideo = video);
      },
    );
  }

  Widget _buildMetadataDetailPanel() {
    if (_selectedVideo == null) {
      return const Center(child: Text('选择一个视频查看元数据详情'));
    }
    final v = _selectedVideo!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 缩略图
          if (v.thumbnailPath != null && File(v.thumbnailPath!).existsSync())
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(v.thumbnailPath!), width: 320, height: 180, fit: BoxFit.cover),
              ),
            ),
          const SizedBox(height: 16),
          // 编辑按钮
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => MetadataEditor(
                    video: v,
                    onSaved: () => _loadVideos(),
                  ),
                );
              },
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('编辑'),
            ),
          ),
          const SizedBox(height: 12),
          _buildSection('基本信息', [
            _metaRow('文件名', v.fileName),
            _metaRow('时长', v.duration),
            _metaRow('分辨率', v.resolution),
            _metaRow('编码', v.codec),
            _metaRow('帧率', v.frameRate),
            _metaRow('码率', v.bitrate),
            _metaRow('文件大小', v.fileSize),
            _metaRow('文件路径', v.filePath),
          ]),
          _buildSection('音频', [
            _metaRow('音频编码', v.audioCodec),
            _metaRow('采样率', v.audioSampleRate),
            _metaRow('声道', v.audioChannels),
            _metaRow('音频码率', v.audioBitrate),
          ]),
          _buildSection('色彩', [
            _metaRow('色彩空间', v.colorSpace),
            _metaRow('色彩原色', v.colorPrimaries),
            _metaRow('色彩传输', v.colorTransfer),
            _metaRow('色彩范围', v.colorRange),
            _metaRow('像素格式', v.pixelFormat),
          ]),
          _buildSection('设备', [
            _metaRow('相机品牌', v.cameraMake),
            _metaRow('相机型号', v.cameraModel),
            _metaRow('镜头型号', v.lensModel),
            _metaRow('ISO', v.iso),
            _metaRow('录制时间', v.recordStartTime),
          ]),
          if (v.scene != null || v.take != null || v.reelName != null)
            _buildSection('场记', [
              _metaRow('场景', v.scene),
              _metaRow('镜次', v.take),
              _metaRow('卷名', v.reelName),
            ]),
          if (v.cameraSn != null || v.shutterAngle != null || v.gamma != null)
            _buildSection('ALE 拍摄参数', [
              _metaRow('相机序列号', v.cameraSn),
              _metaRow('镜头序列号', v.lensSn),
              _metaRow('快门角度', v.shutterAngle),
              _metaRow('Gamma', v.gamma),
              _metaRow('Look名称', v.lookName),
              _metaRow('Sensor FPS', v.sensorFps),
            ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> rows) {
    final nonEmptyRows = rows.where((w) => w is! SizedBox || true).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const Divider(),
        ...rows,
      ],
    );
  }

  Widget _metaRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12))),
          Expanded(child: Text(value ?? '-', style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
