# AG Pocket Apple Watch — 产品需求与 watchOS UX 规范 (`W01`–`W08`, v1.0)

- **状态**：Normative Spec（与 iOS `v2.0 / v2.33+` 伴侣端及 `AntigravityData` 保持一致）
- **目标平台**：`watchOS 11.0+`（Xcode 16+ / Swift 6，单 Target 原生 SwiftUI App：`AGPocketWatch`）
- **基线视口（视觉验收基准）**：Apple Watch Series 10 (46mm) `416×496 px @2x`（`208×248 pt`），自适应兼容 40mm / 41mm / 42mm / 44mm / 45mm / 46mm / 49mm Ultra
- **设计稿基准**：[`specs/watch/reference/W01_SESSIONS.png` .. `W08_APPROVAL_NOTIFICATION.png`](./reference/)

---

## 1. 产品定位与核心原则（"抬腕 2 秒决策 · 危险分层 · 随时接力 iPhone"）

Apple Watch 不是把 iPhone 完整 IDE / 聊天界面强行缩小到手表屏幕，而是面向 **离开工位 / 通勤 / 会议间隙** 的高频微交互场景，聚焦 4 个核心闭环：

1. **扫一眼掌握全局进度（Glanceable Status）**：抬腕即可看到哪个 Agent 在等你批准（暖琥珀脉冲点）、哪个在云端/本机运行（旋转蓝弧）、哪个已完成并产生多少代码增删（`+42 −31`）。
2. **一按/双指互点解除阻塞（Low-Friction Wrist Action）**：针对需要审批的终端命令，提供支持 watchOS 11 **双指互点（Double Tap / `.handGestureShortcut(.primaryAction)`）** 的 `Allow`、一键 `Deny` 与 `Reply by voice`，直接从手表通知或会话流放行。
3. **语音优先的微指令回复（Voice-First Steering）**：从首页或对话流右下角蓝色麦克风按钮一键进入语音输入，支持切换目标会话（`To: Rate limiter ⌄`）、实时转写（已确认高亮 + 尾部识别词淡灰）、声波动画与双指互点发送。
4. **代码改动智能分层审阅（Intent-Grouped Diff Triage + Handoff）**：
   - **少量改动（`≤ 6` 文件）**：展示简洁的文件级卡片（`A`/`M`/`D` 徽标 + 一句话意图摘要 + `+N/-M`）并允许在手表端一键 `Accept all`。
   - **大量改动（`> 6` 文件）**：禁止盲目一键全部接受；自动切换为 **按意图分组视图**——将高风险/高影响改动置顶为 `WORTH A LOOK`（暖琥珀底色卡片，如依赖删减 `go.mod`、审计日志字段变更 `audit/writer.go`），将其余机械性变更折叠为 `GROUPED` 聚类卡片（如 `16 · Call sites → updated · Mechanical · 9 dirs`），并把底部主按钮替换为蓝底 `iPhone` 接力胶囊，一键通过 Handoff + `WatchConnectivity` 切到 iPhone 查看完整行级 Diff（`UE12`）。

---

## 2. OLED 视觉与交互规范

### 2.1 精确色彩 Token（采样自 8 张 `@2x` 基准稿）

