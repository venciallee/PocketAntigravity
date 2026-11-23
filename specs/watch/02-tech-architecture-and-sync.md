# AG Pocket Apple Watch — 技术架构、数据同步与分层审阅方案 (v1.0)

- **状态**：Normative Technical Design
- **适用范围**：
  1. 共享纯 Swift 6 数据与意图分类层（`apps/ios/Packages/AntigravityData`）
  2. iPhone ↔ Apple Watch 双向通信、可交互通知与 Handoff 接力（`apps/ios/App/Services/`）
  3. 原生 watchOS 11+ 单 Target 伴侣应用（`apps/ios/Watch/`）
  4. XcodeGen 多平台构建、Watch XCUITest 与 Apple Watch Series 10 视觉 CI（`project.yml`、`tests/watchos-ui/`、`verification/`）

---

## 1. 架构选型与边界划分

### 1.1 为什么 Watch 直接复用纯 Swift `AntigravityData` 而不引入 `AntigravityShared.xcframework`？
- `AntigravityShared.xcframework`（KMP Kotlin/Native + Ktor Darwin）当前聚焦 iOS/Android 主端，二进制体积较大且面向长连接网络引擎；Apple Watch 受限于功耗、安装包体积与内存配额，且需要 **离线瞬时冷启动** 与 **超低功耗蓝牙/Wi-Fi 协同**。
- `apps/ios/Packages/AntigravityData` 本身遵循零 `UIKit` / `WebKit` / `AVFoundation` 隔离原则，仅依赖 `Foundation`、`Observation`、`CryptoKit`、`Security`、`Network`，直接声明 `.watchOS(.v11)` 即可零开销被 `AGPocketWatch` 复用，使数据契约、状态投影、Diff 分层引擎、产物摘要器与确定性 Fixtures 在 iOS、macOS XCTest 与 watchOS 间保持 **单一事实来源（Single Source of Truth）**。

### 1.2 端到端数据流拓扑

```text
Antigravity Desktop / Cloud Relay
        │  (Connect-RPC / 5-byte Stream / KMP Core)
        ▼
iPhone `AGPocket` (`AntigravitySessionStore`)
  ├── `WatchCompanionProjector.project(from: store)` -> 紧凑 JSON 快照 (< 16KB)
  ├── `WatchConnectivityBridge` (iOS `WCSessionDelegate`)
  │      ├── 下行: `updateApplicationContext` (保底最新态) + `sendMessage` (可达时亚秒级实时推送)
  │      └── 上行: 接收 `WatchRemoteCommand` -> 驱动 `selectHostScope` / `approveWaitingCommandWithFaceID`
  │               / `denyWaitingCommand` / `sendCurrentDraft` / `acceptAllTurnDiffs` / 路由跳转
  ├── `NotificationCoordinator` (`UNNotificationCategory: AGPOCKET_APPROVAL_REQUEST`)
  │      └── 携带 `cascadeId`, `cascadeTitle`, `stepIndex`, `totalSteps`, `commandLine` -> 自动镜像至 Watch `W08`
  └── `onContinueUserActivity(com.thousandtimes.agpocket.handoff)` & `agpocket://{cascade,artifact,changes}/<id>`
        ▲
        │  (`WatchConnectivity` + `NSUserActivity` Handoff)
        ▼
Apple Watch `AGPocketWatch` (`WatchAppStore` + `WatchSessionDelegateProxy`)
  ├── 本地 `UserDefaults` 快照缓存（离线秒开最近状态）
  ├── 乐观 UI 更新 + `sendMessage` 失败自动降级 `transferUserInfo` 持久投递
  ├── 8 屏原生 SwiftUI 视图 (`W01`..`W08`) + Double Tap (`.handGestureShortcut(.primaryAction)`)
  └── `WKNotificationScene(controller: WatchApprovalNotificationController.self)` (`isInteractive = true`)
