# Windows 便携版编译

[CODEX_LONG_TASK_CONTINUE_V3]

- 当前状态：已完成，`4.1.1+1` 便携目录、压缩包和 SHA-256 均已生成。
- 下一步：用户从便携目录直接运行，或将完整压缩包复制到其他电脑解压使用。
- TODO：无本次编译任务遗留项。
- 最近验证：Windows Release 构建成功；主程序启动并响应，五个功能入口已通过界面文本确认；SQLite 完整性通过；FFmpeg、FFprobe、SenseVoice、Qwen3-ASR 和 VAD 基础运行检查通过；7-Zip 压缩包完整性测试返回 Everything is Ok。
- Git：分支 `build/windows-portable`，起始提交 `f254c44`；本日已检查并推送远程（无待推送提交）。本任务新增记录及打包脚本以 `build: package Windows portable release 4.1.1` 本地提交，不自动重复推送；提交哈希以 Git 历史为准。
- 阻塞：无构建阻塞；窗口截图连续超时、设置页点击工具缓存失败，未完成视觉截图及设置页验收。

## 目标与范围

将当前 `video_subtitle_editor` 源码构建为 Windows x64 免安装程序，保存在根目录 `dist/` 的新版本目录。保留旧目录和真实业务数据。优先保持业务源码不变，必要时修复导致构建或启动失败的问题。

## 验收标准

1. Windows Release 构建成功，主程序及 Flutter 运行依赖齐全。
2. 附带 FFmpeg/FFprobe、ASR 工具和本地可用的 SenseVoice 模型，依赖使用发行包相对路径。
3. 实际启动主程序并检查界面；核对工具可执行、模型路径与数据库初始化。
4. 交付便携目录、压缩包、SHA-256 校验值和如实记录的验证结果。

## 执行约定

不将二进制、模型、用户数据库提交 Git；打包目录从干净 Release 文件创建，不复制旧发行目录内的数据。历史业务功能验收不在本次编译范围内。

## 实现和验证

- Flutter：`D:/flutter/bin/flutter.bat`，3.38.8 / Dart 3.10.7；Visual Studio 2022 Build Tools。
- 构建命令：`flutter build windows --release --build-name 4.1.1 --build-number 1`，耗时 71.4 秒，退出码 0。
- 打包脚本：`tool/package-portable.ps1`；要求新版本目录不存在，预检主程序版本、数据库 DLL 和运行资源，复制 Flutter 资源与 Visual C++ CRT。
- 发行目录：`dist/v4.1.1/`；主程序 `DIT-v4.1.1.exe`。程序集版本与文件版本均为 `4.1.1+1`。
- 包含 FFmpeg/FFprobe、sherpa-onnx 1.12.38、CPU/CUDA 依赖、Silero VAD、SenseVoice 和 Qwen3-ASR 0.6B int8 模型。模型复用旧目录中的资源，不复制旧数据库或工程数据。
- 验证使用包内工具生成 1 秒 16kHz WAV、读取参数并导出测试图像；两种 ASR 模型在 CPU 模式下加载并推理成功；VAD+SenseVoice 运行成功。合成音频不能证明真实语音识别准确率，未验收 GPU 推理或真实素材合板精度。
- 程序首次启动按既有迁移逻辑读取本机 SharedPreferences 中的旧工程。关闭程序后仅移除本次新发行目录内由验收生成的 `data/app.db`；原始数据库和系统用户配置保留。
- 无业务源码或依赖版本改动，因此未运行与本次打包无关的业务测试。旧 widget test 仍使用“工程管理”文案，未在本任务中修订。

## 最终交付

- 可运行程序：`dist/v4.1.1/DIT-v4.1.1.exe`。
- 便携压缩包：`dist/DIT-v4.1.1-windows-x64-portable.zip`，2,889,994,699 字节，90 个文件，解压后约 4.23 GB。
- 校验文件：`dist/DIT-v4.1.1-windows-x64-portable.zip.sha256`。
- SHA-256：`eea72360f3c22160d5d1ef4bec226bad2875562056d87dd8d1f11f9e405d2d3f`。
- 包内包含使用说明、编译日志、验收记录、构建信息及文件清单。
