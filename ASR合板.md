# ASR 自动合板 — 完整功能方案

> 日期：2026-04-15
> 项目：video_subtitle_editor（v3.0.0）
> 依赖：whisper.cpp ASR 已集成（v2.9.0 已验证可用）

---

## 一、功能概述

### 1.1 核心定位

一个**完全独立的**"ASR 自动合板"功能模块，用户只需导入视频目录和音频目录，系统自动完成：
1. 语音识别（ASR）→ 为每个视频和音频生成字幕
2. 字幕上下文匹配 → 自动判断哪些视频和音频是同步录制的
3. 一键创建时间线 → 自动裁切音频适配视频长度

### 1.2 与现有"智能合板"的区别

| 对比项 | 现有智能合板 | ASR 自动合板 |
|--------|-------------|-------------|
| 入口 | 剪辑页内按钮 | 独立工程卡片页面 |
| 字幕来源 | 需手动导入 SRT 或手动触发 ASR | 全自动 ASR，无需手动操作 |
| 匹配方式 | 依赖时间码或手动选字幕锚点 | 上下文语义自动匹配 |
| 适用人群 | 熟练用户（需理解合板概念） | 新手友好（一键操作） |
| 匹配粒度 | 音频整体偏移 | 逐条视频↔音频配对 |

### 1.3 典型使用场景

```
场景：纪录片拍摄
  - 拍摄设备：3台摄像机（各录制了若干视频片段）
  - 录音设备：2个独立录音机（各录制了若干音频文件）
  - 所有视频和音频在同一时间段内同时录制
  - 需要自动找出哪个视频对应哪段音频，并自动对齐

操作流程：
  1. 新建 ASR 合板工程
  2. 导入视频目录 → 自动扫描 30 个视频文件
  3. 导入音频目录 → 自动扫描 8 个音频文件
  4. 点击"自动合板" → ASR 识别所有文件 → 自动匹配
  5. 查看匹配结果 → 确认或调整
  6. 点击"创建时间线" → 生成完整时间线，音频裁切到位
```

---

## 二、页面结构与导航

### 2.1 在导航栏中的位置

在现有 `MainShell` 的 `NavigationRail` 中新增一个标签页：

```
NavigationRail（侧边栏，5个标签）
  ├── 0. 合板工作台   →  HomeScreen（已有，项目卡片管理）
  ├── 1. ASR 合板     →  AsrProjectListScreen（新增 ★）
  ├── 2. 元数据管理   →  DitDataScreen（已有）
  ├── 3. 查找素材     →  SearchScreen（已有）
  └── 4. 设置         →  SettingsScreen（已有）
```

### 2.2 页面层级

```
ASR 合板（标签页）
  │
  ├── [AsrProjectListScreen]          ← 工程列表页（卡片网格）
  │     ├── 顶部：标题 + 新建工程按钮
  │     ├── 主体：工程卡片网格
  │     │     每张卡片显示：
  │     │       - 工程名称
  │     │       - 视频数量 / 音频数量
  │     │       - 状态标签（待识别 / 识别中 / 已匹配 / 已完成）
  │     │       - 创建时间
  │     └── 卡片操作：点击进入 / 长按删除
  │
  └── [AsrProjectDetailScreen]        ← 工程操作页（Navigator.push）
        ├── 顶部：工程名称 + 返回按钮
        ├── 步骤条：① 导入素材 → ② ASR识别 → ③ 匹配确认 → ④ 创建时间线
        ├── 主体内容区（根据步骤切换）
        │     Step 1: 素材导入面板
        │     Step 2: ASR 识别进度面板
        │     Step 3: 匹配结果面板
        │     Step 4: 时间线预览面板
        └── 底部：操作按钮区
```

---

## 三、详细 UI 设计

### 3.1 工程列表页（AsrProjectListScreen）

