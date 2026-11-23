# AG Pocket Apple Watch — 技术架构、数据同步与安全审批方案 (v1.1)

- **状态**：Normative Technical Design
- **核心边界**：Watch 只做三件事——**看状态、批准、语音发任务**；绝不在手表传输或渲染源代码行级 Diff，所有批准动作强制校验腕上解锁。
- **适用范围**：
  1. 共享纯 Swift 6 数据、分层审阅引擎与腕上解锁契约（`apps/ios/Packages/AntigravityData`）
  2. iPhone ↔ Apple Watch 双向通信、二次安全校验、可交互通知与 Handoff 接力（`apps/ios/App/Services/`）
  3. 原生 watchOS 11+ 单 Target 伴侣应用与硬件腕上解锁守卫（`apps/ios/Watch/`）
  4. XcodeGen 多平台构建、Watch XCUITest 与 Apple Watch Series 10 视觉 CI（`project.yml`、`tests/watchos-ui/`、`verification/`）

---

## 1. 架构选型与端到端数据流

### 1.1 为什么 Watch 直接复用纯 Swift `AntigravityData`？
- `apps/ios/Packages/AntigravityData` 遵循零 `UIKit` / `WebKit` / `AVFoundation` / `LocalAuthentication` 隔离原则，声明 `.watchOS(.v11)` 即可被 `AGPocketWatch` 零体积开销直接复用，确保数据模型、Diff 风险分层引擎、产物摘要器与确定性 Fixtures 在 iOS、macOS XCTest 与 watchOS 间保持单一事实来源。
- watchOS 硬件安全 API（`LocalAuthentication` / `LAPolicy.deviceOwnerAuthenticationWithWristDetection`）放在 `apps/ios/Watch/State/WatchWristUnlockGuard.swift`，通过 `AntigravityData` 中的纯 Swift 协议 `WatchWristUnlockAuthorizing` 解耦，既满足生产环境真机硬件门禁，又支持测试确定性注入 `AlwaysAuthorizedWristVerifier` 与 `LockedOffWristVerifier`。

### 1.2 端到端数据流拓扑

```text
Antigravity Desktop / Cloud Relay
        │  (Connect-RPC / 5-byte Stream / KMP Core)
        ▼
iPhone `AGPocket` (`AntigravitySessionStore`)
  ├── `WatchCompanionProjector.project(from: store)` -> 紧凑 JSON 快照 (< 16KB，零源码行)
  ├── `WatchConnectivityBridge` (iOS `WCSessionDelegate`)
  │      ├── 下行: `updateApplicationContext` (保底最新态) + `sendMessage` (可达时亚秒级实时推送)
  │      └── 上行: 接收 `WatchRemoteCommand`
  │               ├── 二次门禁: `requiresWristUnlockApproval && !wristVerified` 一律拒绝
  │               ├── `createVoiceTask` -> `createNewCascade(title:initialPrompt:)`
  │               ├── `sendVoiceReply` -> `sendCurrentDraft()`
  │               ├── `approveCommand` / `proceedPlan` / `acceptAllChanges` (再校验 <=5 且无风险项)
  │               └── `selectDevice` / `denyCommand` / `openOnPhone` / `requestRefresh`
  ├── `NotificationCoordinator` (`UNNotificationCategory: AGPOCKET_APPROVAL_REQUEST`)
  │      └── `allowAction` 带 `.authenticationRequired`，携带审批上下文镜像至 Watch `W08`
  └── `onContinueUserActivity(com.thousandtimes.agpocket.handoff)` & `agpocket://{cascade,artifact,changes}/<id>`
        ▲
        │  (`WatchConnectivity` + `NSUserActivity` Handoff)
        ▼
Apple Watch `AGPocketWatch` (`WatchAppStore` + `WatchSessionDelegateProxy` + `WatchWristUnlockGuard`)
  ├── 本地 `UserDefaults` 快照缓存（离线秒开最近状态）
  ├── `WatchWristUnlockGuard`: `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithWristDetection)`
  │      └── 强制门禁 `Allow` (`approveCommand`) / `Proceed` (`proceedPlan`) / `Accept all` (`acceptAllChanges`)
  ├── 8 屏原生 SwiftUI 视图 (`W01`..`W08`) + Double Tap (`.handGestureShortcut(.primaryAction)`)
  └── `WKNotificationScene(controller: WatchApprovalNotificationController.self)` (`isInteractive = true` + 腕上解锁门禁)
