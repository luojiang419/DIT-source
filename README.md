# DIT 影视素材与字幕合板工具

基于 Flutter 的 Windows 桌面项目，源码位于 `video_subtitle_editor/`。功能包含合板工作台、多轨时间轴、字幕导入与对齐、ASR 合板、元数据管理和报表导出。全局素材检索页面目前仍为占位实现。

## 开发

安装与 `video_subtitle_editor/pubspec.yaml` 匹配的 Flutter SDK，然后执行：

```powershell
cd video_subtitle_editor
flutter pub get
flutter run -d windows
```

编译 Windows 应用：

```powershell
flutter build windows --release
```

2026-11-18 已在本机使用 Flutter 3.38.8 构建 `4.1.1+1` Windows x64 便携版。发行产物保存在 `dist/v4.1.1/`，不纳入 Git。

重新打包时，先在应用目录执行带版本的构建，再回到仓库根目录运行打包脚本：

```powershell
cd video_subtitle_editor
flutter build windows --release --build-name 4.1.1 --build-number 1
cd ..
.\tool\package-portable.ps1 -Version 4.1.1 -ModelsSource '模型目录绝对路径'
```

脚本要求目标版本目录不存在，且模型目录中至少有 `sense-voice-small/model.int8.onnx`、`sense-voice-small/tokens.txt` 和 `silero_vad.onnx`。如需打包其他版本，调整构建及脚本中的版本参数。完整使用说明和本次验证范围随便携版提供。

## 外部依赖

仓库仅保存源码、平台工程、依赖清单与开发记录，不包含 FFmpeg、sherpa-onnx、ASR 模型、视频素材、业务数据库、备份和编译产物。

运行完整功能需要另行准备以下资源：

- FFmpeg 与 FFprobe：发布程序旁的 `ffmpeg/bin/`。
- sherpa-onnx 可执行文件及其依赖：发布程序旁的 `sherpa-onnx/bin/`。
- 对应 ASR 模型和 tokens 文件：`sherpa-onnx/models/`，具体规则见 `sherpa_onnx_path_service.dart`。

现有源码与 Windows CMake 配置仍包含旧开发机 `G:\data\app\DIT` 路径；迁移电脑时需核对 `ffmpeg_path_service.dart`、`sherpa_onnx_path_service.dart` 和 `windows/CMakeLists.txt`。单独编译 Flutter 不代表上述运行资源已完整打包。

## 进度记录

根目录 `进度快照/` 保存历史开发记录。`video_subtitle_editor/docs/开发计划与进度.md` 为较早的进度表，不能单独作为当前完成情况的依据。

首次源码归档未修改业务逻辑；后续 Windows 便携版构建与启动验收见 `开发任务/01-Windows便携版编译.md`。