```
┌──────────────────────────────────────────────────────────────┐
│  ASR 自动合板                                     [+ 新建工程] │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ 📁 拍摄Day1      │  │ 📁 拍摄Day2      │  │ 📁 新工程    │ │
│  │                  │  │                  │  │             │ │
│  │ 🎬 12个视频      │  │ 🎬 8个视频       │  │  🎬 0个视频  │ │
│  │ 🎙 4个音频       │  │ 🎙 3个音频       │  │  🎙 0个音频  │ │
│  │                  │  │                  │  │             │ │
│  │ ✅ 已完成         │  │ 🔄 识别中 45%    │  │ ⏳ 待识别    │ │
│  │ 2026-04-14       │  │ 2026-04-15       │  │ 2026-04-15  │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**卡片样式规范**：
- 圆角矩形卡片，宽 260px，固定高度
- 顶部：工程名称（加粗，单行截断）
- 中部：视频/音频文件数量统计（带图标）
- 底部：状态标签（颜色区分） + 创建日期
- 悬停/选中：边框高亮 + 轻微上浮阴影

**状态标签颜色**：
| 状态 | 颜色 | 含义 |
|------|------|------|
| 待识别 | 灰色 | 未添加素材或未开始ASR |
| 识别中 | 蓝色（带动画） | ASR 正在工作 |
| 已匹配 | 绿色 | ASR 完成，匹配结果已生成 |
| 已完成 | 深绿色 | 时间线已创建 |
| 识别失败 | 红色 | ASR 出错 |

**新建工程对话框**：
```
┌────────────────────────────┐
│  新建 ASR 合板工程          │
│                             │
│  工程名称：                  │
│  [拍摄Day3____________]     │
│                             │
│          [取消]  [创建]      │
└────────────────────────────┘
```

### 3.2 工程操作页（AsrProjectDetailScreen）

#### Step 1：素材导入

```
┌──────────────────────────────────────────────────────────────────┐
│  ← 返回    拍摄Day1 — ASR 自动合板                                │
├──────────────────────────────────────────────────────────────────┤
│  ① 导入素材   ② ASR识别   ③ 匹配确认   ④ 创建时间线               │
│  [═════════]  ────────  ────────  ────────                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────┐  ┌──────────────────────────────┐ │
│  │  视频素材                  │  │  音频素材                      │ │
│  │                           │  │                               │ │
│  │  [📁 选择视频目录]         │  │  [📁 选择音频目录]              │ │
│  │                           │  │                               │ │
│  │  G:\拍摄\Day1\1_Video     │  │  G:\拍摄\Day1\2_Audio         │ │
│  │                           │  │                               │ │
│  │  已添加 12 个文件：        │  │  已添加 4 个文件：              │ │
│  │  ├ C0457.mp4    12:34     │  │  ├ ZOOM0021_LR.mp3  45:12    │ │
│  │  ├ C0458.mp4    08:21     │  │  ├ ZOOM0022_LR.mp3  32:45    │ │
│  │  ├ C0459.mp4    15:03     │  │  ├ R001.wav         28:30    │ │
│  │  ├ ...                    │  │  └ R002.wav         15:20    │ │
│  │                           │  │                               │ │
│  │  总时长：2h 15m            │  │  总时长：2h 01m                │ │
│  │  总大小：8.3 GB            │  │  总大小：1.2 GB                │ │
│  │                           │  │                               │ │
│  │  [清空视频列表]            │  │  [清空音频列表]                │ │
│  └──────────────────────────┘  └──────────────────────────────┘ │
│                                                                  │
│                 ASR 语言：[中文 ▼]  模型：[medium ▼]               │
│                                                                  │
│                          [开始 ASR 识别 →]                        │
└──────────────────────────────────────────────────────────────────┘
```

**交互说明**：
- 左右分栏布局，视频/音频各占一半
- "选择目录"按钮：调用 `file_picker` 选择文件夹
- 选择后自动扫描目录下所有视频/音频文件（复用 `MediaScanService`）
- 文件列表可滚动，显示文件名 + 时长
- 底部显示汇总信息（总时长、总大小）
- 语言和模型选择下拉框（复用 `SettingsScreen` 中的配置）
- 底部"开始 ASR 识别"按钮，需视频和音频都有文件才可点击

**额外功能 — 也支持单文件/多文件导入**：
- 目录按钮旁边有"添加文件"按钮，可手动选择单个或多个文件
- 支持拖拽文件到列表区域（复用 `desktop_drop` 插件）
- 文件列表支持删除单个文件（右键菜单或滑动删除）

#### Step 2：ASR 识别进度

```
┌──────────────────────────────────────────────────────────────────┐
│  ← 返回    拍摄Day1 — ASR 自动合板                                │
├──────────────────────────────────────────────────────────────────┤
│  ① 导入素材   ② ASR识别   ③ 匹配确认   ④ 创建时间线               │
│  ────────  [═════════]  ────────  ────────                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─ 视频识别进度 ──────────────────────────────────────────────┐ │
│  │                                                              │ │
│  │  ✅ C0457.mp4    — 356 条字幕    完成                        │ │
│  │  ✅ C0458.mp4    — 243 条字幕    完成                        │ │
│  │  🔄 C0459.mp4    — [████████░░░░] 72%    正在识别...         │ │
│  │  ⏳ C0460.mp4    — 等待中                                    │ │
│  │  ⏳ C0461.mp4    — 等待中                                    │ │
│  │  ...                                                         │ │
│  │                                                              │ │
│  │  总进度：5/12 已完成    预计剩余：8 分钟                       │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─ 音频识别进度 ──────────────────────────────────────────────┐ │
│  │                                                              │ │
│  │  ✅ ZOOM0021_LR.mp3 — 1,245 条字幕   完成                   │ │
│  │  🔄 ZOOM0022_LR.mp3 — [██████████░░] 88%   正在识别...      │ │
│  │  ⏳ R001.wav        — 等待中                                 │ │
│  │  ⏳ R002.wav        — 等待中                                 │ │
│  │                                                              │ │
│  │  总进度：1/4 已完成    预计剩余：12 分钟                       │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│                          [取消识别]                               │
└──────────────────────────────────────────────────────────────────┘
```

**交互说明**：
- 上方视频识别区，下方音频识别区（可滚动）
- 每个文件一行：状态图标 + 文件名 + 字幕数量 + 进度条
- 识别完成的文件显示"✅"和识别到的字幕数量
- 正在识别的文件显示进度条和百分比
- 等待中的文件显示"⏳"
- 底部汇总：已完成数/总数 + 预估剩余时间
- "取消识别"按钮：停止当前 ASR 任务，已完成的识别结果保留
- 全部完成后自动跳转到 Step 3

**ASR 优化策略**：
- 视频和音频**并行识别**（各自独立队列）
- 长文件分片处理（每 5 分钟一段，复用 `SpeechRecognitionService`）
- 已识别的文件缓存结果，重新进入不重复识别
- 识别失败的单文件标记为红色"❌"，不影响其他文件继续

#### Step 3：匹配结果确认

```
┌──────────────────────────────────────────────────────────────────┐
│  ← 返回    拍摄Day1 — ASR 自动合板                                │
├──────────────────────────────────────────────────────────────────┤
│  ① 导入素材   ② ASR识别   ③ 匹配确认   ④ 创建时间线               │
│  ────────  ────────  [═════════]  ────────                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  自动匹配完成：成功匹配 10 对，2 个视频未匹配                       │
│                                                                  │
│  ┌─ 匹配结果列表 ──────────────────────────────────────────────┐ │
│  │                                                              │ │
│  │  ✅ 匹配  C0457.mp4  ←→  ZOOM0021_LR.mp3   置信度：98%      │ │
│  │     上下文匹配：12/12 条字幕一致（偏移：+2.3s）                │ │
│  │     [查看字幕对比]                                            │ │
│  │                                                              │ │
│  │  ✅ 匹配  C0458.mp4  ←→  ZOOM0021_LR.mp3   置信度：95%      │ │
│  │     上下文匹配：8/10 条字幕一致（偏移：+18m45s）               │ │
│  │                                                              │ │
│  │  ✅ 匹配  C0459.mp4  ←→  ZOOM0022_LR.mp3   置信度：91%      │ │
│  │     上下文匹配：7/9 条字幕一致（偏移：+5.2s）                  │ │
│  │                                                              │ │
│  │  ⚠ 低置信  C0460.mp4 ←→  ZOOM0022_LR.mp3  置信度：62%      │ │
│  │     上下文匹配：3/8 条字幕一致（建议人工确认）                  │ │
│  │     [手动调整]  [取消匹配]                                    │ │
│  │                                                              │ │
│  │  ❌ 未匹配  C0461.mp4  — 未找到对应音频                       │ │
│  │  ❌ 未匹配  C0462.mp4  — 未找到对应音频                       │ │
│  │                                                              │ │
│  │  ─── 音频文件状态 ───                                         │ │
│  │  ZOOM0021_LR.mp3  匹配 2 个视频                               │ │
│  │  ZOOM0022_LR.mp3  匹配 2 个视频                               │ │
│  │  R001.wav          未匹配任何视频                              │ │
│  │  R002.wav          未匹配任何视频                              │ │
│  │                                                              │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  [重新匹配]                              [确认匹配，创建时间线 →]  │
└──────────────────────────────────────────────────────────────────┘
```

**匹配结果说明**：
- 每对匹配显示：视频名 ↔ 音频名 + 置信度百分比
- 置信度颜色：≥90% 绿色，70-89% 黄色，<70% 红色
- "查看字幕对比"：弹出对话框，左右对比视频字幕和音频字幕，高亮匹配的部分
- 低置信度匹配（<70%）：显示警告图标，提供"手动调整"和"取消匹配"按钮
- 未匹配的文件单独列出，提示原因
- 音频文件可能匹配多个视频（同一段录音覆盖多个视频片段）

**字幕对比对话框**：
```
┌────────────────────────────────────────────────────────┐
│  字幕对比：C0457.mp4 ←→ ZOOM0021_LR.mp3                 │
├───────────────────────┬────────────────────────────────┤
│  视频字幕              │  音频字幕                        │
│                       │                                │
│  00:01:23,400         │  00:01:25,700                  │
│  今天天气真不错        │  今天天气真不错                  │
│                       │                                │
│  00:01:26,800         │  00:01:29,100                  │
│  我们去公园走走吧      │  我们去公园走走吧                │
│                       │                                │
│  00:01:30,200         │  00:01:32,500                  │
│  好啊，走这边          │  好啊走这边                     │
│                       │                                │
│  (共 356 条)          │  (共 1,245 条，已筛选匹配段)    │
├───────────────────────┴────────────────────────────────┤
│  匹配偏移：+2.3s（音频比视频晚 2.3 秒）                    │
│  匹配区间：00:00:00 — 02:34:00                           │
│                              [关闭]                      │
└────────────────────────────────────────────────────────┘
```

**手动调整功能**（低置信度匹配）：
- 用户可以手动选择视频的 3 条字幕和音频的 3 条字幕作为锚点
- 系统根据锚点重新计算偏移
- 或者用户直接取消该匹配

#### Step 4：时间线预览与创建

```
┌──────────────────────────────────────────────────────────────────┐
│  ← 返回    拍摄Day1 — ASR 自动合板                                │
├──────────────────────────────────────────────────────────────────┤
│  ① 导入素材   ② ASR识别   ③ 匹配确认   ④ 创建时间线               │
│  ────────  ────────  ────────  [═════════]                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─ 时间线预览 ────────────────────────────────────────────────┐ │
│  │                                                              │ │
│  │  视频 │ [C0457][C0458]  [C0459]    [C0460]                   │ │
│  │  ─────┼──────────────────────────────────────────            │ │
│  │  音频 │ [ZOOM0021 ████] [ZOOM0022 ████] [──]                 │ │
│  │       │ (裁切适配)       (裁切适配)                           │ │
│  │  ─────┼──────────────────────────────────────────            │ │
│  │  字幕 │ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓              │ │
│  │       │ (视频ASR字幕)                                         │ │
│  │                                                              │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─ 裁切方案 ──────────────────────────────────────────────────┐ │
│  │                                                              │ │
│  │  C0457.mp4:  音频从 +2.3s 裁切，长度 12:34                   │ │
│  │  C0458.mp4:  音频从 +18m45s 裁切，长度 08:21                 │ │
│  │  C0459.mp4:  音频从 +5.2s 裁切，长度 15:03                   │ │
│  │  C0460.mp4:  音频从 +32m10s 裁切，长度 06:42                 │ │
│  │                                                              │ │
│  │  未匹配视频：C0461.mp4、C0462.mp4（无音频）                  │ │
│  │                                                              │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ☑ 导出时包含 ASR 字幕    ☑ 自动修剪空白间隙                      │
│                                                                  │
│  [← 返回修改匹配]    [创建时间线并打开编辑器]  [直接导出 FCP7 XML] │
└──────────────────────────────────────────────────────────────────┘
```

**操作说明**：
- 时间线预览：简化版可视化，显示视频和音频的对齐关系
- 裁切方案：详细列出每段音频的裁切起止点和长度
- 选项：
  - "导出时包含 ASR 字幕"：将 ASR 生成的字幕一起导出
  - "自动修剪空白间隙"：视频之间的空白自动压缩
- 三个操作按钮：
  - "返回修改匹配"：回到 Step 3 调整
  - "创建时间线并打开编辑器"：创建 TimelineProject → 跳转到 ClipScreen 继续编辑
  - "直接导出 FCP7 XML"：直接导出到文件，无需打开编辑器

---

## 四、核心算法设计

### 4.1 ASR 识别流程

```
输入：List<File> 视频文件列表 + List<File> 音频文件列表

