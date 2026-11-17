# 进度快照：Phase 3 whisper.cpp ASR 语音识别集成完成

**日期**：2026-04-15
**版本**：v2.6.0

---

## 已完成的全部阶段

### Phase 1：时间码驱动合板（v2.4.0）
- MultiPointSyncService 增加 `_syncByTimecodes()` 时间码同步策略
- 音频导入时自动提取源时间码存入 sourceTimecodes
- 智能合板支持时间码优先、字幕匹配降级

### Phase 2：时间码平铺（v2.5.0）
- 导入视频时弹出排列方式选择（按时间码平铺 / 紧凑排列）
- 按源时间码排列视频，保留录制间隔空白

### Phase 3：whisper.cpp ASR 语音识别（v2.6.0，本次完成）

#### 新增文件

| 文件 | 说明 | 行数 |
|------|------|------|
| `lib/services/whisper_path_service.dart` | whisper-cli.exe 路径管理 + 模型信息 | ~90行 |
| `lib/services/speech_recognition_service.dart` | ASR 调用封装（FFmpeg提取WAV + whisper识别 + SRT解析） | ~200行 |
| `lib/services/model_download_service.dart` | 模型文件下载管理（支持代理、进度流） | ~130行 |

#### 修改文件

| 文件 | 说明 |
|------|------|
| `lib/screens/clip_screen.dart` | AppBar新增🎤识别字幕按钮 + `_recognizeSubtitles()` 方法 + `_AsrConfigDialog` 配置对话框 |

#### 功能详解

**WhisperPathService**：
- 仿 FfmpegPathService 模式，静态类，二级路径解析（exe同级 → 开发机路径）
- 模型路径管理：`whisper/models/*.bin`
- 预置模型列表：small/base/medium/large-v3

**SpeechRecognitionService**：
- 完整流程：FFmpeg提取16kHz WAV → 分片(5分钟/段) → whisper-cli识别 → SRT解析 → TimelineClip
- 进度回调支持
- 自动清理临时文件

**ModelDownloadService**：
- Stream<DownloadProgress> 响应式下载
- 支持代理（192.168.0.211:7890）
- 下载到临时文件 → 完成后重命名

**UI 集成**：
- AppBar 新增 🎤 麦克风图标按钮
- 点击弹出 `_AsrConfigDialog`：选择轨道、语言(中/英/自动)、模型
- 自动检测模型是否已下载 → 弹出下载对话框
- 逐文件识别并显示进度 SnackBar
- 识别完成自动绑定字幕到对应轨道

---

## 编译状态

- **编译版本**：v2.6.0 → `dist/v2.6.0/`
- **ffmpeg**：已复制
- **备份**：`backup/backup_v2.5.0_*.tar.gz`

---

## 完整版本历史

| 版本 | 内容 | dist |
|------|------|------|
| v2.3.0 | 多点字幕锚点合板（基线） | ✅ |
| v2.4.0 | Phase 1: 时间码驱动合板 | ✅ |
| v2.5.0 | Phase 2: 时间码平铺 | ✅ |
| v2.6.0 | Phase 3: whisper.cpp ASR 集成 | ✅ |

---

## 下一步可选优化（Phase 4）

1. **批量识别**：一键识别所有轨道
2. **GPU加速**：检测 NVIDIA GPU → 启用 CUDA 模式
3. **设置页面**：ASR 模型管理、默认语言配置
4. **whisper-cli.exe 打包**：下载并放入 `tools/whisper/` 随编译分发
5. **自动检测提示**：导入视频时检测有音频轨道 → 自动提示识别字幕
