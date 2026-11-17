# 进度快照 - ASR 合板页面重新实现 + GPU 加速

## 修改摘要
重新实现 ASR 自动合板页面（源码曾丢失），同时完成 SenseVoice GPU 加速。

## 已完成内容

### 一、SenseVoice GPU 加速（v3.6.0-v3.7.0）

#### 代码修改：`sherpa_onnx_asr_service.dart`
- GPU 自动检测（4 重检查）：NVIDIA GPU → CUDA DLL → cuDNN DLL → cuFFT DLL
- 自动 provider 选择：默认 `'auto'`，CUDA 可用则用，否则 CPU
- CUDA→CPU 自动降级：CUDA 推理失败时自动切换 CPU 重试
- `resetGpuCache()` 方法支持重新检测

#### 环境修复：sherpa-onnx DLL 升级
| 组件 | 版本 |
|------|------|
| sherpa-onnx executables | v1.12.38 |
| onnxruntime | v1.12.38 内置 |
| cudart64_12.dll | CUDA 12.9.79 |
| cublas64_12.dll / cublasLt64_12.dll | CUDA 12.9.2.10 |
| cudnn64_9.dll + 8 个 | cuDNN 9.21.0.82 |
| cufft64_11.dll | cuFFT 11.4.1.4 |
| nvJitLink_120_0.dll | 12.9.86 |

### 二、ASR 合板页面重新实现（v3.8.0）

#### 新增文件（5 个）

| 文件 | 行数 | 说明 |
|------|------|------|
| `lib/models/asr_project.dart` | ~210 | AsrProject + MatchPair + AsrProjectStatus 数据模型 |
| `lib/services/asr_project_service.dart` | ~100 | ASR 工程 CRUD + 状态管理 |
| `lib/services/asr_match_service.dart` | ~210 | 字幕上下文滑动窗口匹配算法 |
| `lib/screens/asr_project_list_screen.dart` | ~290 | 工程列表页（卡片网格 + 新建/删除） |
| `lib/screens/asr_project_detail_screen.dart` | ~740 | 工程操作页（4 步骤引导） |

#### 修改文件（3 个）

| 文件 | 修改内容 |
|------|---------|
| `lib/screens/main_shell.dart` | 导航栏从 4 项改为 5 项，新增 "ASR合板" 标签 |
| `lib/services/database_service.dart` | DB 版本 1→2，新增 asr_projects 表 + CRUD 方法 |
| `lib/state/app_state.dart` | 新增 `addAsrSyncedProject()` 方法 |

#### 功能流程
1. **Step 1 导入素材**：选择视频/音频目录，自动扫描文件
2. **Step 2 ASR 识别**：调用 SenseVoice/Whisper 逐文件识别，实时进度显示
3. **Step 3 匹配确认**：字幕上下文自动匹配，显示置信度，支持查看匹配对
4. **Step 4 创建时间线**：根据匹配结果裁切音频，生成 TimelineProject，跳转剪辑页

### 三、版本记录

| 版本 | 内容 | dist |
|------|------|------|
| v3.5.0 | ASR 合板页面（原始实现，源码已丢失） | ✅ |
| v3.6.0 | SenseVoice GPU 加速检测与降级 | ✅ |
| v3.7.0 | GPU 加速版本（用户请求编译） | ✅ |
| **v3.8.0** | **ASR 合板页面重新实现 + GPU 加速** | ✅ |

### 四、备份
- 源码备份：`backup/v3.5.0-backup-20260416-125646`

## 下一步
- 用户运行 v3.8.0 测试 ASR 合板页面完整流程
- 验证 GPU 加速效果（CUDA vs CPU 速度对比）
