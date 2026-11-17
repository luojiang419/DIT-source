# 09 - SenseVoice 添加 VAD 预处理

**时间**: 2026-04-15 20:30
**版本**: v3.0.1（功能增强，未编译新版本）

---

## 已完成内容

### 1. 问题诊断
- SenseVoice 在处理长音频（17分钟视频）时只产出 8 条混乱字幕
- 根本原因：sherpa-onnx-offline.exe 把整个音频当作一段语音识别，5分钟固定分片仍然太长
- SenseVoice 设计目标是短语音（几秒到几十秒），需要 VAD 预处理

### 2. 部署 VAD 工具文件
- ✅ 复制 `sherpa-onnx-vad-with-offline-asr.exe`（2.4MB）到 `sherpa-onnx/bin/`
- ✅ 下载 `silero_vad.onnx`（628KB）到 `sherpa-onnx/models/`
- ✅ 验证组合工具支持 `--sense-voice-model`、`--silero-vad-model` 等参数

### 3. 验证输出格式
- 确认组合工具输出格式：`start_sec -- end_sec: text`（每行一个语音片段）
- 30秒测试片段正确输出 4 条字幕
- 诊断信息输出到 stderr，识别结果输出到 stdout

### 4. 代码修改
- ✅ `sherpa_onnx_path_service.dart`: 新增 `vadWithAsrExePath`、`sileroVadModelPath`、`isVadWithAsrAvailable()`
- ✅ `sherpa_onnx_asr_service.dart`:
  - `recognize()` 新增 `useVad = true` 参数
  - 新增 `_processWithVad()` 方法（调用组合工具）
  - 新增 `_parseVadOutput()` 方法（解析纯文本输出）
  - 新增 `_splitTextIntoClips()` 方法（长文本按标点/字数拆分）
  - 原有逻辑提取为 `_processLegacy()` 作为后备方案
  - VAD 失败时自动回退到传统模式

### 5. 测试结果
- C0457.mp4（17分钟）VAD+ASR 测试成功
- **旧方案（无VAD）**: 8 条字幕，时间戳跨 8+ 分钟，文本混乱
- **新方案（VAD+ASR）**: **160 条字幕**，每条精确对应一个语音片段，时间戳合理

---

## 修改到的文件
- `video_subtitle_editor/lib/services/sherpa_onnx_path_service.dart`（第28行后新增3个getter）
- `video_subtitle_editor/lib/services/sherpa_onnx_asr_service.dart`（重构 recognize + 新增4个方法）
- `sherpa-onnx/bin/sherpa-onnx-vad-with-offline-asr.exe`（新文件，从发行包复制）
- `sherpa-onnx/models/silero_vad.onnx`（新文件，从 GitHub 下载）

---

## 待办清单
- [ ] 编译新版本（v3.1.0）到 dist 目录
- [ ] 在 Flutter 应用中实际运行测试
- [ ] 验证 clip_screen.dart 中 SenseVoice 调用是否自动使用 VAD 模式
- [ ] 确认编译后新版本目录包含 sherpa-onnx-vad-with-offline-asr.exe 和 silero_vad.onnx
- [ ] 确认编译脚本自动复制新文件

## 下一步
- 编译新版本并在应用内测试 SenseVoice VAD+ASR 功能
- 确保编译脚本（dist 复制逻辑）包含新的 VAD 相关文件