For 每个 文件（视频或音频）:
  1. 检查缓存：是否已有识别结果
     └── 有 → 跳过，使用缓存结果
  2. 用 FFmpeg 提取 16kHz 单声道 WAV（复用 SpeechRecognitionService._extractWav）
  3. 分片（每 5 分钟一段）→ 逐片调用 whisper-cli
  4. 合并所有片的 SRT 结果
  5. 幻觉过滤（复用 _filterHallucination）
  6. 存储识别结果

输出：Map<filePath, List<TimelineClip>>  // 每个文件对应一组字幕
```

### 4.2 字幕上下文匹配算法

这是 ASR 合板的**核心创新**——不依赖时间码，完全通过字幕文本内容匹配。

#### 算法思路

```
原理：同一段录制的视频和音频，ASR 识别出的字幕内容必然相同（或高度相似）。
     通过比较每个视频和每个音频的字幕"指纹"，找到最佳配对。

指纹 = 连续 N 条字幕的文本序列（滑动窗口）
```

#### 详细步骤

```
Step 1：为每个文件生成字幕指纹集合

  For 每个视频文件 V:
    subtitles_v = V 的 ASR 字幕列表
    fingerprints_v = {}
    For i = 0 to len(subtitles_v) - window_size:
      window = subtitles_v[i : i + window_size]  // 取连续 window_size 条
      text = normalize(window 的文本拼接)
      fingerprints_v[text] = {startIndex: i, subtitles: window}

  For 每个音频文件 A:
    同上生成 fingerprints_a

