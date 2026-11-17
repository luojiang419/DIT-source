# 进度快照 - SenseVoice GPU 加速检测与降级

## 当前修改
为 SenseVoice ASR 引擎添加 GPU 自动检测和 CUDA→CPU 自动降级机制。

## 已完成内容

### 1. 修改 `sherpa_onnx_asr_service.dart`
- **新增 GPU 自动检测**（第 47-138 行）：
  - `hasNvidiaGpu()` — 检测系统是否有 NVIDIA GPU（通过 nvidia-smi）
  - `detectCudaSupport()` — 三重检测：NVIDIA GPU → CUDA DLL → cuDNN DLL
  - `autoSelectProvider()` — 自动选择最佳 provider（优先 CUDA）
  - `resetGpuCache()` — 重置检测缓存
- **修改 `recognize()` 方法**：
  - 默认 provider 从 `'cpu'` 改为 `'auto'`
  - 添加 CUDA→CPU 自动降级：CUDA 失败时自动切换到 CPU 重试
- **新增 `_recognizeWithProvider()` 辅助方法**：
  - 封装原 VAD/Legacy 选择逻辑
  - 支持指定 provider 执行

### 2. 确认调用方无需修改
- `clip_screen.dart` 两处调用 `sherpaService!.recognize()` 未传 provider 参数
- 默认值已改为 `'auto'`，自动检测生效，无需改动

### 3. 编译验证
- `flutter analyze` 通过，仅 info 级别提示（avoid_print）

## 待完成（环境层面）
- **cuDNN DLL 缺失**：`sherpa-onnx\bin\` 目录缺少 cuDNN 9.x DLL
  - 需要：`cudnn64_9.dll`、`cudnn_ops_infer64_9.dll` 等
  - 解决方案：下载 cuDNN 9.x for CUDA 12.x 并将 DLL 复制到 `sherpa-onnx\bin\`
  - 代码已就绪，添加 cuDNN 后 GPU 即可自动启用

## 下一步
1. 下载 cuDNN 9 DLL 到 sherpa-onnx\bin\
2. 测试 --provider=cuda 是否正常
3. 编译新版本到 dist 文件夹
