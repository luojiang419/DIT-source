# 进度快照 15 — ASR合板新增字幕审阅与匹配步骤

**日期**: 2026-04-17
**版本**: v3.9.1

---

## 已完成内容

### 功能调整
ASR合板页面从 4 步扩展为 5 步，新增「字幕匹配」步骤。

**新流程**：
- Step 0：导入素材
- Step 1：ASR 识别
- Step 2（新）：字幕匹配 — 双栏显示视频/音频字幕，支持搜索、手动匹配、全自动匹配
- Step 3：匹配确认 — 显示匹配结果详情
- Step 4：创建时间线

### 修改的文件
- `lib/screens/asr_project_detail_screen.dart`

### 具体改动

#### 1. 步骤框架更新
- 注释更新为「5步骤引导」
- 步骤指示器标签：`['导入素材', 'ASR 识别', '字幕匹配', '匹配确认', '创建时间线']`
- `_restoreStep()`：`matched`/`completed` → Step 3（原 Step 2）
- `_buildCurrentStep()` 路由更新为 5 步

#### 2. 新增状态变量
- `_searchKeyword` — 搜索关键词
- `_selectedVideoPath` / `_selectedAudioPath` — 手动匹配选中
- `_expandedVideoFiles` / `_expandedAudioFiles` — 文件展开/折叠

#### 3. 新增方法
- `_buildStep3SubtitleReview()` — 字幕审阅页面（搜索栏 + 双栏 + 底部按钮）
- `_buildFileColumn()` — 单栏文件/字幕列表组件
- `_formatMs()` — 毫秒格式化为 MM:SS
- `_tryCreateManualMatch()` — 手动匹配逻辑
- `_autoMatch()` — 全自动匹配
- `_saveMatchResults()` — 保存匹配结果到数据库

#### 4. 识别流程调整
- `_startRecognition()` 识别完成后不再自动执行匹配，跳转到 Step 2（字幕匹配）

#### 5. 方法重命名
- `_buildStep3Match()` → `_buildStep4MatchConfirm()`
- `_buildStep4Timeline()` → `_buildStep5Timeline()`
- 导航引用全部更新

### 备份
- `backup/v3.9.1_pre-subtitle-review_*.tar.gz`

---

## 当前状态
- 编译通过，dist/v3.9.1 已更新

## 待办清单
- [ ] 运行测试完整 5 步流程

## 下一步
- 测试新步骤功能
