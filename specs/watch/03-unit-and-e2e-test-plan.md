# AG Pocket Apple Watch — 单元测试、交互式 E2E 与视觉验收测试计划 (v1.0)

## 1. 四层端到端验证策略

1. **Layer 1 — Watch ESDD 规范图谱、源码契约与无头交互式 E2E（`verification/verify_watch_esdd.py`，Linux & macOS 均可秒级运行）**
   - 校验 [`specs/watch/esdd-watch-ir.json`](./esdd-watch-ir.json)：12 个 OLED 色彩 Token、8 个画面状态（`W01`–`W08`）、8 张 `416×496px @2x` 参考设计稿、11 条导航转换边（BFS 校验从 `W01_SESSIONS` 100% 可达）、8 条可执行验收断言（`WCLAIM-01`..`WCLAIM-08`）与 12 条 E2E 用例（`WTC-01`..`WTC-12`）。
   - 机械校验 100% `accessibilityIdentifier` 覆盖率：IR 中声明的每个必选控件 ID 均存在于 `apps/ios/Watch/**/*.swift` 且被 `tests/watchos-ui/AGPocketWatchUITests.swift` 断言验证。
   - 在无头 Chromium 的真实 Apple Watch Series 10 46mm 视口（`208×248pt @2x` = `416×496px`）执行全部 **12 条交互式 E2E 路径（`WTC-01`..`WTC-12`）**，断言状态流转、零水平溢出（`overflowX == 0px`）、按钮触控尺寸达标，并生成 `verification/output/watch/watch-esdd-report.json`。

2. **Layer 2 — Swift 6 领域模型、分层引擎与双向同步单元测试（`WatchCompanionTests.swift`）**
   - `WatchDiffTriageEngine` 紧凑模式（`≤ 6` 文件）vs 按意图分组模式（`> 6` 文件、`WORTH A LOOK` 风险识别、`GROUPED` 聚类统计）。
   - `WatchArtifactSummarizer` Markdown 提炼、行内等宽代码片段与翠绿性能指标提取。
   - `WatchConnectivityCodec` 快照与指令编解码往返、通知 `userInfo` 解析、以及未知未来枚举前向兼容降级。
   - `WatchCompanionProjector` 实时 `AntigravitySessionStore` 投影与 iPhone ↔ Watch 端到端指令回写闭环（设备切换、审批放行/拒绝、语音回复发送、接受全部改动、Handoff 路由）。

3. **Layer 3 — 真实 Apple Watch Simulator 原生 XCUITest 交互 E2E（`tests/watchos-ui/AGPocketWatchUITests.swift`）**
   - 在 `macos-26` + Apple Watch Series 10 (46mm) watchOS Simulator 上以真实编译的 `AGPocketWatch.app` 执行全部端到端交互测试方法：
     - `testWTC01_WTC02_HomeSessionsAndDeviceSwitching`（`W01` ↔ `W02` 切换设备、离线拦截、首页同步更新）
     - `testWTC03_WTC04_ChatStreamAndArtifactWalkthrough`（`W01` → `W03` → `W04` 产物摘要要点与 iPhone 接力）
     - `testWTC05_CompactChangedFilesAndAcceptAll`（`W05` 少量文件卡片展示与 `Accept all` 状态确认）
     - `testWTC06_GroupedChangedFilesTriageAndPhoneHandoff`（`W06` 大量文件 `WORTH A LOOK` + `GROUPED` 展开 + `iPhone` 接力）
     - `testWTC07_VoiceInputTargetSwitchAndSend`（`W07` 切换目标会话、暂停/恢复、点击 `Send` 提交并回流聊天）
     - `testWTC08_ApprovalNotificationAllowDenyAndReplyByVoice`（`W08` 待批准命令卡片验证 `Allow` / `Deny` / `Reply by voice` 三条分支）

4. **Layer 4 — 真实 Apple Watch Series 10 Simulator 8 屏截图与 1:1 视觉对比（`verification/watchos-simulator-runner.py`）**
   - 编译 `watchsimulator` 与 `generic/platform=watchOS`（arm64 真机编译链接门禁）。
   - 在真实 watchOS Simulator 启动全部 8 个确定性画面（`W01_SESSIONS` .. `W08_APPROVAL_NOTIFICATION`），采集原生截图并生成 `WATCH_8_SCREENS_OVERVIEW.png` 及左参考稿/右真模拟器 1:1 对比图 `WATCH_REF_VS_SIM_COMPARISON.png`。

---

## 2. 可执行 E2E 测试用例矩阵（`WTC-01` .. `WTC-12`）

