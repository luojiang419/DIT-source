# 进度快照：Phase 2 时间码平铺完成

**日期**：2026-04-15
**版本**：v2.5.0

---

## 已完成内容

### Phase 1：时间码驱动合板（v2.4.0，已完成）

- MultiPointSyncService 增加时间码同步策略
- 音频导入时自动提取源时间码
- 智能合板支持时间码/字幕双策略

### Phase 2：时间码平铺（v2.5.0，本次完成）

#### 1. `lib/screens/clip_screen.dart` — 导入排列方式选择

- **新增导入对话框**：首次扫描视频目录时，若检测到源时间码，弹出选择对话框：
  - "按时间码平铺（推荐）"：按真实录制时间排列，停录间隔用空白填充
  - "紧凑排列"：所有视频首尾相接，无间隙（原有行为）

- **时间码平铺逻辑**（`_loadProject()` 内）：
  - 找到最早的时间码作为基准（timelineStartMs = 0）
  - 每个视频的时间轴位置 = 自己的时间码 - 最早时间码
  - 无时间码的文件排在最后（紧凑方式）
  - 无任何时间码数据时自动跳过对话框，直接紧凑排列

- **新增 `dart:math` import**（用于 `reduce(min)`）

#### 2. 时间轴缩放适配

- 现有的 `_zoomToFit()` 已支持 0.1~200.0 px/s 范围
- "适应窗口"按钮可自动适配大跨度时间线
- 无需额外修改

---

## 当前修改到的模块

| 文件 | 改动类型 |
|------|---------|
| `clip_screen.dart` | 修改 `_loadProject()` |

---

## 编译状态

- **编译版本**：v2.5.0 → `dist/v2.5.0/`
- **ffmpeg**：已复制
- **备份**：`backup/backup_v2.4.0_*.tar.gz`

---

## 下一步待办

### Phase 3：whisper.cpp 集成（ASR 语音识别）
- 下载 whisper-cli.exe 到 tools/whisper/
- 新建 `whisper_path_service.dart`（路径管理）
- 新建 `speech_recognition_service.dart`（FFmpeg提取WAV + whisper识别）
- 新建 `model_download_service.dart`（模型下载管理）
- UI 增加"识别字幕"按钮和进度对话框
- 预估版本号：v2.6.0

### Phase 4：工作流优化（可选）
- 批量识别、GPU加速等
