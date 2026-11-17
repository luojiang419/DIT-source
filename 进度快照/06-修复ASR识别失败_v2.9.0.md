# 进度快照：修复 ASR 识别失败（v2.9.0）

**日期**：2026-04-15
**版本**：v2.9.0

---

## 问题描述

ASR 语音识别功能无法识别任何字幕。使用测试文件验证：
- 视频：`G:\data\260224-元数据脚本测试\1_Video\220822shipin\C0457.mp4`
- 音频：`G:\data\260224-元数据脚本测试\2_Audio\220822yinpin\ZOOM0021_LR.mp3`

## 根本原因

**`--use-gpu` 参数无效**：当前版本的 whisper-cli（带 CUDA 支持）默认已启用 GPU，使用 `-ng` 禁用 GPU。代码中检测到 NVIDIA GPU 后添加了不存在的 `--use-gpu` 参数，导致 whisper-cli 直接打印帮助信息并退出（exitCode != 0），返回 0 条字幕。

## 修复内容

### 文件：`lib/services/speech_recognition_service.dart`

1. **移除 `--use-gpu` 参数**（关键修复）
   - GPU 在当前 whisper-cli 版本中默认启用
   - `hasNvidiaGpu()` 方法保留但不再影响 whisper-cli 参数

2. **移除 `--no-fallback` 参数**
   - 该参数对困难音频过于严格，可能导致部分视频 0 条识别
   - 改为依赖后处理幻觉过滤

3. **添加幻觉过滤** `_filterHallucination()`
   - 连续 3 条以上相同文本视为幻觉，自动移除

4. **改善错误处理**
   - FFmpeg WAV 提取失败：抛出异常，提示"文件可能没有音频轨道"
   - whisper-cli 失败：抛出异常并包含具体退出码和错误信息
   - 不再静默返回空列表，让用户看到具体错误原因

5. **添加诊断日志**
   - 每步打印 [ASR] 前缀日志，便于排查问题

### 文件：`lib/screens/clip_screen.dart`

1. **逐条 clip 错误处理**
   - `_recognizeSubtitles`：每条 clip 单独 try-catch，一条失败不影响其他
   - `_batchRecognizeAll`：同样添加逐条错误处理
   - 失败时显示具体文件名和错误信息

### 手动测试结果

| 测试项 | 结果 |
|--------|------|
| whisper-cli --help | 正常，GPU 自动检测到 RTX 4070 Ti SUPER |
| `--use-gpu` 参数 | 无效，导致直接退出 |
| 不带 `--use-gpu` 识别 | 正常，生成有效 SRT |
| `--no-fallback` | 减少尾部幻觉重复 |
| C0457.mp4 识别 | 生成约 400 条字幕（含尾部幻觉，过滤后约 350 条） |
| ZOOM0021_LR.mp3 识别 | 正常识别中文语音 |

---

## 编译状态

- **编译版本**：v2.9.0 → `dist/v2.9.0/`
- **ffmpeg**：已复制
- **whisper**：已复制（含全部 4 个模型）
- **备份**：`backup/backup_v2.8.0_*.tar.gz`

---

## 完整版本历史

| 版本 | 内容 | dist |
|------|------|------|
| v2.3.0 | 多点字幕锚点合板（基线） | ✅ |
| v2.4.0 | Phase 1: 时间码驱动合板 | ✅ |
| v2.5.0 | Phase 2: 时间码平铺 | ✅ |
| v2.6.0 | Phase 3: whisper.cpp ASR 集成 | ✅ |
| v2.7.0 | Phase 4: 工作流优化 | ✅ |
| v2.8.0 | （之前版本） | ✅ |
| v2.9.0 | **修复 ASR 识别失败** | ✅ |

---

## 待验证

- 用户使用 v2.9.0 版本实际测试 ASR 识别功能
- 验证幻觉过滤是否有效
- 验证识别质量是否满足需求