| 用例 ID | 覆盖画面 / 领域 | 前置条件 | 测试操作步骤 | 预期结果与验收断言 |
| :--- | :--- | :--- | :--- | :--- |
| **`WTC-01`** | `W01_SESSIONS`（会话列表首页） | 启动 `--watch-verify W01_SESSIONS` | 渲染首页；检查顶部设备圆钮与蓝底麦克风圆钮、标题 `Agents` + `MacBook Pro`、3 张会话卡片 | 依次呈现 `Rate limiter`（暖琥珀 `Approve command`）、`Dark mode settings`（蓝色 `Cloud · 2 of 5`）、`Upgrade to Go 1.25`（`Done · +42 −31`）；水平溢出 `0px` |
| **`WTC-02`** | `W01` → `W02_DEVICES`（在线设备切换） | 位于 `W01_SESSIONS` | 点击左上角设备圆钮进入 `Devices`；先点 `Office iMac`（离线），再点 `Cloud`（在线） | `MacBook Pro` 默认选中带蓝边；点离线设备停留当前页并提示 `Office iMac is offline`；点 `Cloud` 后自动返回 `W01` 且右上设备名更新为 `Cloud` |
| **`WTC-03`** | `W01` → `W03_CHAT_STREAM`（对话流） | 启动 `W03_CHAT_STREAM` 或从 `W01` 点击 `Rate limiter` | 验证标题 `Rate limiter`、状态 `Step 6 of 7 · Running`、语音气泡 `Use 1000/s on staging`、回复文本、`Walkthrough` 卡片、`+128 -14 · 4 files` 胶囊与右下蓝麦克风 FAB | 所有关键信息完整可见且无裁切；滚动流畅且悬浮麦克风 FAB 始终可点 |
| **`WTC-04`** | `W03` → `W04_ARTIFACT_SUMMARY`（产物摘要与接力） | 位于 `W03_CHAT_STREAM` | 点击 `Walkthrough` 卡片进入 `W04`；验证标题、`Per-tenant token bucket`、3 条编号要点（含 `ratelimit.go` 等宽与 `3.8 ms` 绿高亮）；点击左下 `iPhone` 按钮；再点击 `See changes` | 点 `iPhone` 触发 Handoff 并弹出 `Opened on iPhone` Toast；点 `See changes` 导航至 `W05` 改动文件页 |
| **`WTC-05`** | `W05_CHANGED_FILES_COMPACT`（少量改动与一键接受） | 启动 `W05_CHANGED_FILES_COMPACT`（4 文件） | 检查 `4 files · +128 -14`、文件卡片（`A ratelimit.go +96`、`M router.go +12 -6`、`M config.go +14 -2`）；点击底栏 `Accept all` | 按钮切换为绿色 `Accepted` 并弹出 `Accepted all` Toast；对应会话状态更新为 `Done` |
| **`WTC-06`** | `W06_CHANGED_FILES_GROUPED`（大量改动按意图分组） | 启动 `W06_CHANGED_FILES_GROUPED`（23 文件） | 检查 `23 files · +412 -198`、`WORTH A LOOK · 2`（`audit/writer.go`、`go.mod`）、`GROUPED · 21`（`16 · Call sites → updated`）；点击分组卡片展开路径；点击右下 `iPhone` 接力胶囊 | 禁止出现盲目 `Accept all` 按钮；分组卡片展开展示子路径及 `+N more on iPhone`；点击 `iPhone` 触发 Handoff 与 `Opened on iPhone` Toast |
| **`WTC-07`** | `W07_VOICE_INPUT`（语音输入、切目标与发送） | 启动 `W07_VOICE_INPUT` | 检查 `To: Rate limiter` 胶囊、转写文本（已确认 + 尾部灰字 `2000`）、波形与 `Double tap to send`；点击目标胶囊切换至 `Dark mode settings`；点击停止按钮再点 `Send` | 目标胶囊切换成功；点击 `Send` 关闭语音页、将语音消息乐观写入目标会话并提示 `Sent` |
| **`WTC-08`** | `W08_APPROVAL_NOTIFICATION`（待批准通知 — Allow） | 启动 `W08_APPROVAL_NOTIFICATION` | 检查 `Agents · now`、暖琥珀 `Run this command?`、`Rate limiter · step 5 of 7`、`vegeta attack -rate=2000/s -duration=30s`；点击暖琥珀 `Allow` | 审批弹层关闭，派发 `approveCommand`，会话从待批准推进至运行中并提示 `Allowed` |
| **`WTC-09`** | `W08_APPROVAL_NOTIFICATION`（待批准通知 — Deny & Reply by voice） | 启动 `W08_APPROVAL_NOTIFICATION` | 分支 A：点击 `Deny`；分支 B：重新打开 `W08`，点击 `Reply by voice` | 分支 A 清除待批准态并标记 `Denied`；分支 B 直接无缝切入 `W07_VOICE_INPUT` 且目标锁定为 `Rate limiter` |
| **`WTC-10`** | **Diff 分层引擎边界与风险分类（Unit E2E）** | `WatchCompanionTests` | 分别传入 4 文件（`≤ 6`）与 23 文件（含 `audit/writer.go`、`go.mod`、16 调用点、5 单测）调用 `WatchDiffTriageEngine.buildChangesSnapshot` | 4 文件输出 `isGroupedMode == false`；23 文件输出 `isGroupedMode == true`、`worthALookFiles == ["audit/writer.go", "go.mod"]`、`groupedFileCount == 21` |
| **`WTC-11`** | **双向 Wire 编解码与前向兼容（Unit E2E）** | `WatchCompanionTests` | 往返编解码完整 `WatchCompanionSnapshot`、`WatchRemoteCommand`、通知 `userInfo` 解析，并喂入未知未来枚举字符串 | 100% 无损往返；所有未知枚举优雅降级至 `unknownFallback`，零抛出异常 |
| **`WTC-12`** | **iPhone ↔ Watch 完整状态投影与指令回环（Integration E2E）** | `AntigravitySessionStore.makeESDDVerificationStore()` | 从真实 iOS Store 投影快照给 Watch，再模拟 Watch 侧下发 `selectDevice` / `approveCommand` / `sendVoiceReply` / `acceptAllChanges` 回写 Store 并重新投影 | 每次回写均准确变更 iOS Store 状态并体现在下一次投影快照中，实现完整闭环 |
