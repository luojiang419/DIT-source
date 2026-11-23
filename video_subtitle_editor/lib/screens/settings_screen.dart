import 'dart:io';
import 'package:flutter/material.dart';
import '../services/ffmpeg_path_service.dart';
import '../services/sherpa_onnx_path_service.dart';
import '../services/database_service.dart';
import '../models/production_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _productionController = TextEditingController();
  final _cinematographerController = TextEditingController();
  final _operatorController = TextEditingController();
  final _directorController = TextEditingController();
  final _locationController = TextEditingController();
  final _companyController = TextEditingController();

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _productionController.dispose();
    _cinematographerController.dispose();
    _operatorController.dispose();
    _directorController.dispose();
    _locationController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settingsMap = await DatabaseService.getProductionSettings(null);
    if (settingsMap != null) {
      final settings = ProductionSettings.fromMap(settingsMap);
      _productionController.text = settings.production ?? '';
      _cinematographerController.text = settings.cinematographer ?? '';
      _operatorController.text = settings.operator ?? '';
      _directorController.text = settings.director ?? '';
      _locationController.text = settings.location ?? '';
      _companyController.text = settings.company ?? '';
    }
    setState(() => _loaded = true);
  }

  Future<void> _saveSettings() async {
    final settingsMap = await DatabaseService.getProductionSettings(null);
    final data = {
      'project_id': null,
      'production': _productionController.text.isEmpty ? null : _productionController.text,
      'cinematographer': _cinematographerController.text.isEmpty ? null : _cinematographerController.text,
      'operator': _operatorController.text.isEmpty ? null : _operatorController.text,
      'director': _directorController.text.isEmpty ? null : _directorController.text,
      'location': _locationController.text.isEmpty ? null : _locationController.text,
      'company': _companyController.text.isEmpty ? null : _companyController.text,
    };
    if (settingsMap != null && settingsMap['id'] != null) {
      data['id'] = settingsMap['id'];
    }
    await DatabaseService.saveProductionSettings(data);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // FFmpeg 路径信息
                      _buildSection('FFmpeg 配置', [
                        _buildInfoRow('FFmpeg 路径', FfmpegPathService.ffmpegPath),
                        const SizedBox(height: 4),
                        _buildInfoRow('FFprobe 路径', FfmpegPathService.ffprobePath),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: 16,
                                color: File(FfmpegPathService.ffmpegPath).existsSync()
                                    ? Colors.green
                                    : Colors.red),
                            const SizedBox(width: 8),
                            Text(File(FfmpegPathService.ffmpegPath).existsSync()
                                ? 'FFmpeg 已就绪'
                                : 'FFmpeg 未找到，请将 ffmpeg 放到 exe 同级目录的 ffmpeg/bin/ 下'),
                          ],
                        ),
                      ]),

                      const SizedBox(height: 32),

                      // SenseVoice ASR 引擎
                      _buildSection('ASR 语音识别 (SenseVoice)', [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            SherpaOnnxPathService.isAvailable
                                ? Icons.check_circle
                                : Icons.error_outline,
                            color: SherpaOnnxPathService.isAvailable
                                ? Colors.green
                                : Colors.grey,
                          ),
                          title: Text(SherpaOnnxPathService.isAvailable
                              ? 'sherpa-onnx 已就绪'
                              : 'sherpa-onnx 未找到'),
                          subtitle: Text(
                            SherpaOnnxPathService.isAvailable
                                ? '路径: ${SherpaOnnxPathService.offlineExePath}'
                                : '请将 sherpa-onnx 放到应用目录下',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        if (SherpaOnnxPathService.isAvailable) ...[
                          const Divider(),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text('已安装的模型：',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          ...SherpaOnnxPathService.listAvailableModels().map((m) =>
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.model_training, size: 20),
                              title: Text(m.displayLabel),
                              subtitle: Text('大小: ${m.sizeText}', style: const TextStyle(fontSize: 11)),
                              trailing: Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                            ),
                          ),
                          if (SherpaOnnxPathService.listAvailableModels().isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('暂无模型，请下载 SenseVoice 模型到 sherpa-onnx/models/ 目录',
                                  style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ),
                        ],
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.blue),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'SenseVoice: 高精度中文语音识别引擎，自动检测语言',
                                  style: TextStyle(fontSize: 11, color: Colors.blue),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),

                      const SizedBox(height: 32),

                      // 职员名单
                      _buildSection('职员名单（PDF报表）', [
                        _buildTextField('制片', _productionController),
                        const SizedBox(height: 12),
                        _buildTextField('摄影师', _cinematographerController),
                        const SizedBox(height: 12),
                        _buildTextField('操作员', _operatorController),
                        const SizedBox(height: 12),
                        _buildTextField('导演', _directorController),
                        const SizedBox(height: 12),
                        _buildTextField('拍摄地点', _locationController),
                        const SizedBox(height: 12),
                        _buildTextField('制作公司', _companyController),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _saveSettings,
                          child: const Text('保存职员设置'),
                        ),
                      ]),

                      const SizedBox(height: 32),

                      // 版本信息
                      _buildSection('关于', [
                        _buildInfoRow('应用名称', '采访视频检索工具 + DIT工具箱'),
                        _buildInfoRow('版本', 'v3.0.0'),
                        _buildInfoRow('技术栈', 'Flutter + SQLite + FFmpeg + media_kit'),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Divider(),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