Step 2：交叉匹配

  candidates = []
  For 每个视频 V:
    For 每个音频 A:
      match_score = computeMatchScore(fingerprints_v, fingerprints_a)
      if match_score.confidence >= threshold:
        candidates.add({
          video: V,
          audio: A,
          confidence: match_score.confidence,
          offset: match_score.offset,
          matchedWindows: match_score.matchedCount
        })

Step 3：贪心分配（一对一或多对一匹配）

  // 音频文件可能覆盖多段视频（一个长录音 → 多个短视频）
  // 按置信度降序排列
  candidates.sortBy(c => -c.confidence)

  matched_pairs = []
  for c in candidates:
    if c.video 未被匹配 或 已匹配但置信度更低:
      matched_pairs.add(c)
      // 注意：同一个音频可以被多个视频匹配（不同时间段）

Step 4：验证匹配质量

  For 每对匹配:
    验证偏移一致性：
    - 提取所有匹配窗口的偏移量
    - 计算标准差
    - 如果标准差 > 阈值 → 标记为"低置信度"
```

#### computeMatchScore 详细算法

```dart
/// 计算视频和音频的字幕匹配分数
MatchScore computeMatchScore(
  Map<String, WindowInfo> videoFps,
  Map<String, WindowInfo> audioFps,
) {
  int matchedCount = 0;
  List<int> offsets = [];

  for (final vText in videoFps.keys) {
    // 精确匹配
    if (audioFps.containsKey(vText)) {
      matchedCount++;
      final vStart = videoFps[vText]!.subtitles.first.timelineStartMs;
      final aStart = audioFps[vText]!.subtitles.first.timelineStartMs;
      offsets.add(vStart - aStart);
      continue;
    }

    // 模糊匹配（应对 ASR 微小差异）
    for (final aText in audioFps.keys) {
      final similarity = levenshteinSimilarity(vText, aText);
      if (similarity >= 0.85) {  // 85% 相似度阈值
        matchedCount++;
        final vStart = videoFps[vText]!.subtitles.first.timelineStartMs;
        final aStart = audioFps[aText]!.subtitles.first.timelineStartMs;
        offsets.add(vStart - aStart);
        break;  // 找到一个足够好的匹配就停
      }
    }
  }

  if (matchedCount < 3) {
    return MatchScore(confidence: 0, offset: 0, matchedCount: 0);
  }

  // 置信度 = 匹配窗口数 / 视频总窗口数
  final confidence = matchedCount / videoFps.length;

  // 偏移量 = 匹配窗口偏移的中位数（鲁棒估计）
  offsets.sort();
  final medianOffset = offsets[offsets.length ~/ 2];

  // 偏移一致性验证
  final offsetStdDev = _stdDev(offsets);
  final isConsistent = offsetStdDev < 3000;  // 3 秒容差

  return MatchScore(
    confidence: isConsistent ? confidence : confidence * 0.5,
    offset: medianOffset,
    matchedCount: matchedCount,
    isConsistent: isConsistent,
  );
}
```

#### 关键参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| window_size | 3 | 滑动窗口大小（取连续 3 条字幕） |
| min_match_count | 3 | 最少匹配窗口数（低于此数认为不匹配） |
| similarity_threshold | 0.85 | Levenshtein 相似度阈值 |
| confidence_high | 0.90 | 高置信度阈值（绿色） |
| confidence_medium | 0.70 | 中置信度阈值（黄色） |
| offset_consistency_ms | 3000 | 偏移一致性容差（毫秒） |

### 4.3 音频裁切算法

匹配完成后，根据每对视频-音频的偏移量裁切音频：

```dart
/// 为每个匹配的视频创建对应的音频片段
List<TimelineClip> createAudioClips(List<MatchPair> pairs) {
  final audioClips = <TimelineClip>[];

  for (final pair in pairs) {
    final video = pair.videoClip;
    final audio = pair.audioFile;

    // 音频源文件中的起始位置 = 偏移量
    final sourceStartMs = pair.offset.abs();

    // 裁切长度 = 视频长度（音频适配视频）
    final durationMs = video.durationMs;

    // 检查音频文件是否足够长
    if (sourceStartMs + durationMs > audio.totalDurationMs) {
      // 音频不够长，截断到音频末尾
      final actualDuration = audio.totalDurationMs - sourceStartMs;
      if (actualDuration <= 0) continue;  // 完全不够，跳过

      audioClips.add(TimelineClip(
        filePath: audio.filePath,
        fileName: audio.fileName,
        timelineStartMs: video.timelineStartMs,  // 和视频对齐
        durationMs: actualDuration,
        sourceStartMs: sourceStartMs,
        mediaIndex: -1,
      ));
    } else {
      audioClips.add(TimelineClip(
        filePath: audio.filePath,
        fileName: audio.fileName,
        timelineStartMs: video.timelineStartMs,  // 和视频对齐
        durationMs: durationMs,
        sourceStartMs: sourceStartMs,
        mediaIndex: -1,
      ));
    }
  }

  return audioClips;
}
```

### 4.4 时间线构建

```dart
/// 构建 ASR 合板时间线
TimelineProject buildAsrTimeline(
  List<File> videoFiles,
  List<File> audioFiles,
  List<MatchPair> matchPairs,
  List<TimelineClip> videoSubtitles,  // 视频 ASR 字幕
) {
  // 1. 视频轨道：紧凑排列
  int cursor = 0;
  final videoClips = <TimelineClip>[];
  for (final vf in videoFiles) {
    final duration = getVideoDuration(vf);
    videoClips.add(TimelineClip(
      filePath: vf.path,
      fileName: path.basename(vf.path),
      timelineStartMs: cursor,
      durationMs: duration,
      mediaIndex: videoClips.length,
    ));
    cursor += duration;
  }

  // 2. 音频轨道：根据匹配结果裁切
  final audioClips = createAudioClips(matchPairs);

  // 3. 字幕轨道：视频 ASR 字幕跟随视频位置
  final subtitleClips = <TimelineClip>[];
  for (final vs in videoSubtitles) {
    subtitleClips.add(TimelineClip(
      filePath: '',
      fileName: '',
      timelineStartMs: vs.timelineStartMs,
      durationMs: vs.durationMs,
      text: vs.text,
      mediaIndex: -1,
    ));
  }

  return TimelineProject(
    videoTrack: TimelineTrack(type: TrackType.video, clips: videoClips),
    audioTracks: [TimelineTrack(
      type: TrackType.audio,
      clips: audioClips,
      linkedSubtitleTrack: TimelineTrack(
        type: TrackType.subtitle,
        clips: subtitleClips,
      ),
    )],
    durationMs: cursor,
    isSyncedProject: true,
  );
}
```

---

## 五、数据模型设计

### 5.1 新增模型

#### AsrProject（ASR 合板工程）

```dart
/// ASR 合板工程
class AsrProject {
  final String id;               // UUID
  String name;                    // 工程名称
  String? videoDirectory;         // 视频目录路径
  String? audioDirectory;         // 音频目录路径
  List<String> videoFiles;        // 视频文件路径列表
  List<String> audioFiles;        // 音频文件路径列表
  AsrProjectStatus status;        // 工程状态
  String? asrLanguage;            // ASR 语言设置
  String? asrModel;               // ASR 模型设置
  DateTime createdAt;
  DateTime updatedAt;

