# AG Pocket Apple Watch — 单元测试、交互式 E2E 与视觉验收测试计划 (v1.1)

## 1. 四层端到端验证策略

1. **Layer 1 — Watch ESDD 规范图谱、源码契约与无头交互式 E2E（`verification/verify_watch_esdd.py`，Linux & macOS 秒级运行）**
   - 校验 [`specs/watch/esdd-watch-ir.json`](./esdd-watch-ir.json)：12 个 OLED 色彩 Token、8 个画面状态（`W01`–`W08`）、8 张 `416×496px @2x` 参考设计稿、11 条导航转换边（BFS 校验 100% 可达）、8 条可执行断言（`WCLAIM-01`..`WCLAIM-08`）与 **14 条 E2E 用例（`WTC-01`..`WTC-14`）**。
   - 机械校验 6 大核心规则的源码落地：`defaultCompactThreshold = 5`、`maxKeyPoints = 3`、`deviceOwnerAuthenticationWithWristDetection`、`wristVerified`、`createVoiceTask`、`proceedPlan`、`.handGestureShortcut(.primaryAction)` 及全量 `accessibilityIdentifier` 覆盖。
   - 在无头 Chromium 的 Series 10 46mm 视口（`208×248pt @2x` = `416×496px`）执行全部 **14 条交互式 E2E 路径（`WTC-01`..`WTC-14`）**，断言 `overflowX == 0px`，生成 `watch-esdd-report.json` 与 `WATCH_ESDD_COMPARISON_OVERVIEW.png`。

2. **Layer 2 — Swift 6 领域模型、风险分层、腕上门禁与双向同步单元测试（`WatchCompanionTests.swift`）**
   - `WatchDiffTriageEngine` 三重边界验证：`≤ 5` 文件无风险项（`W05` 可 `Accept all`）、**`≤ 5` 文件但含风险项如 `go.mod`（强制 `W06` 分组去 iPhone 审）**、`6` 文件 / `23` 文件（`> 5` 强制 `W06` 分组去 iPhone 审）。
   - `WatchArtifactSummarizer` 严格 `≤ 3` 条要点裁剪、等宽代码/翠绿指标提取与 `Proceed` vs `See changes` 单一主操作选择。
   - `WatchConnectivityCodec` 往返编解码（`< 32KB`）、`wristVerified` 缺省向后兼容、通知 `userInfo` 解析与 `ResilientStringEnum` 前向兼容。
   - `WatchCompanionProjector` 与 `AntigravitySessionStore` 双向闭环（设备切换、语音新建任务 `createVoiceTask`、语音回复、计划 `Proceed`、命令审批、接受全部改动与 `LockedOffWristVerifier` 拦截）。

3. **Layer 3 — 真实 Apple Watch Simulator 原生 XCUITest 交互 E2E（`tests/watchos-ui/AGPocketWatchUITests.swift`）**
   - `testWTC01_WTC02_HomeSessionsAndDeviceSwitching`（`W01` 左上切设备、`W02` 离线拦截、切至 `Cloud`）
   - `testWTC03_WTC04_ChatStreamAndArtifactWalkthrough`（`W03` → `W04` `≤ 3` 要点 + iPhone 接力 + `See changes`）
   - `testWTC05_CompactChangedFilesAndAcceptAll`（`W05` `≤ 5` 无风险文件 + `Accept all`）
   - `testWTC06_GroupedChangedFilesTriageAndPhoneHandoff`（`W06` `WORTH A LOOK` + `GROUPED` 展开 + `iPhone` 接力，无 `Accept all`）
   - `testWTC07_VoiceInputTargetSwitchAndSend`（`W07` 目标切换 + `Send`）
   - `testWTC08_WTC09_ApprovalNotificationAllowDenyAndReplyByVoice`（`W08` `Allow` / `Deny` / `Reply by voice`）
   - `testWTC13_WristLockedBlocksApprovals`（启动 `--watch-wrist-locked`，验证 `Allow` 与 `Accept all` 均被拦截并提示 `Unlock Watch on wrist to approve`）
   - `testWTC14_HomeTopRightVoiceCreatesNewTask`（从 `W01` 点击右上角蓝麦克风验证默认 `To: New task`，点击 `Send` 后在首页新建运行中任务）

4. **Layer 4 — 真实 Apple Watch Series 10 Simulator 8 屏截图与 1:1 视觉对比（`verification/watchos-simulator-runner.py`）**
   - 编译 `watchsimulator` 与 `generic/platform=watchOS` 真机目标，采集全部 8 屏真模拟器截图并与参考设计稿生成 1:1 对比拼图。

---

## 2. 可执行 E2E 测试用例矩阵（`WTC-01` .. `WTC-14`）

