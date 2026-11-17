# 进度快照：SenseVoice 集成完成，准备开发 ASR 合板页面（v3.0.1）

**日期**：2026-04-15
**版本**：v3.0.1

---

## 已完成内容

### SenseVoice ASR 引擎集成

1. **新增文件**：
   - `lib/services/sherpa_onnx_path_service.dart` — sherpa-onnx 路径管理
   - `lib/services/sherpa_onnx_asr_service.dart` — SenseVoice ASR 服务（含 UTF-8 编码修复）

2. **修改文件**：
   - `lib/services/whisper_path_service.dart` — 添加 large-v3-turbo 模型
   - `lib/screens/clip_screen.dart` — ASR 配置对话框增加引擎选择（SenseVoice/Whisper）；识别方法支持双引擎
   - `lib/screens/settings_screen.dart` — 设置页增加 SenseVoice 引擎状态显示

3. **外部工具**：
   - `sherpa-onnx/bin/sherpa-onnx-offline.exe`（v1.12.38）
   - `sherpa-onnx/models/sense-voice-small/model.int8.onnx`（229MB）
   - `whisper/models/ggml-large-v3-turbo.bin`（1.5GB）

4. **关键修复**：
   - UTF-8 编码：`Process.run` 添加 `stdoutEncoding: utf8`（Windows 中文系统 GBK 解码导致 JSON 解析失败）
   - 布尔参数：`--sense-voice-use-itn=true`（不接受 `1/0`）

### 设计文档

- `ASR合板.md` — ASR 自动合板完整功能方案（已保存，待开发）

---

## 编译状态

- **编译版本**：v3.0.1 → `dist/v3.0.1/`
- **ffmpeg**：已复制
- **whisper**：已复制（含 turbo 模型）
- **sherpa-onnx**：已复制（含 SenseVoice 模型）
- **备份**：`backup/backup_v3.0.1_asr_sensevoice_*.tar.gz`

---

## 当前待验证

- [ ] 用户使用 v3.0.1 测试 SenseVoice 识别 C0457.mp4 是否正常出字幕

---

## 下一阶段：开发 ASR 合板页面

按 `ASR合板.md` 方案实施，核心任务：

### 新增文件（9个）

| 文件 | 说明 |
|------|------|
| `lib/screens/asr_project_list_screen.dart` | ASR 工程列表页（卡片网格） |
| `lib/screens/asr_project_detail_screen.dart` | ASR 工程操作页（4步骤引导） |
| `lib/services/asr_match_service.dart` | 字幕上下文匹配算法 |
| `lib/services/asr_project_service.dart` | ASR 工程 CRUD + 状态管理 |
| `lib/models/asr_project.dart` | AsrProject + MatchPair 数据模型 |
| `lib/widgets/asr/asr_progress_card.dart` | ASR 识别进度卡片 |
| `lib/widgets/asr/match_result_card.dart` | 匹配结果卡片 |
| `lib/widgets/asr/subtitle_compare_dialog.dart` | 字幕对比对话框 |
| `lib/widgets/asr/timeline_preview.dart` | 简化版时间线预览 |

### 需修改文件（4个）

| 文件 | 修改内容 |
|------|---------|
| `lib/screens/main_shell.dart` | NavigationRail 从 4 项改为 5 项 |
| `lib/services/database_service.dart` | 新增 asr_projects 表 |
| `lib/services/speech_recognition_service.dart` | 添加批量识别接口（可选） |
| `lib/state/app_state.dart` | 添加 ASR 工程相关状态 |

### 实施步骤

1. **数据层**：AsrProject 模型 + 数据库表 + AsrProjectService
2. **匹配算法**：AsrMatchService（字幕上下文滑动窗口匹配）
3. **UI-工程列表页**：卡片网格 + 新建工程
4. **UI-工程操作页**：Step 1 导入素材 → Step 2 ASR 识别 → Step 3 匹配确认 → Step 4 创建时间线
5. **导航集成**：MainShell 新增标签页

---

## 版本历史

| 版本 | 内容 | dist |
|------|------|------|
| v2.3.0 | 多点字幕锚点合板（基线） | ✅ |
| v2.4.0 | Phase 1: 时间码驱动合板 | ✅ |
| v2.5.0 | Phase 2: 时间码平铺 | ✅ |
| v2.6.0 | Phase 3: whisper.cpp ASR 集成 | ✅ |
| v2.7.0 | Phase 4: 工作流优化 | ✅ |
| v2.9.0 | 修复 ASR 识别失败 | ✅ |
| **v3.0.1** | **集成 SenseVoice ASR 引擎** | ✅ |
| v3.1.0 | ASR 自动合板页面（待开发） | ⏳ |