  // 识别结果（JSON序列化存储）
  Map<String, List<TimelineClip>>? videoSubtitles;  // 视频 ASR 字幕
  Map<String, List<TimelineClip>>? audioSubtitles;  // 音频 ASR 字幕

  // 匹配结果
  List<MatchPair>? matchPairs;

  // 生成的时间线ID（创建后关联）
  String? timelineProjectId;
}

enum AsrProjectStatus {
  empty,        // 空工程，未添加素材
  ready,        // 已添加素材，待识别
  recognizing,  // ASR 识别中
  recognized,   // ASR 识别完成，待匹配
  matched,      // 匹配完成，待创建时间线
  completed,    // 时间线已创建
  error,        // 出错
}
```

#### MatchPair（匹配对）

```dart
/// 视频-音频匹配对
class MatchPair {
  final String videoFilePath;     // 视频文件路径
  final String audioFilePath;     // 音频文件路径
  final double confidence;        // 匹配置信度 0.0-1.0
  final int offsetMs;             // 音频偏移量（视频时间 - 音频时间）
  final int matchedWindowCount;   // 匹配的窗口数
  final int totalWindowCount;     // 视频总窗口数
  final bool isConsistent;        // 偏移是否一致
  final bool isUserConfirmed;     // 用户是否确认
  final bool isManualMatch;       // 是否手动匹配
}
```

### 5.2 数据库表设计

```sql
-- ASR 合板工程表
CREATE TABLE asr_projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  video_directory TEXT,
  audio_directory TEXT,
  video_files TEXT,           -- JSON 数组
  audio_files TEXT,           -- JSON 数组
  status TEXT NOT NULL,       -- AsrProjectStatus 枚举值
  asr_language TEXT DEFAULT 'chinese',
  asr_model TEXT DEFAULT 'ggml-medium.bin',
  video_subtitles TEXT,       -- JSON: Map<filePath, List<TimelineClip>>
  audio_subtitles TEXT,       -- JSON: Map<filePath, List<TimelineClip>>
  match_pairs TEXT,           -- JSON: List<MatchPair>
  timeline_project_id TEXT,   -- 关联的时间线项目ID
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

