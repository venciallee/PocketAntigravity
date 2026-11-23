# AG Pocket Apple Watch — 产品需求与 watchOS UX 规范 (`W01`–`W08`, v1.1)

- **状态**：Normative Spec（与 iOS `v2.0 / v2.33+` 伴侣端及 `AntigravityData` 保持一致）
- **目标平台**：`watchOS 11.0+`（Xcode 16+ / Swift 6，单 Target 原生 SwiftUI App：`AGPocketWatch`）
- **基线视口（视觉验收基准）**：Apple Watch Series 10 (46mm) `416×496 px @2x`（`208×248 pt`），自适应兼容 40mm / 41mm / 42mm / 44mm / 45mm / 46mm / 49mm Ultra
- **设计稿基准**：[`specs/watch/reference/W01_SESSIONS.png` .. `W08_APPROVAL_NOTIFICATION.png`](./reference/)

---

## 1. 产品定位与六大铁律（"Watch 只做三件事：看状态、批准、语音发任务"）

Apple Watch 不做袖珍 IDE、不展示源代码行级 Diff，只聚焦 **看状态、批准、语音发任务** 三件高频抬腕微交互，严格执行以下 6 条产品边界：

1. **顶部入口分工明确**：首页（`W01`）**左上角 = 当前设备（点开切换）**，**右上角 = 语音新建任务**（默认 `To: New task ⌄`，可在目标选择器中切换为回复已有会话；而对话流 `W03` 右下角麦克风 FAB 与通知 `W08` 的 `Reply by voice` 默认锁定回复当前会话）。
2. **产物只给摘要**：`W04` 严格限制为 **标题 + `≤ 3` 条要点 + 一个主操作**（Walkthrough 为 `See changes`，Implementation Plan 为 `Proceed`），配左下角紧凑 `iPhone` 接力图标。
3. **不显示代码**：`W05` / `W06` 绝不渲染源码 Diff 行；只列 **改了哪些文件 + 每个文件一句话摘要（配 `A`/`M`/`D` 状态标记）**。
4. **风险与规模双重门禁（`≤ 5` 文件且无风险项）**：
   - **`≤ 5` 个文件且无风险项**：进入 `W05` 紧凑文件列表，允许在手表一键 `Accept all`（受腕上解锁校验保护）。
   - **`> 5` 个文件 或 存在任意风险项**（即使文件数 `≤ 5`，只要触及依赖清单如 `go.mod`/`Package.swift`、安全鉴权/审计日志如 `audit/writer.go`、数据库迁移或大额删除）：自动进入 `W06` 分层审阅——**先列 `WORTH A LOOK`（值得一看）**，**其余按意图折叠成组（`GROUPED`）**，禁止在手表出现 `Accept all`，**主操作改为去 `iPhone` 审**（Handoff + `WatchConnectivity` 直达 iPhone `UE12`）。
5. **Double Tap 手势 = 主操作（`Allow` / `Send` / `Proceed`）**：基于 watchOS 11+ `.handGestureShortcut(.primaryAction)`，主操作按钮均支持单手双指互点触发（`W08` 的 `Allow`、`W07` 的 `Send`、`W04` 的 `Proceed` / `See changes`、`W05` 的 `Accept all`、`W06` 的 `iPhone`）。
6. **批准类操作要求手表已解锁且戴在腕上**：所有批准类操作（`W08` 的 `Allow`、`W04` 的 `Proceed`、`W05` 的 `Accept all`）在 Watch 侧必须通过 `LocalAuthentication` 的 **`LAPolicy.deviceOwnerAuthenticationWithWristDetection`** 实时校验（确认已设密码、当前已解锁且佩戴在腕上），并在 `WatchRemoteCommand.wristVerified == true` 时才允许 iPhone 端执行；未解锁、未设密码或离腕一律 Fail-Closed 拦截并提示 `Unlock Watch on wrist to approve`。

---

## 2. OLED 视觉与交互规范

### 2.1 精确色彩 Token（采样自 8 张 `@2x` 基准稿）

