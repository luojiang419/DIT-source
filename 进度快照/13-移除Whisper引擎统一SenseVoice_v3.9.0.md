# 进度快照 13 — 移除 Whisper 引擎，统一使用 SenseVoice

**日期**: 2026-04-17
**版本**: v3.9.0（待编译）

---

## 已完成内容

### 1. 删除的文件（3个核心文件 + 1个目录）
- `lib/services/whisper_path_service.dart` — Whisper 路径管理服务
- `lib/services/speech_recognition_service.dart` — whisper-cli.exe 封装服务
- `lib/services/model_download_service.dart` — Whisper 模型下载服务
- `whisper-20250625/` — OpenAI whisper Python 源码副本

### 2. 修改的文件（4个）

#### `clip_screen.dart`
- 移除了 whisper 相关 imports（speech_recognition_service、whisper_path_service、model_download_service）
- `_promptAsrIfAvailable`: 改用 `SherpaOnnxPathService.isAvailable` 检查
- `_recognizeSubtitles`: 移除引擎选择、模型下载逻辑，统一使用 SenseVoice
- `_batchRecognizeAll`: 移除 Whisper 回退逻辑，仅保留 SenseVoice
- `_AsrConfigDialog`: 简化为仅 SenseVoice，移除引擎选择和模型选择器
- 批量识别按钮: 改用 `SherpaOnnxPathService.isAvailable` 检查

#### `asr_project_detail_screen.dart`
- 移除了 whisper_path_service 和 speech_recognition_service imports
- 引擎检查: 统一检查 SenseVoice，移除 Whisper 分支
- 识别逻辑: 移除双引擎分支，统一使用 SherpaOnnxAsrService

#### `settings_screen.dart`
- 移除了 whisper_path_service 和 model_download_service imports
- 移除了 `_downloadModel` 方法
- 移除了 Whisper CLI 状态显示、模型列表、模型下载区块
- SenseVoice 区块标题改为 "ASR 语音识别 (SenseVoice)"
- 更新描述文本，移除与 Whisper 的比较

#### `sherpa_onnx_asr_service.dart`
- 移除类注释中的 Whisper 比较
- 移除幻觉过滤方法注释中的 Whisper 引用

### 3. 更新的配置文件
- `大型项目规划.md`: 移除编译时复制 whisper 目录的规则

### 4. 备份
- 备份文件: `backup/DIT-tools_v3.8.0_pre-whisper-removal_*.tar.gz`

---

## 当前状态
- 所有源码修改已完成
- lib 目录中已无任何 whisper 残留引用
- 待编译验证

## 待办清单
- [ ] 编译新版本到 `\dist`

## 下一步
- 编译 v3.9.0 到 dist 目录（不再复制 whisper 目录）
