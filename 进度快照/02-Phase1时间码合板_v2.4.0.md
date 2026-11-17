# 进度快照：Phase 1 时间码合板完成

**日期**：2026-04-15
**版本**：v2.4.0

---

## 已完成内容

### Phase 1：时间码驱动合板（v2.4.0）

**核心改动**：MultiPointSyncService 增加时间码同步策略，不再强制依赖字幕匹配。

#### 1. `lib/services/multipoint_sync_service.dart`（重构）

- **新增 `_syncByTimecodes()` 方法**：
  - 输入视频/音频的源时间码，直接计算音频偏移
  - `audioSourcePos = videoTC.startMs - audioBaseMs`
  - 精度 100%，confidence = 1.0
  - 自动分段：每个视频片段对应一段音频

- **提取 `_syncBySubtitleMatching()` 方法**：
  - 原 `performSync()` 的字幕匹配逻辑完整保留
  - 一对一匹配 → 锚点计算 → 分段/全局偏移策略不变

- **重构 `performSync()` 为策略路由**：
  - 优先检查音视频时间码 → 调用 `_syncByTimecodes()`
  - 无时间码时降级 → 调用 `_syncBySubtitleMatching()`
  - 新增 `_extractAudioTimecodes()` 自动从音频轨道提取时间码

#### 2. `lib/screens/clip_screen.dart`（3处修改）

- **`_importAudio()` 单文件导入**：
  - 导入音频后自动调用 `TimecodeService.extractTimecode()`
  - 将音频时间码存入 `TimelineProject.sourceTimecodes`

- **`_importAudioFolder()` 批量导入**：
  - 遍历音频文件时逐个提取时间码
  - 合并到 `sourceTimecodes`

- **`_performMultiPointSync()` 智能合板**：
  - 检测时间码可用性，显示使用的策略（"时间码同步"/"字幕匹配"）
  - 时间码锚点显示 "精确" 标签（蓝色），字幕锚点显示偏移量
  - 不再强制要求字幕才能合板

- **`_canAutoSync()` 启用条件扩展**：
  - 原条件：视频有字幕 && 音频有字幕
  - 新增条件：视频有时间码 && 音频有时间码

---

## 当前修改到的模块

| 文件 | 改动类型 | 行数变化 |
|------|---------|---------|
| `multipoint_sync_service.dart` | 重构+新增 | ~150行新增 |
| `clip_screen.dart` | 修改 | ~80行修改 |

---

## 编译状态

- **编译版本**：v2.4.0 → `dist/v2.4.0/`
- **ffmpeg**：已复制到 `dist/v2.4.0/ffmpeg/`
- **备份**：`backup/backup_v2.3.0_20260415_140021.tar.gz`

---

## 下一步待办（按优先级）

### Phase 2：时间码平铺（时间轴可视化）
- 修改 `_loadProject()` 增加时间码平铺模式
- 导入时弹出排列方式选择对话框（按TC平铺 / 紧凑排列）
- 时间轴缩放适配大跨度时间线
- 预估版本号：v2.5.0

### Phase 3：whisper.cpp 集成（ASR语音识别）
- 新建 `whisper_path_service.dart`（路径管理）
- 新建 `speech_recognition_service.dart`（ASR调用封装）
- 新建 `model_download_service.dart`（模型下载）
- UI 增加"识别字幕"按钮和进度对话框
- 预估版本号：v2.6.0

### Phase 4：工作流优化（可选）
- 自动检测音频轨道 → 提示识别字幕
- 批量识别
- GPU加速
