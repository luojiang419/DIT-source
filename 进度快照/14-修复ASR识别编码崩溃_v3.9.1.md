# 进度快照 14 — 修复 ASR 识别编码崩溃

**日期**: 2026-04-17
**版本**: v3.9.1

---

## 已完成内容

### 问题根因
ASR合板页面的 ASR 识别在调用 sherpa-onnx 工具时崩溃，原因是 **编码不匹配**：
- sherpa-onnx 工具在 Windows 上输出混合编码：路径/配置行使用系统默认编码（GBK），识别文本使用 UTF-8
- Dart 代码使用 `stdoutEncoding: utf8` 解码，遇到 GBK 字节后抛出 `FormatException: Missing extension byte`
- 导致整个识别流程中断，无法产生任何字幕

### 修复的文件
- `lib/services/sherpa_onnx_asr_service.dart`（2处修改）
  - `_processWithVad()` 方法：`stdoutEncoding: utf8` → `const Utf8Codec(allowMalformed: true)`
  - `_processSegment()` 方法：`stdoutEncoding: utf8` → `const Utf8Codec(allowMalformed: true)`
  - stderr 同步修改

### 验证结果
使用 `G:\data\260224-元数据脚本测试\1_Video\ces\C0457.mp4` 测试：
- 修复前：FormatException 崩溃，0 条字幕
- 修复后：成功识别 160 条字幕，中文内容正确

### 备份
- `backup/v3.9.0_pre-asr-encoding-fix_*.tar.gz`

### 编译
- 新版本：`dist/v3.9.1/`
- 已复制 ffmpeg 目录
- 已复制 sherpa-onnx 目录（含 SenseVoice 模型、CUDA 运行库）

---

## 当前状态
- 源码修改、验证、编译全部完成
- v3.9.1 可直接运行

## 待办清单
（无）

## 下一步
- 运行 v3.9.1 测试 ASR合板页面完整流程