| 语义 Token | Hex 值 | 用途 |
| :--- | :--- | :--- |
| `canvas` | `#000000` | 纯黑 OLED 背景（与表壳无边界融合，极限省电） |
| `card` | `#1C1C1F` | 会话卡片、设备卡片、产物摘要卡片、分组卡片 |
| `cardOffline` | `#121214` | 离线设备弱化卡片 |
| `cardSelectedDevice` | `#1A2435` | 当前选中在线设备背景（配 `1.5pt` `#8DB8FF` 描边） |
| `cardWorthALook` | `#1E1A14` | 大量改动中 `WORTH A LOOK` 高关注文件暖棕暗底 |
| `elevatedButton` | `#26262B` | 语音气泡、次级胶囊按钮（`Deny`/`Reply by voice`）、iPhone 图标圆钮、停止圆钮、序号徽标 |
| `topChromeCircle` | `#292929` | 顶部圆形返回 `<`、关闭 `×`、设备入口按钮（`34pt`） |
| `accentPeriwinkle` | `#8DB8FF` | 主 CTA（麦克风、See changes、Accept all、iPhone、Send）、运行态蓝弧与选中态 |
| `inkOnPeriwinkle` | `#0A1A33` | 蓝色主 CTA 上的深色高对比文字与图标 |
| `amber` | `#F2B866` | 待批准标题、主审批按钮 `Allow`、等待态圆点与 `WORTH A LOOK` 分组标题（配 `#2A1A00` 按钮文字、`#E3CFA8` 风险副标题、`#473B2D` 光晕） |
| `emerald` | `#6FD8A6` | 在线状态、代码新增 `+N`、性能指标高亮（如 `3.8 ms`）、新增文件 `A` 徽标前景 |
| `coralRed` | `#F59595` | 代码删除 `−N` / `-N`、删除文件 `D` 徽标前景 |

### 2.2 布局、触控与系统交互不变量

- **水平安全边距**：主内容区 `8pt`–`10pt`（通知页 `12pt`），任意屏幕尺寸（40mm–49mm）下 **0px 水平溢出**、无文字裁切重叠。
- **核心触控热区**：顶部圆形按钮 `34×34pt`；底部主 CTA 高度 `38pt`–`40pt`（胶囊全宽或与左侧 `38pt` 圆形辅助钮并排）；会话/设备卡片高度 `≥ 48pt`。
- **Double Tap（watchOS 11+）**：主动作按钮（`W07` 的 `Send`、`W08` 的 `Allow`、`W05` 的 `Accept all`、`W06` 的 `iPhone`）绑定 `.handGestureShortcut(.primaryAction)`。
- **触觉反馈（Haptics）**：导航/切换设备播放 `.click`，批准/发送/全部接受播放 `.success`，离线拒绝播放 `.failure`，等待审批提示播放 `.notification`。

---

## 3. 8 大核心画面需求矩阵（`W01`–`W08`）

