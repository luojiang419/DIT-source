param(
    [string]$Version = '4.1.1',
    [string]$ModelsSource = '',
    [string]$CrtSource = ''
)

# 先执行 flutter build windows --release --build-name <Version> --build-number 1。
# 本脚本只创建新发行目录，不覆盖既有版本，也不复制业务数据库。
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$release = Join-Path $repoRoot 'video_subtitle_editor\build\windows\x64\runner\Release'
$destination = Join-Path $repoRoot "dist\v$Version"
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw '版本必须为 major.minor.patch' }
if (Test-Path -LiteralPath $destination) { throw "发行目录已存在：$destination" }
if (-not $ModelsSource) { $ModelsSource = Join-Path $repoRoot 'dist\v4.1\sherpa-onnx\models' }
if (-not $CrtSource) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsRoot = & $vswhere -latest -products '*' -property installationPath
    $crtVersions = Get-ChildItem (Join-Path $vsRoot 'VC\Redist\MSVC') -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending
    $CrtSource = Join-Path $crtVersions[0].FullName 'x64\Microsoft.VC143.CRT'
}
$required = @(
    "$release\video_subtitle_editor.exe", "$release\flutter_windows.dll",
    "$release\sqlite3.dll", "$release\data\app.so", "$release\data\icudtl.dat",
    "$release\data\flutter_assets", "$CrtSource\msvcp140.dll",
    "$repoRoot\ffmpeg\bin\ffmpeg.exe", "$repoRoot\ffmpeg\bin\ffprobe.exe",
    "$repoRoot\sherpa-onnx\bin\sherpa-onnx-offline.exe",
    "$repoRoot\sherpa-onnx\bin\sherpa-onnx-vad-with-offline-asr.exe",
    "$ModelsSource\silero_vad.onnx", "$ModelsSource\sense-voice-small\model.int8.onnx",
    "$ModelsSource\sense-voice-small\tokens.txt"
)
foreach ($item in $required) {
    if (-not (Test-Path -LiteralPath $item)) { throw "缺少发行依赖：$item" }
}
$compiledVersion = (Get-Item "$release\video_subtitle_editor.exe").VersionInfo.ProductVersion
if (-not $compiledVersion.StartsWith($Version + '+') -and $compiledVersion -ne $Version) {
    throw "主程序版本 $compiledVersion 与目标版本 $Version 不符"
}
New-Item -ItemType Directory -Path $destination | Out-Null
Get-ChildItem -LiteralPath $release -File -Filter '*.dll' | Copy-Item -Destination $destination
Copy-Item -LiteralPath "$release\video_subtitle_editor.exe" -Destination "$destination\DIT-v$Version.exe"
$dataDestination = New-Item -ItemType Directory -Path "$destination\data"
foreach ($item in @('app.so', 'icudtl.dat', 'flutter_assets')) {
    Copy-Item -LiteralPath "$release\data\$item" -Destination $dataDestination.FullName -Recurse
}
$ffmpegDestination = New-Item -ItemType Directory -Path "$destination\ffmpeg\bin" -Force
foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) {
    Copy-Item -LiteralPath "$repoRoot\ffmpeg\bin\$name" -Destination $ffmpegDestination.FullName
}
$sherpaDestination = New-Item -ItemType Directory -Path "$destination\sherpa-onnx\bin" -Force
Get-ChildItem "$repoRoot\sherpa-onnx\bin" -File -Filter '*.dll' |
    Copy-Item -Destination $sherpaDestination.FullName
foreach ($name in @('sherpa-onnx-offline.exe', 'sherpa-onnx-vad.exe',
    'sherpa-onnx-vad-with-offline-asr.exe', 'sherpa-onnx-offline-punctuation.exe', 'sherpa-onnx-version.exe')) {
    Copy-Item -LiteralPath "$repoRoot\sherpa-onnx\bin\$name" -Destination $sherpaDestination.FullName
}
foreach ($runtimeDestination in @($destination, $sherpaDestination.FullName)) {
    Get-ChildItem -LiteralPath $CrtSource -File -Filter '*.dll' | Copy-Item -Destination $runtimeDestination
}
$modelsDestination = New-Item -ItemType Directory -Path "$destination\sherpa-onnx\models"
Copy-Item -LiteralPath "$ModelsSource\silero_vad.onnx" -Destination $modelsDestination.FullName
Copy-Item -LiteralPath "$ModelsSource\sense-voice-small" -Destination $modelsDestination.FullName -Recurse
$qwen = Join-Path $ModelsSource 'sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25'
if (Test-Path -LiteralPath $qwen) {
    foreach ($item in @('conv_frontend.onnx','encoder.int8.onnx','decoder.int8.onnx','tokenizer\vocab.json','tokenizer\merges.txt')) {
        if (-not (Test-Path -LiteralPath "$qwen\$item")) { throw "Qwen3 模型不完整：$item" }
    }
    Copy-Item -LiteralPath $qwen -Destination $modelsDestination.FullName -Recurse
}
$licenses = New-Item -ItemType Directory -Path "$destination\licenses"
foreach ($entry in @(
    @{Source="$repoRoot\ffmpeg\LICENSE"; Name='FFmpeg-LICENSE'},
    @{Source="$repoRoot\sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17\LICENSE"; Name='SenseVoice-LICENSE'},
    @{Source="$repoRoot\dist\v4.1\LICENSE"; Name='legacy-third-party-LICENSE'}
)) {
    if (Test-Path -LiteralPath $entry.Source) { Copy-Item -LiteralPath $entry.Source -Destination (Join-Path $licenses $entry.Name) }
}
$sourceCommit = git -C $repoRoot rev-parse HEAD
@{
    version=$Version; compiledVersion=$compiledVersion; sourceCommit=$sourceCommit
    packagedAt=(Get-Date).ToString('o'); architecture='windows-x64'
    flutter='3.38.8'; executable="DIT-v$Version.exe"
} | ConvertTo-Json | Set-Content "$destination\build-info.json" -Encoding utf8
@"
DIT $Version Windows x64 便携版

完整解压本目录到可写位置，然后双击 DIT-v$Version.exe，无需安装。
请保留 data、ffmpeg、sherpa-onnx 与所有 DLL 文件；仅复制 EXE 无法运行。
首次运行会在 data/app.db 创建本地数据库。备份用户数据时请保留整个 data 目录。
包含 FFmpeg/FFprobe、SenseVoice、Qwen3-ASR（源目录存在时）、VAD 及 CPU/CUDA 运行依赖。
CUDA 加速还需要目标电脑安装兼容的 NVIDIA 显卡驱动；无兼容显卡时使用 CPU。
部分字体可能由原有应用逻辑在线获取；全局查找素材页面目前仍为占位实现。
"@ | Set-Content "$destination\使用说明.txt" -Encoding utf8
Write-Output "便携目录已创建：$destination"
