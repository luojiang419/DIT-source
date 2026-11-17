# 进度快照：Phase 4 工作流优化完成

**日期**：2026-04-15
**版本**：v2.7.0

---

## 智能合板完整方案 — 全部四个阶段开发完成

### Phase 1：时间码驱动合板（v2.4.0）✅
### Phase 2：时间码平铺（v2.5.0）✅
### Phase 3：whisper.cpp ASR 语音识别（v2.6.0）✅

### Phase 4：工作流优化（v2.7.0，本次完成）

#### 4.1 批量识别
- 新增 `_batchRecognizeAll()` 方法，一键识别所有无字幕轨道
- AppBar 新增"批量识别"按钮（`Icons.playlist_play`）
- 自动跳过已有字幕的轨道
- 逐文件处理并显示进度

#### 4.2 自动检测提示
- 新增 `_promptAsrIfAvailable()` 方法
- 导入音频后自动检测：如果存在无字幕轨道 → 弹出提示对话框
- 用户可选择"开始识别"或"跳过"

#### 4.3 GPU 加速检测
- `SpeechRecognitionService` 新增 `hasNvidiaGpu()` 静态方法
- 调用 `nvidia-smi` 检测 NVIDIA GPU（结果缓存）
- 自动在 whisper-cli 参数中加入 `--use-gpu`

#### 4.4 设置页面 — ASR 管理
- `settings_screen.dart` 新增"ASR 语音识别"配置区域：
  - Whisper CLI 状态显示（已就绪/未找到）
  - 模型目录路径
  - 已下载模型列表（支持删除）
  - 可下载模型列表（一键下载 + 进度条）
  - 下载使用代理 192.168.0.211:7890

---

## 修改文件清单

| 文件 | Phase | 改动 |
|------|-------|------|
| `lib/services/speech_recognition_service.dart` | 4.3 | +GPU 检测 + --use-gpu |
| `lib/screens/clip_screen.dart` | 4.1/4.2 | +批量识别 + 自动提示 |
| `lib/screens/settings_screen.dart` | 4.4 | +ASR 配置区域 |

---

## 编译状态

- **编译版本**：v2.7.0 → `dist/v2.7.0/`
- **ffmpeg**：已复制
- **备份**：`backup/backup_v2.6.0_*.tar.gz`

---

## 完整版本历史

| 版本 | 内容 | dist |
|------|------|------|
| v2.3.0 | 多点字幕锚点合板（基线） | ✅ |
| v2.4.0 | Phase 1: 时间码驱动合板 | ✅ |
| v2.5.0 | Phase 2: 时间码平铺 | ✅ |
| v2.6.0 | Phase 3: whisper.cpp ASR 集成 | ✅ |
| v2.7.0 | Phase 4: 工作流优化 | ✅ |

---

## 智能合板完整方案开发完毕

完整工作流：
```
导入视频 → [选择时间码平铺/紧凑排列] → [自动提示ASR识别] → ASR生成字幕
导入音频 → [自动提取时间码]           → [自动提示ASR识别] → ASR生成字幕
智能合板 → [时间码优先/字幕匹配降级] → 结果确认 → 应用
一键修剪 → 压缩空白 → 导出 FCP7 XML
```

所有四个 Phase 均已完成并通过编译。