| 语义 Token | Hex 值 | 用途 |
| :--- | :--- | :--- |
| `canvas` | `#000000` | 纯黑 OLED 背景（与表壳无边界融合，极限省电） |
| `card` | `#1C1C1F` | 会话卡片、设备卡片、产物摘要卡片、分组卡片 |
| `cardOffline` | `#121214` | 离线设备弱化卡片 |
| `cardSelectedDevice` | `#1A2435` | 当前选中在线设备背景（配 `1.5pt` `#8DB8FF` 描边） |
| `cardWorthALook` | `#1E1A14` | `WORTH A LOOK` 高关注风险文件暖棕暗底 |
| `elevatedButton` | `#26262B` | 语音气泡、次级胶囊按钮（`Deny`/`Reply by voice`）、iPhone 图标圆钮、停止圆钮、序号徽标 |
| `topChromeCircle` | `#292929` | 顶部圆形返回 `<`、关闭 `×`、设备入口按钮（`34pt`） |
| `accentPeriwinkle` | `#8DB8FF` | 主 CTA（语音新建麦克风、See changes/Proceed、Accept all、iPhone、Send）、运行态蓝弧与选中态 |
| `inkOnPeriwinkle` | `#0A1A33` | 蓝色主 CTA 上的深色高对比文字与图标 |
| `amber` | `#F2B866` | 待批准标题、主审批按钮 `Allow`、等待态圆点与 `WORTH A LOOK` 分组标题（配 `#2A1A00` 按钮文字、`#E3CFA8` 风险副标题、`#473B2D` 光晕） |
| `emerald` | `#6FD8A6` | 在线状态、代码新增 `+N`、性能指标高亮（如 `3.8 ms`）、新增文件 `A` 徽标前景 |
| `coralRed` | `#F59595` | 代码删除 `−N` / `-N`、删除文件 `D` 徽标前景 |

### 2.2 布局、触控与系统交互不变量

- **水平安全边距**：主内容区 `8pt`–`10pt`（通知页 `12pt`），任意屏幕尺寸（40mm–49mm）下 **0px 水平溢出**、无文字裁切重叠。
- **核心触控热区**：顶部圆形按钮 `34×34pt`；底部主 CTA 高度 `38pt`–`40pt`（胶囊全宽或与左侧 `38pt` 圆形辅助钮并排）；会话/设备卡片高度 `≥ 48pt`。
- **Double Tap（watchOS 11+）**：主动作按钮（`Allow` / `Send` / `Proceed` / `See changes` / `Accept all` / `iPhone`）统一绑定 `.handGestureShortcut(.primaryAction)`。
- **腕上解锁门禁**：`Allow` / `Proceed` / `Accept all` 均通过 `WatchWristUnlockGuard`（`LAPolicy.deviceOwnerAuthenticationWithWristDetection`）把关，失败时播放 `.failure` 触觉并保留待审批状态不派发远端指令。
- **触觉反馈（Haptics）**：导航/切换设备播放 `.click`，批准/新建任务/发送/全部接受播放 `.success`，离线拒绝或离腕拦截播放 `.failure`，等待审批提示播放 `.notification`。

---

## 3. 8 大核心画面需求矩阵（`W01`–`W08`）