```

---

## 2. 核心模块技术方案

### 2.1 紧凑同步契约与前向兼容（`WatchCompanionModels.swift`）
- **单向快照（`WatchCompanionSnapshot`）**：最多 12 个活跃会话、每会话最近 4 条精简消息、严格 `≤ 3` 条要点的 `WatchArtifactSummarySnapshot` 与不含源码行的 `WatchChangesSnapshot`，稳定远低于 `WCSession` 65KB 限制。
- **远端指令（`WatchRemoteCommand`）**：支持 9 类指令：`selectDevice`、`approveCommand`、`denyCommand`、`sendVoiceReply`、`createVoiceTask`（首页右上角语音新建任务）、`proceedPlan`（产物摘要 `Proceed`）、`acceptAllChanges`、`openOnPhone`、`requestRefresh`，并携带 `artifactPath: String?` 与 `wristVerified: Bool`（向后兼容缺省解码为 `false`）。
- **前向兼容枚举**：全部 8 个字符串枚举（含 `WatchArtifactPrimaryAction`、`WatchRemoteCommandKind` 等）均遵循 `ResilientStringEnum`。
- **Swift 6 严格并发安全**：
  - `WatchAppStore` 为纯 Swift `@MainActor @Observable`，`WCSessionDelegate` 隔离在私有 `WatchSessionDelegateProxy`；
  - `WatchWristUnlockGuard` 使用 `withCheckedContinuation` 封装 `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithWristDetection, ...)`，不跨越 Actor 边界传递非 `Sendable` 的 `LAContext`。

### 2.2 Diff 风险与规模双重门禁引擎（`WatchDiffTriageEngine`）
- **核心判定规则**：`defaultCompactThreshold = 5`，且 **先做风险扫描、再决定模式**：
  1. 对全部改动文件运行 `classifyHighSignalReason(for: diff)`，识别依赖/构建清单（`go.mod`、`Package.swift`、`package.json`、`Cargo.toml`、`build.gradle.kts`、`project.yml`、`Dockerfile` 等）、安全/鉴权/审计/迁移路径（`audit`、`auth`、`security`、`crypto`、`permission`、`migration`、`schema`、`billing`、`policy` 等）以及大额删除（`deleted && deletions >= 25`）。
  2. **仅当 `totalFiles <= 5 && worthALook.isEmpty`**：进入 `W05` 紧凑模式（`isGroupedMode = false`，`canAcceptAllOnWatch = true`），逐文件列出 `A`/`M`/`D` + 一句话摘要 + `+/-`，允许手表端 `Accept all`。
  3. **否则（`totalFiles > 5` 或 `!worthALook.isEmpty`）**：强制进入 `W06` 分层模式（`isGroupedMode = true`，`canAcceptAllOnWatch = false`），置顶 `WORTH A LOOK`（值得一看），将其余文件按意图折叠为 `GROUPED`（`Call sites → updated`、`Test suites`、`Docs & specs`），手表端隐藏 `Accept all`，主操作切换为 `iPhone` 接力。
- **零源码传输保证**：`WatchChangedFileItem` 仅包含 `filePath`、`statusLetter`、`summary`、`additions`、`deletions`、`isWorthALook`，绝不包含任何源码行数组。

### 2.3 产物 Markdown 摘要器（`WatchArtifactSummarizer`）
- 严格裁剪 `maxKeyPoints = 3`（在 `WatchArtifactSummarySnapshot.init`、`init(from:)`、`WatchArtifactSummarizer.buildSummary` 与 `WatchArtifactSummaryView` 四处同时强制 `≤ 3`）；
- 自动判定单个主操作：`artifact.kind == .implementationPlan || artifact.requestFeedback` → `.proceed`（`Proceed`，绑定 Double Tap + 腕上解锁校验）；其余（如 `Walkthrough`）→ `.seeChanges`（`See changes`，绑定 Double Tap）。

### 2.4 腕上解锁硬件门禁（`WatchWristUnlockGuard` + 双端纵深防御）
- **Watch 端**：`WatchAppStore`（`approveCommand`、`proceedPlan`、`acceptAllChanges`）与 `WatchApprovalNotificationController`（Long-Look 通知 `Allow`）均调用 `verifyUnlockedOnWrist(reason:)`，底层执行 `LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithWristDetection, error:)` 与 `evaluatePolicy(.deviceOwnerAuthenticationWithWristDetection, localizedReason:)`；任一失败即 Fail-Closed，播放 `.failure` 触觉并显示 `Unlock Watch on wrist to approve`。
- **iPhone 端**：`WatchConnectivityBridge.handleIncomingCommand` 二次校验 `command.kind.requiresWristUnlockApproval && !command.wristVerified`（直接丢弃未验证指令），且 `.acceptAllChanges` 还会二次运行 `WatchDiffTriageEngine` 确认 `canAcceptAllOnWatch == true`。
- **自动化验证注入**：`--watch-verify` 默认注入 `AlwaysAuthorizedWristVerifier()`；配合 `--watch-wrist-locked` 或 `AGPOCKET_WATCH_WRIST_LOCKED=1` 注入 `LockedOffWristVerifier()`，可在 Simulator XCUITest 中确定性验证锁表/离腕拦截。

### 2.5 XcodeGen 多平台工程与测试目标（`project.yml`）
- `AGPocketWatch` target（`watchOS 11.0+`，`WKApplication: true`，嵌入 `AGPocket`）与 `AGPocketWatchUITests` target（`tests/watchos-ui`）。
- CI 验证管线：`verify_watch_esdd.py`（Stage W1 + Stage W2 `WTC-01`..`WTC-14`）+ `watchos-simulator-runner.py`（`watchsimulator` & `generic/platform=watchOS` 构建、`AGPocketWatchUITests`、8 屏真机模拟器截图与 1:1 参考对比）。