---

## 六、新增文件清单

### 6.1 新增文件

| 文件路径 | 说明 | 预估代码量 |
|----------|------|-----------|
| `lib/screens/asr_project_list_screen.dart` | ASR 工程列表页（卡片网格） | ~300 行 |
| `lib/screens/asr_project_detail_screen.dart` | ASR 工程操作页（4步骤） | ~800 行 |
| `lib/services/asr_match_service.dart` | ASR 字幕上下文匹配算法 | ~350 行 |
| `lib/services/asr_project_service.dart` | ASR 工程管理（CRUD + 状态管理） | ~200 行 |
| `lib/models/asr_project.dart` | AsrProject + MatchPair 模型 | ~150 行 |
| `lib/widgets/asr/asr_progress_card.dart` | ASR 识别进度卡片组件 | ~100 行 |
| `lib/widgets/asr/match_result_card.dart` | 匹配结果卡片组件 | ~120 行 |
| `lib/widgets/asr/subtitle_compare_dialog.dart` | 字幕对比对话框 | ~150 行 |
| `lib/widgets/asr/timeline_preview.dart` | 简化版时间线预览组件 | ~180 行 |

### 6.2 需修改的文件

| 文件路径 | 修改内容 | 预估改动量 |
|----------|---------|-----------|
| `lib/screens/main_shell.dart` | NavigationRail 从 4 项改为 5 项 | ~10 行 |
| `lib/services/database_service.dart` | 新增 asr_projects 表 | ~20 行 |
| `lib/services/speech_recognition_service.dart` | 添加批量识别接口 | ~50 行 |
| `lib/state/app_state.dart` | 添加 ASR 工程相关状态 | ~30 行 |

### 6.3 不修改的文件

- `clip_screen.dart` — 不改动（通过传参接收 TimelineProject）
- `home_screen.dart` — 不改动
- `timeline_panel.dart` — 不改动
- 所有现有 services — 不改动（新增服务独立调用）

---

## 七、扩展功能（超出核心诉求）

### 7.1 智能匹配策略

除了基本的"滑动窗口文本匹配"，增加以下策略：

#### 策略 A：时间码辅助验证（增强置信度）
```
如果视频和音频都有源时间码：
  1. 先用 ASR 字幕匹配得到候选对
  2. 用时间码验证偏移量是否合理
  3. 时间码和字幕匹配一致 → 置信度提升到 99%
  4. 时间码和字幕匹配冲突 → 提示用户选择信任哪个
```