| 画面 ID | 中文名称 | 参考设计稿 | 核心元素与交互需求 |
| :--- | :--- | :--- | :--- |
| **`W01_SESSIONS`** | Watch · 会话列表 | `reference/W01_SESSIONS.png` | 顶部左圆钮（当前设备图标 + 右上角翠绿/灰色在线圆点，点按进入 `W02`）、右蓝圆钮（麦克风，点按进入 `W07`）；标题行 `Agents` + 右侧当前设备名（如 `MacBook Pro`）；会话卡片列表按优先级排序（待批准暖琥珀光晕点 + `Approve command` → 运行中旋转蓝弧 + `Cloud · 2 of 5` → 已完成蓝点 + `Done · +42 −31`）；点按任意卡片进入 `W03`；无会话时显示同步引导卡。 |
| **`W02_DEVICES`** | Watch · 在线设备 | `reference/W02_DEVICES.png` | 顶部返回圆钮 `<` + 大标题 `Devices`；展示本机配对设备（`laptopcomputer`/`desktopcomputer`）与 `Cloud` 运行时；当前选中设备呈 `#1A2435` 底色 + `#8DB8FF` 描边 + 右侧对勾，在线副标题翠绿 `Online · N running`，离线设备弱化底色 `#121214` + `Offline · seen 3h ago`；点按在线设备切换主机作用域、同步给 iPhone 并自动返回 `W01`；点按离线设备给失败触觉反馈与 Toast 提示。 |
| **`W03_CHAT_STREAM`** | Watch · 对话流 | `reference/W03_CHAT_STREAM.png` | 顶部 `<` + 会话标题（如 `Rate limiter`）；状态行（蓝弧 + `Step 6 of 7 · Running`；若处于待批准态则展示暖琥珀 `Approve command` 横幅可直达 `W08`）；右对齐深灰语音用户气泡（含麦克风图标）+ 左对齐 Agent 精简回复正文；可点击的 `Walkthrough` 产物卡片（`doc.text` 蓝底小图标 + `3 key points` + `>`，跳转 `W04`）；可点击的变更统计胶囊（`+128 -14 · 4 files`，跳转 `W05`/`W06`）；右下角悬浮蓝色麦克风 FAB（打开针对当前会话的 `W07`）。 |
| **`W04_ARTIFACT_SUMMARY`** | Watch · 产物摘要 | `reference/W04_ARTIFACT_SUMMARY.png` | 顶部 `<` + 产物标题（`Walkthrough`，窄屏平滑截断）；加粗核心结论标题（如 `Per-tenant token bucket`）；1–N 条带圆形序号徽标的要点列表，支持行内等宽代码（`ratelimit.go`）与加粗翠绿性能指标（`3.8 ms`）；底部悬浮操作栏：左侧圆形 `iphone` 接力按钮（通过 Handoff/WCSession 在 iPhone 打开完整产物）+ 右侧蓝底 `See changes` 胶囊（跳转 `W05`/`W06`）。 |
| **`W05_CHANGED_FILES_COMPACT`** | Watch · 改动文件（少量） | `reference/W05_CHANGED_FILES_COMPACT.png` | 触发条件：`totalFiles <= 6`。顶部 `<` + `Changes`；副标题 `4 files · +128 -14`；逐文件卡片：左侧彩色单字状态块（`A` 绿 / `M` 蓝 / `D` 红）、中间等宽文件名 + 单行意图摘要、右侧垂直堆叠 `+96` / `-6`；底部悬浮操作栏：左侧圆形 `iphone` 接力钮 + 右侧蓝底 `Accept all` 胶囊（支持 Double Tap，点击后派发 `acceptAllChanges` 并切换为绿色 `Accepted`）。 |
| **`W06_CHANGED_FILES_GROUPED`** | Watch · 改动文件（大量，按意图分组） | `reference/W06_CHANGED_FILES_GROUPED.png` | 触发条件：`totalFiles > 6`。顶部 `<` + `Changes`；副标题 `23 files · +412 -198`；**分区 1 `WORTH A LOOK · N`**（暖琥珀标题 + `#1E1A14` 卡片，突出依赖文件/安全审计/大删改文件，配 `#E3CFA8` 风险原因说明）；**分区 2 `GROUPED · M`**（灰标题 + `#1C1C1F` 聚类卡片，左侧 `#2E2E34` 计数块 + 聚类标题 + `Mechanical · 9 dirs`，点击可在表端展开预览前 5 条路径）；右下角悬浮蓝底 `iPhone` 接力胶囊（引导在 iPhone 审阅完整行级 Diff）。 |
| **`W07_VOICE_INPUT`** | Watch · 语音输入 | `reference/W07_VOICE_INPUT.png` | 顶部左 `×` 关闭圆钮；目标会话选择胶囊 `To: Rate limiter ⌄`（点击可在活跃会话间循环切换）；实时转写大字区（已确认文本 `#F1F1F3` + 尾部实时词 `#8E8E98`；实机空草稿时调起 watchOS 原生听写/涂鸦输入框）；11 柱蓝色声波动画；提示语 `Double tap to send`；底部左侧圆形停止按钮（白方块，切换录音状态）+ 右侧蓝底 `↑ Send` 主按钮（支持 Double Tap，发送后乐观追加到对话流并同步 iPhone）。 |
| **`W08_APPROVAL_NOTIFICATION`** | Watch · 通知（待批准） | `reference/W08_APPROVAL_NOTIFICATION.png` | 双入口复用：既作为 watchOS 自定义可交互 Long-Look 通知（`AGPOCKET_APPROVAL_REQUEST`），也作为 App 内待批准确认弹窗。顶部品牌轨道徽标 + `Agents · now`；暖琥珀加粗标题 `Run this command?` + 上下文 `Rate limiter · step 5 of 7`；等宽命令卡片（如 `vegeta attack -rate=2000/s -duration=30s`）；垂直三按钮：暖琥珀 `Allow`（带手势图标，绑定 Double Tap）、深灰 `Deny`、深灰 `Reply by voice`（关闭审批卡并直接打开 `W07` 语音回复）。 |
