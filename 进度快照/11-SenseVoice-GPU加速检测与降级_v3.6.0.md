# 进度快照 - SenseVoice GPU 加速启用

## 修改摘要
为 SenseVoice ASR 引擎启用 GPU（CUDA）加速，包含环境修复和代码自动检测/降级机制。

## 已完成内容

### 1. 代码修改：`sherpa_onnx_asr_service.dart`
- **GPU 自动检测**（4 重检查）：
  1. NVIDIA GPU 检测（nvidia-smi）
  2. CUDA DLL 检查（cudart64_12.dll, onnxruntime_providers_cuda.dll）
  3. cuDNN DLL 检查（cudnn64_9.dll, cudnn_ops64_9.dll）
  4. cuFFT DLL 检查（cufft64_11.dll）
- **自动 provider 选择**：默认 `'auto'` → CUDA 可用则用，否则 CPU
- **CUDA→CPU 自动降级**：CUDA 推理失败时自动切换 CPU 重试
- **GPU 缓存管理**：`resetGpuCache()` 方法支持重新检测

### 2. 环境修复：sherpa-onnx DLL 升级
| DLL | 版本 | 来源 |
|-----|------|------|
| sherpa-onnx executables | v1.12.38 | GitHub Release |
| onnxruntime.dll | v1.12.38 内置 | sherpa-onnx CUDA 版 |
| onnxruntime_providers_cuda.dll | v1.12.38 内置 | sherpa-onnx CUDA 版 |
| cudart64_12.dll | CUDA 12.9.79 | pip nvidia-cuda-runtime-cu12 |
| cublas64_12.dll | CUDA 12.9.2.10 | pip nvidia-cublas-cu12 |
| cublasLt64_12.dll | CUDA 12.9.2.10 | pip nvidia-cublas-cu12 |
| cudnn64_9.dll + 8 个 | cuDNN 9.21.0.82 | pip nvidia-cudnn-cu12 |
| cufft64_11.dll + cufftw64_11.dll | cuFFT 11.4.1.4 | pip nvidia-cufft-cu12 |
| nvJitLink_120_0.dll | 12.9.86 | pip nvidia-nvjitlink-cu12 |

### 3. 测试结果
- **CUDA provider**：✅ exit code 0，recognizer 创建耗时 1.542s
- **CPU provider**：✅ exit code 0，recognizer 创建耗时 0.904s
- **调用方无需修改**：默认值从 `'cpu'` 改为 `'auto'`，自动生效

### 4. 版本编译
- 新版本：**v3.6.0** → `G:\data\app\DIT\dist\v3.6.0\`
- 包含所有 CUDA DLL、ffmpeg、whisper、sherpa-onnx
- 源代码备份：`G:\data\app\DIT\backup\v3.5.0-backup-20260416-125646`

## 下一步
- 用户可运行 v3.6.0 测试实际 ASR 识别的 GPU 加速效果
- 对比 CUDA 和 CPU 的识别速度差异