#### 策略 B：波形指纹辅助（可选，Phase 2）
```
当字幕匹配失败（静音视频/纯音乐等场景）：
  1. 用 FFmpeg 从视频提取音频轨道
  2. 生成音频指纹（能量峰值模式）
  3. 与独立录音的音频指纹交叉相关
  4. 找到最佳偏移
  5. 精度较低但可以处理无语音场景
```

#### 策略 C：部分匹配（长音频覆盖多段视频）
```
一个 2 小时的录音可能覆盖多个短视频：
  1. 长音频的 ASR 字幕按时间分段
  2. 每段独立与视频字幕匹配
  3. 支持一对多匹配（一个音频 → 多个视频）
  4. 需要处理音频段不重叠的约束
```

### 7.2 工程管理功能

- **工程模板**：保存常用的 ASR 配置（语言、模型、匹配阈值）为模板
- **批量工程**：同时创建多个工程，共享同一套音频目录
- **工程导入/导出**：将工程配置和匹配结果导出为 JSON，可在其他设备导入
- **工程历史**：记录每次匹配的结果，支持回退到之前的匹配方案

### 7.3 ASR 缓存管理

```
识别缓存策略：
  - ASR 结果按 (filePath + fileSize + modifiedTime) 生成哈希键
  - 缓存存储在应用的临时目录中
  - 文件未修改 → 直接使用缓存，跳过 ASR
  - 设置页面增加"清除 ASR 缓存"按钮
  - 显示缓存占用空间
```

### 7.4 匹配结果后处理

- **静音检测**：在音频裁切边界检测是否在语音中，如果在则自动扩展到最近静音段
- **重叠检测**：检测同一音频文件的不同裁切段是否重叠，如果重叠则提示用户
- **音量归一化**：创建时间线后自动检测视频自带音频和独立录音的音量差异，提示是否需要调整

### 7.5 导出选项扩展

除了现有的 FCP7 XML 导出：
- **AAF 导出**：兼容 Pro Tools 等音频工作站
- **EDL 导出**：兼容传统剪辑系统
- **Premiere Pro 项目文件**：直接生成 .prproj
- **批量导出**：每个匹配对单独导出一个 XML/AAF

---

## 八、实施路线

### Phase 1：基础框架（核心功能）

**目标**：完成 ASR 合板的基础流程，可以工作

| 步骤 | 内容 | 预估代码量 |
|------|------|-----------|
| 1.1 | 新增数据模型 `AsrProject`、`MatchPair` | ~150 行 |
| 1.2 | 数据库新增 `asr_projects` 表 | ~20 行 |
| 1.3 | `AsrProjectService`：工程 CRUD + 状态管理 | ~200 行 |
| 1.4 | `AsrMatchService`：字幕上下文匹配算法 | ~350 行 |
| 1.5 | `AsrProjectListScreen`：工程列表页（卡片网格） | ~300 行 |
| 1.6 | `AsrProjectDetailScreen`：Step 1-4 完整流程 | ~800 行 |
| 1.7 | `MainShell` 新增标签页 | ~10 行 |
| 1.8 | `SpeechRecognitionService` 添加批量识别接口 | ~50 行 |

**合计**：~1,880 行新增代码

### Phase 2：体验优化

| 步骤 | 内容 |
|------|------|
| 2.1 | 匹配结果卡片组件优化（动画、拖拽排序） |
| 2.2 | 字幕对比对话框（左右对照，高亮差异） |
| 2.3 | 时间线预览组件（简化版可视化） |
| 2.4 | ASR 缓存管理 |
| 2.5 | 进度预估优化（基于历史数据估算剩余时间） |

### Phase 3：高级功能

| 步骤 | 内容 |
|------|------|
| 3.1 | 时间码辅助验证 |
| 3.2 | 长音频分段匹配（一对多） |
| 3.3 | 波形指纹辅助匹配 |
| 3.4 | 静音检测边界优化 |
| 3.5 | 工程模板和批量工程 |

---

## 九、错误处理与边界情况

### 9.1 可能的问题及处理

| 场景 | 处理方式 |
|------|---------|
| 视频没有音频轨道 | ASR 跳过该文件，标记为"无音频轨道，无法识别" |
| 音频文件极短（<5秒） | ASR 仍尝试识别，但可能返回 0 条字幕，标记为"音频过短" |
| 所有视频都没匹配到 | 提示"未找到匹配，请检查视频和音频是否来自同一次拍摄" |
| 音频文件损坏无法识别 | 标记为错误，不影响其他文件继续 |
| ASR 模型未下载 | 弹出提示，引导到设置页面下载模型 |
| 磁盘空间不足 | 在开始前检查预估空间需求 |
| 匹配窗口数不足（视频太短） | 降低最少匹配数要求，但标记为低置信度 |
| 两个音频都匹配同一视频 | 取置信度更高的，另一个标记为备选 |

### 9.2 用户提示规范

```
错误级别颜色：
  - 红色：阻断性错误（无法继续）
  - 黄色：警告（可以继续但需注意）
  - 蓝色：信息提示
  - 绿色：成功/完成

提示位置：
  - Step 2（识别中）：进度条变红 + 错误文件名 + 原因
  - Step 3（匹配）：未匹配文件红色标记 + 原因说明
  - Step 4（创建时间线）：确认前汇总所有警告
```