```

---

## 2. 核心模块技术方案

### 2.1 紧凑同步契约与前向兼容（`WatchCompanionModels.swift`）
- **单向快照（`WatchCompanionSnapshot`）**：限制最多 12 个活跃会话、每会话最近 4 条精简消息、提炼后的 `WatchArtifactSummarySnapshot` 与分层后的 `WatchChangesSnapshot`，确保序列化后稳定远低于 `WCSession.updateApplicationContext` 的 65KB 上限。
- **远端指令（`WatchRemoteCommand`）**：统一封装 7 类指令：`selectDevice`、`approveCommand`、`denyCommand`、`sendVoiceReply`、`acceptAllChanges`、`openOnPhone`（`.chat`/`.artifact`/`.changes`）、`requestRefresh`。
- **前向兼容枚举**：全部 7 个新增字符串枚举（`WatchVerifySceneCase`、`WatchSessionStatus`、`WatchDeviceKind`、`WatchStyledSpanKind`、`WatchFileStatusLetter`、`WatchPhoneHandoffTarget`、`WatchRemoteCommandKind`）均严格遵守 `ResilientStringEnum`（通过 `verify_compat_guardrails.py` 机械校验），未来 iPhone 新版下发未知枚举不会导致旧版 Watch 解码崩溃。
- **Swift 6 严格并发安全**：
  - `WatchAppStore` 保持纯 Swift `@MainActor @Observable`（不继承 `NSObject`），将 `WCSessionDelegate` 隔离在私有 `WatchSessionDelegateProxy` 内；
  - 所有 `nonisolated` Delegate 回调先在当前线程将非 `Sendable` 的 `[String: Any]` 解码为 `Sendable` 领域模型，再通过 `Task { @MainActor in ... }` 切回主线程；
  - `sendMessage` 的 `@Sendable` `errorHandler` 仅捕获 `Sendable` 的 `Data`，在回调内重建 `[String: Any]` 交给 `transferUserInfo` 重试。

### 2.2 Diff 意图分组引擎（`WatchDiffTriageEngine`）
- **模式阈值**：`defaultCompactThreshold = 6`。
  - `totalFiles <= 6`：`isGroupedMode = false`，输出完整 `compactFiles`，每个文件提取 hunk 标题或增删行摘要，供 `W05` 展示并支持 `Accept all`。
  - `totalFiles > 6`：`isGroupedMode = true`，输出 `worthALookFiles`（最多置顶 4 个高风险文件）+ `intentGroups`（机械改动聚类），供 `W06` 展示并切换底部 CTA 为 `iPhone` 接力。
- **高风险识别规则（`WORTH A LOOK`）**：
  1. 依赖/构建清单（`go.mod`、`Package.swift`、`package.json`、`Cargo.toml`、`build.gradle.kts`、`project.yml`、`Dockerfile` 等）——删除行多于新增行时标注 `"Removes a dependency"`；
  2. 安全/鉴权/审计/数据库迁移路径关键字（`audit`、`auth`、`security`、`crypto`、`permission`、`migration`、`schema`、`billing` 等）——分别生成语义原因如 `"Log field names change"` / `"Auth or permission change"`；
  3. 删除文件且删除行数 `>= 25`；
  4. 若大改动集未命中上述规则，兜底提取改动行数最大的 1 个核心文件。
- **机械改动聚类规则（`GROUPED`）**：按路径语义归并为 `Call sites → updated`（统计跨目录数 `N dirs`）、`Test suites`、`Docs & specs` 三类卡片，点击卡片可在手表端按需展开查看前 5 条文件路径。

### 2.3 产物 Markdown 摘要器（`WatchArtifactSummarizer`）
- 解析 `ArtifactSnapshot.content` 的标题与无序/有序列表，提取核心 `headline` 与前 3 条编号要点；
- 行内解析反引号代码片段（`.code` 等宽渲染）与正则性能数字指标（`\b\d+(?:\.\d+)?\s?(?:ms|s|%)\b` → `.metricHighlight` 翠绿加粗渲染），与 `W04` 设计稿 1:1 匹配。

### 2.4 iOS 通知与 watchOS Long-Look 通知（`W08`）
- iPhone `NotificationCoordinator` 注册分类 `AGPOCKET_APPROVAL_REQUEST` 及 3 个动作：
  - `AGPOCKET_APPROVAL_ALLOW`（`Allow`，需认证）
  - `AGPOCKET_APPROVAL_DENY`（`Deny`，破坏性）
  - `AGPOCKET_APPROVAL_REPLY_VOICE`（`Reply by voice`，`UNTextInputNotificationAction`，支持表端直接听写回复）
- Apple Watch 侧在 `AGPocketWatchApp` 注册 `WKNotificationScene(controller: WatchApprovalNotificationController.self, category: "AGPOCKET_APPROVAL_REQUEST")`，且 `WatchApprovalNotificationController` 显式覆写 `isInteractive = true`，保证通知长看视图内的 `Allow` / `Deny` / `Reply by voice` 按钮可直接触发点击与 Double Tap。

### 2.5 XcodeGen 多平台工程与测试目标（`project.yml`）
- 新增 `AGPocketWatch` target（`type: application`，`platform: watchOS`，`deploymentTarget: "11.0"`，`WKApplication: true`，`TARGETED_DEVICE_FAMILY: "4"`，`SKIP_INSTALL: YES`），并嵌入 `AGPocket` 主应用（`embed: true`）。
- 新增 `AGPocketWatchUITests` target（`type: bundle.ui-testing`，`platform: watchOS`，`sources: tests/watchos-ui`，`TEST_TARGET_NAME: AGPocketWatch`），挂入 `AGPocketWatch` scheme 的 `test` 阶段。
- CI 构建与脚本支持：
  - `ios-simulator-runner.py` 改用 `-destination`（不再用全局 `-sdk iphonesimulator` 覆盖嵌入式 watchOS 目标）；
  - `watchos-simulator-runner.py` 负责 `AGPocketWatch` 的 `watchsimulator` 编译、`generic/platform=watchOS` 真机链接检查、`AGPocketWatchUITests` 交互式 UI 测试执行、以及 8 屏确定性截图与 `WATCH_REF_VS_SIM_COMPARISON.png` 1:1 对比拼图生成；
  - `verify_watch_esdd.py` 在 Linux / macOS 本地与 CI Gate 0 执行 Watch ESDD Spec-DAG、代码契约与无头 `208×248pt @2x` 交互式 E2E 验证。