| 画面 ID | 中文名称 | 参考设计稿 | 核心元素与交互需求 |
| :--- | :--- | :--- | :--- |
| **`W01_SESSIONS`** | Watch · 会话列表 | `reference/W01_SESSIONS.png` | **左上角** = 当前设备图标 + 在线绿/灰点（点开进入 `W02` 切换设备）；**右上角** = 蓝底麦克风（点开进入 `W07` **语音新建任务**，默认 `To: New task`）；标题行 `Agents` + 当前设备名；会话卡片列表按优先级排序（待批准暖琥珀光晕点 → 运行中旋转蓝弧 → 已完成 `+N −M`）；点按任意卡片进入 `W03`。 |
| **`W02_DEVICES`** | Watch · 在线设备 | `reference/W02_DEVICES.png` | 顶部返回圆钮 `<` + 大标题 `Devices`；展示本机配对设备与 `Cloud` 运行时；当前选中设备 `#1A2435` + `#8DB8FF` 描边 + 右侧对勾；在线副标题翠绿 `Online · N running`，离线弱化 `#121214` + `Offline · seen 3h ago`；点按在线设备切换并自动返回 `W01`，点按离线设备提示拦截。 |
| **`W03_CHAT_STREAM`** | Watch · 对话流 | `reference/W03_CHAT_STREAM.png` | 顶部 `<` + 会话标题；状态行（`Step 6 of 7 · Running` 或待批准暖琥珀横幅直达 `W08`）；右对齐语音气泡 + 左对齐 Agent 精简回复；可点 `Walkthrough`/`Plan` 产物摘要卡（`≤ 3 key points`，跳转 `W04`）；可点变更统计胶囊（`+128 -14 · 4 files`，跳转 `W05`/`W06`）；右下悬浮麦克风 FAB（打开回复当前会话的 `W07`）。 |
| **`W04_ARTIFACT_SUMMARY`** | Watch · 产物摘要 | `reference/W04_ARTIFACT_SUMMARY.png` | 顶部 `<` + 产物标题（`Walkthrough` / `Plan`）；加粗核心结论标题 + **严格 `≤ 3` 条**带圆形序号徽标的要点（支持行内等宽文件名与翠绿指标高亮）；底栏左侧紧凑 `iPhone` 接力圆钮 + **单个主操作胶囊**（Walkthrough 为 `See changes`，Implementation Plan 为受腕上解锁保护的 `Proceed`，均支持 Double Tap）。 |
| **`W05_CHANGED_FILES_COMPACT`** | Watch · 改动文件（少量） | `reference/W05_CHANGED_FILES_COMPACT.png` | 触发条件：**`totalFiles <= 5` 且无任何风险项**。**不显示源代码**，仅展示 `A`/`M`/`D` 标记 + 文件名 + 一句话摘要 + `+/-` 统计；底栏左侧 `iPhone` 接力钮 + 右侧蓝底 `Accept all` 主按钮（支持 Double Tap 且需手表已解锁戴在腕上，通过后切换绿色 `Accepted`）。 |
| **`W06_CHANGED_FILES_GROUPED`** | Watch · 改动文件（大量或含风险项，按意图分组） | `reference/W06_CHANGED_FILES_GROUPED.png` | 触发条件：**`totalFiles > 5` 或 命中任意风险项**。**不显示源代码、禁止出现 `Accept all`**。**分区 1 `WORTH A LOOK · N`**（值得一看的高风险文件，暖琥珀标题 + `#1E1A14` 卡片 + 风险原因一句话）；**分区 2 `GROUPED · M`**（其余文件按意图折叠成组，点击可展开路径摘要）；主操作改为右下悬浮蓝底 **`iPhone` 接力胶囊**（支持 Double Tap，一键去 iPhone 审）。 |
| **`W07_VOICE_INPUT`** | Watch · 语音输入 | `reference/W07_VOICE_INPUT.png` | 顶部左 `×` 关闭；目标切换胶囊（从 `W01` 右上角进入默认 `To: New task ⌄`，从 `W03`/`W08` 进入默认 `To: <会话名> ⌄`，点击在 `New task` 与各活跃会话间循环切换）；大字实时转写（已确认高亮 + 尾部识别词淡灰）；11 柱声波动画；`Double tap to send` 提示；底栏停止圆钮 + `↑ Send` 主按钮（绑定 Double Tap，新建任务派发 `createVoiceTask`，回复会话派发 `sendVoiceReply`）。 |
| **`W08_APPROVAL_NOTIFICATION`** | Watch · 通知（待批准） | `reference/W08_APPROVAL_NOTIFICATION.png` | 复用为 watchOS 可交互 Long-Look 通知（`AGPOCKET_APPROVAL_REQUEST`）及 App 内待批准确认页。展示 `Agents · now`、暖琥珀 `Run this command?`、上下文与等宽命令摘要；三按钮：`Allow`（暖琥珀主操作，绑定 Double Tap 且强制校验手表已解锁戴在腕上）、`Deny`、`Reply by voice`（切入 `W07` 锁定当前会话）。 |