---

## 十、性能预估

### 10.1 ASR 识别时间

基于 v2.9.0 的实测数据（RTX 4070 Ti SUPER GPU）：

| 音频时长 | 识别耗时 | 字幕数量（中文） |
|----------|---------|----------------|
| 1 分钟 | ~2 秒 | ~15 条 |
| 5 分钟 | ~10 秒 | ~80 条 |
| 30 分钟 | ~1 分钟 | ~450 条 |
| 1 小时 | ~2 分钟 | ~900 条 |
| 2 小时 | ~4 分钟 | ~1800 条 |

**典型场景**（12 个视频共 2 小时 + 4 个音频共 2 小时 = 4 小时音频）：
- GPU 模式：约 8 分钟完成全部 ASR 识别
- CPU 模式：约 60-90 分钟（建议提示用户使用 GPU）

### 10.2 匹配计算时间

字幕匹配是纯内存计算，不涉及 IO：

| 规模 | 耗时 |
|------|------|
| 10 视频 + 3 音频，共 5000 条字幕 | <1 秒 |
| 50 视频 + 10 音频，共 20000 条字幕 | <5 秒 |
| 100 视频 + 20 音频，共 50000 条字幕 | <30 秒 |

### 10.3 内存占用

- ASR 识别期间：WAV 临时文件（每个约 10MB/分钟）
- 匹配期间：字幕数据在内存中，每 1000 条字幕约 100KB
- 峰值内存：约 500MB（含 Flutter 框架）

---

## 十一、验收标准

### 核心功能验收

| # | 验收项 | 标准 |
|---|--------|------|
| 1 | 工程创建 | 可创建/删除 ASR 合板工程，卡片正确显示 |
| 2 | 素材导入 | 可选择视频目录和音频目录，文件列表正确显示 |
| 3 | ASR 识别 | 点击开始后逐个文件识别，进度实时更新 |
| 4 | 上下文匹配 | 识别完成后自动匹配，高置信度匹配正确 |
| 5 | 匹配确认 | 可查看字幕对比，可手动调整低置信度匹配 |
| 6 | 创建时间线 | 音频裁切到视频下方，长度适配 |
| 7 | 跳转编辑器 | 可从 ASR 合板页跳转到 ClipScreen 继续编辑 |
| 8 | 导出 XML | 生成的 FCP7 XML 可被 Premiere/DaVinci 正确导入 |

### 非功能验收

| # | 验收项 | 标准 |
|---|--------|------|
| 9 | 识别中断恢复 | 取消后重新开始，已识别文件不重复识别 |
| 10 | 错误处理 | 单个文件失败不影响其他文件 |
| 11 | 大文件支持 | 2 小时音频可正常识别和匹配 |
| 12 | 工程持久化 | 关闭应用重新打开，工程数据不丢失 |

---

## 十二、与现有系统的关系

### 12.1 复用的现有模块

| 模块 | 复用方式 |
|------|---------|
| `SpeechRecognitionService` | 直接调用，新增批量识别接口 |
| `SubtitleService` / `SrtParserService` | 解析 ASR 生成的 SRT |
| `MediaScanService` | 扫描目录下的视频/音频文件 |
| `FfmpegPathService` / `WhisperPathService` | 工具路径解析 |
| `TimecodeService` | 时间码提取（可选增强） |
| `ExportService` | FCP7 XML 导出 |
| `TrimService` | 修剪空白间隙 |
| `ContextMatchingService` | Levenshtein 相似度计算（复用核心算法） |
| `DatabaseService` | 数据库操作 |

### 12.2 新模块独立性

ASR 合板功能的代码**完全独立**于现有合板功能：
- 不修改 `clip_screen.dart`（仅通过参数传入 TimelineProject）
- 不修改 `MultiPointSyncService`（匹配算法完全重写）
- 不修改 `AutoSyncService`（流程完全不同）
- 通过数据库 `asr_projects` 表独立存储工程数据

---

## 附录 A：文件命名规范

```
新增文件统一使用 asr_ 前缀：
  - asr_project_list_screen.dart
  - asr_project_detail_screen.dart
  - asr_match_service.dart
  - asr_project_service.dart
  - asr_project.dart（模型）

组件放在 widgets/asr/ 目录：
  - asr_progress_card.dart
  - match_result_card.dart
  - subtitle_compare_dialog.dart
  - timeline_preview.dart
```

## 附录 B：状态流转图

```
                    ┌──────────┐
                    │  empty   │ 新建工程
                    └────┬─────┘
                         │ 添加视频和音频目录
                    ┌────▼─────┐
                    │  ready   │
                    └────┬─────┘
                         │ 点击"开始 ASR 识别"
                    ┌────▼──────┐
                    │recognizing│ ← 可取消回到 ready
                    └────┬──────┘
                         │ 全部识别完成
                    ┌────▼──────┐
                    │recognized │ ← 自动执行匹配
                    └────┬──────┘
                         │ 匹配完成
                    ┌────▼─────┐
                    │ matched  │ ← 用户确认
                    └────┬─────┘
                         │ 点击"创建时间线"
                    ┌────▼─────┐
                    │completed │
                    └──────────┘

         任何阶段 ──→ error（出错，可重试）
```