| 用例 ID | 覆盖画面 / 领域 | 前置条件 | 测试操作步骤 | 预期结果与验收断言 |
| :--- | :--- | :--- | :--- | :--- |
| **`WTC-01`** | `W01_SESSIONS`（会话列表首页） | 启动 `--watch-verify W01_SESSIONS` | 渲染首页；检查左上设备圆钮、右上语音新建蓝麦克风、标题 `Agents` + `MacBook Pro` 与 3 张会话卡片 | 依次呈现待批准、运行中、已完成会话；水平溢出 `0px` |
| **`WTC-02`** | `W01` → `W02_DEVICES`（在线设备切换） | 位于 `W01_SESSIONS` | 点击左上角设备圆钮进入 `Devices`；先点离线 `Office iMac`，再点在线 `Cloud` | 点离线设备提示 `Office iMac is offline`；点 `Cloud` 自动返回 `W01` 且设备名更新为 `Cloud` |
| **`WTC-03`** | `W01` → `W03_CHAT_STREAM`（对话流） | 启动 `W03_CHAT_STREAM` | 验证状态 `Step 6 of 7 · Running`、语音气泡、回复、`Walkthrough` 卡片、`+128 -14 · 4 files` 胶囊与右下麦克风 FAB | 所有关键信息无裁切溢出，FAB 始终可点 |
| **`WTC-04`** | `W03` → `W04_ARTIFACT_SUMMARY`（产物摘要） | 位于 `W03_CHAT_STREAM` | 点击 `Walkthrough` 进入 `W04`；验证标题、`≤ 3` 条要点（等宽代码与绿指标）；点 `iPhone` 接力；再点 `See changes` | 点 `iPhone` 弹出 `Opened on iPhone`；点 `See changes` 进入 `W05` |
| **`WTC-05`** | `W05_CHANGED_FILES_COMPACT`（`≤ 5` 且无风险项） | 启动 `W05_CHANGED_FILES_COMPACT`（4 安全文件） | 检查 `4 files · +128 -14`、无源码行、逐文件 `A`/`M` 与一句话摘要；在手表已解锁戴腕时点击 `Accept all` | 按钮切换绿色 `Accepted`，弹出 `Accepted all`，会话标记 `Done` |
| **`WTC-06`** | `W06_CHANGED_FILES_GROUPED`（`> 5` 或含风险项） | 启动 `W06_CHANGED_FILES_GROUPED`（23 文件） | 检查 `WORTH A LOOK · 2`（`audit/writer.go`、`go.mod`）、`GROUPED · 21`；展开分组卡片；点 `iPhone` 主操作 | 绝不出现 `Accept all`；展开子路径摘要；点击 `iPhone` 触发 `Opened on iPhone` |
| **`WTC-07`** | `W07_VOICE_INPUT`（语音回复与切目标） | 启动 `W07_VOICE_INPUT` | 检查 `To: Rate limiter`、转写文本、声波与 `Double tap to send`；点击目标胶囊切至 `Dark mode settings`；点停止再点 `Send` | 目标切换成功；点击 `Send` 提交语音回复并提示 `Sent` |
| **`WTC-08`** | `W08_APPROVAL_NOTIFICATION`（待批准 — Allow） | 启动 `W08_APPROVAL_NOTIFICATION`（已解锁戴腕） | 检查 `Run this command?`、命令卡片与暖琥珀 `Allow`（Double Tap）；点击 `Allow` | 腕上解锁校验通过，派发 `approveCommand(wristVerified: true)`，关闭审批页并提示 `Allowed` |
| **`WTC-09`** | `W08_APPROVAL_NOTIFICATION`（Deny & Reply by voice） | 启动 `W08_APPROVAL_NOTIFICATION` | 分支 A 点击 `Deny`；分支 B 重开 `W08` 点击 `Reply by voice` | 分支 A 清除待批准态并标记 `Denied`；分支 B 直接进入 `W07` 且目标锁定 `Rate limiter` |
| **`WTC-10`** | **Diff 风险与规模门禁引擎（Unit E2E）** | `WatchCompanionTests` | 传入 4 安全文件、5 安全文件、**3 文件含 `go.mod` 风险项**、6 安全文件、23 混合文件 | 4/5 安全文件 `canAcceptAllOnWatch == true`；**3 文件含风险项与 6/23 文件均强制 `isGroupedMode == true`、`canAcceptAllOnWatch == false`** |
| **`WTC-11`** | **Wire 编解码、`≤ 3` 产物要点与前向兼容（Unit E2E）** | `WatchCompanionTests` | 往返编解码快照/指令（含缺省 `wristVerified` 兼容）、5 条要点 Markdown 产物裁剪、`Implementation Plan` 识别与未知枚举降级 | 快照 `< 32KB`；产物要点严格 `== 3`；Plan 主操作为 `.proceed`；未知枚举优雅降级 |
| **`WTC-12`** | **iPhone ↔ Watch 全链路闭环（Integration E2E）** | `AntigravitySessionStore.makeESDDVerificationStore()` | 从真实 iOS Store 投影，依次执行设备切换、语音新建任务、命令审批、计划 `Proceed`、语音回复与 `Accept all` | 每次回写均准确变更 Store 状态并反映在下一帧 Watch 快照中 |
| **`WTC-13`** | **腕上解锁门禁拦截 + `≤ 5` 含风险项拦截（Interactive + Unit E2E）** | 锁表/离腕模式（`--watch-wrist-locked`）+ 3 文件含风险项 | 在锁表/离腕状态下点 `Allow` 与 `Accept all`；以及对 3 文件含 `go.mod` 渲染变更页 | 锁表/离腕拦截审批、保留待审态并提示 `Unlock Watch on wrist to approve`；3 文件含风险项隐藏 `Accept all` 并改用 `iPhone` 审 |
| **`WTC-14`** | **首页右上角语音新建任务 + Plan `Proceed`（Interactive + Unit E2E）** | 位于 `W01_SESSIONS` & Implementation Plan 产物 | 从 `W01` 点右上角蓝麦克风验证 `To: New task` 并点击 `Send`；在 Plan 摘要页验证 `≤ 3` 要点并点击 `Proceed`（Double Tap） | 新建任务乐观插入 `W01` 会话列表并派发 `createVoiceTask`；Plan `Proceed` 经腕上解锁通过后切换 `Proceeding` |
