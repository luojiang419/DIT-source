# 进度快照：集成 SenseVoice ASR 引擎（v3.0.1）

**日期**：2026-04-15
**版本**：v3.0.1

---

## 本次修改内容

### 背景

用户反馈 Whisper large-v3 模型识别中文准确率很低。经调研发现 Whisper 是英语优先模型，中文 CER 约 8-10%。阿里达摩院的 SenseVoice 中文 CER 仅 2-3%，且速度更快。

### 第一阶段：Whisper large-v3-turbo 模型

- 下载 `ggml-large-v3-turbo.bin`（1.5GB）到 whisper/models/
- 零代码改动，速度从 75 秒降到 25 秒（3 倍提升）
- 中文质量无显著改善

### 第二阶段：集成 sherpa-onnx + SenseVoice

**新增文件（3个）**：

| 文件 | 说明 | 代码量 |
|------|------|--------|
| `lib/services/sherpa_onnx_path_service.dart` | sherpa-onnx 路径管理 | ~120 行 |
| `lib/services/sherpa_onnx_asr_service.dart` | SenseVoice ASR 服务 | ~300 行 |
| `sherpa-onnx/` 目录 | sherpa-onnx 工具 + SenseVoice 模型 | 外部依赖 |

**修改文件（3个）**：

| 文件 | 修改内容 |
|------|---------|
| `lib/services/whisper_path_service.dart` | 添加 large-v3-turbo 模型到推荐列表 |
| `lib/screens/clip_screen.dart` | ASR 配置对话框增加引擎选择（SenseVoice/Whisper）；识别方法支持双引擎 |
| `lib/screens/settings_screen.dart` | 设置页增加 SenseVoice 引擎状态显示 |

### 新增外部工具

```
sherpa-onnx/
├── bin/
│   ├── sherpa-onnx-offline.exe       ← ASR 识别引擎（~2.3MB）
│   ├── sherpa-onnx-vad.exe           ← 语音活动检测（第三阶段备用）
│   ├── sherpa-onnx-offline-punctuation.exe ← 标点恢复（第三阶段备用）
│   ├── onnxruntime.dll               ← ONNX 推理运行时
│   └── onnxruntime_providers_cuda.dll ← CUDA 支持（待解决兼容性）
└── models/
    └── sense-voice-small/
        ├── model.int8.onnx            ← SenseVoice INT8 模型（229MB）
        └── tokens.txt                 ← 词表文件
```

### 识别效果对比

同一测试文件（C0457.mp4，17 分钟中文采访）：

| 指标 | Whisper large-v3 | Whisper turbo | SenseVoice-Small (CPU) |
|------|-----------------|---------------|----------------------|
| 耗时 | 75 秒 | 25 秒 | 3 分 31 秒 |
| 字幕数 | 1356 条 | 952 条 | 需改进分片 |
| 中文质量 | "上咖?" "录音咖" | 类似 | "太爷爷...什么时候搬到这个院子住的呀？" |

**结论**：SenseVoice 文本准确率远超 Whisper，但速度较慢（CPU 模式）。CUDA GPU 加速待解决兼容性问题。

### 待解决问题

1. **CUDA GPU 加速**：sherpa-onnx CUDA 版与系统 CUDA 13.0 驱动存在兼容性问题，目前只能用 CPU 模式
2. **SenseVoice 输出格式**：输出为整段 JSON（含 token 级时间戳），需要更好的分段逻辑来生成 SRT 风格字幕
3. **长音频速度**：CPU 模式下 17 分钟音频需 3.5 分钟，可接受但不如 Whisper

---

## 编译状态

- **编译版本**：v3.0.1 → `dist/v3.0.1/`
- **ffmpeg**：已复制
- **whisper**：已复制（含 turbo 模型）
- **sherpa-onnx**：已复制（含 SenseVoice 模型）
- **备份**：`backup/backup_v3.0.1_asr_sensevoice_*.tar.gz`

---

## 完整版本历史

| 版本 | 内容 | dist |
|------|------|------|
| v2.3.0 | 多点字幕锚点合板（基线） | ✅ |
| v2.4.0 | Phase 1: 时间码驱动合板 | ✅ |
| v2.5.0 | Phase 2: 时间码平铺 | ✅ |
| v2.6.0 | Phase 3: whisper.cpp ASR 集成 | ✅ |
| v2.7.0 | Phase 4: 工作流优化 | ✅ |
| v2.9.0 | 修复 ASR 识别失败 | ✅ |
| **v3.0.1** | **集成 SenseVoice ASR 引擎** | ✅ |

---

## 下一步

- [ ] 解决 CUDA GPU 兼容性问题（加速 SenseVoice 3-5 倍）
- [ ] 优化 SenseVoice 输出的字幕分段质量
- [ ] 第三阶段：集成 Paraformer-large + VAD + 标点恢复
- [ ] 开始开发 ASR 自动合板功能（按 ASR合板.md 方案）
