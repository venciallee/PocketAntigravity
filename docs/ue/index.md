# Antigravity Mobile · UE 概念稿（设计画布同步）

> **非官方概念稿（Unofficial concept），不含任何官方 Logo。**
> 本目录仅作为产品 / 交互参考，不是 Google Antigravity 官方设计，也不替代 `specs/` 中的规范或 `verification/` 下的视觉基线。

- 来源画布：[Antigravity Mobile · 概念设计](https://claude.ai/artifact/AiD6GGt5bv78HnTicyFHxZ)（`project/canvas.json` + 75 个 `project/*.dc.html`）
- 画板：iOS 34 张 · Android 33 张 · Watch 8 张
- `source/`：画布原始文件，逐字节原样保存（`canvas.json` 与全部 `.dc.html`）
- `ios/`、`android/`、`watch/`：用 Playwright（Chromium）按每张画板在 `canvas.json` 中的 `w`×`h` 视口、`deviceScaleFactor: 2` 渲染的 PNG，文件名与画板同名（去掉 `.dc.html` 后缀）。渲染时使用画布类型自带的 Design Component 运行时作为 `support.js`，仅放行 Google Fonts，并冻结 CSS 动画以保证截图确定性；画布上的圆角（`radius`）属于画框装饰，PNG 保持矩形。

## UE 映射表

| UE 编号 | iOS 画板 | Android 画板 | Watch 画板 | 对应代码（ViewController / Screen 名） | 画布标题 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **UE01** Agents Home | [`Main`](ios/Main.png)<br>[`ios-drawer`](ios/ios-drawer.png) | [`and-new`](android/and-new.png)<br>[`and-home`](android/and-home.png) | [`watch-home`](watch/watch-home.png)<br>[`watch-devices`](watch/watch-devices.png) | iOS `AgentsHomeViewController`（外壳 `AntigravityShellController`）<br>Android `AgentsHomeScreen`（外壳 `RootTabScaffold`） | iOS · New Conversation（首页）<br>iOS · 侧栏（对齐 PC Sidebar）<br>Android · New Conversation（首页）<br>Android · 导航抽屉（对齐 PC Sidebar）<br>Watch · 会话列表<br>Watch · 在线设备 |
| **UE02** Display Options | [`ios-display-options`](ios/ios-display-options.png) | [`and-display-options`](android/and-display-options.png) | — | iOS `DisplayOptionsSheetView`<br>Android `DisplayOptionsSheetContent`（`DisplayOptionsSheet.kt`） | iOS · Display Options<br>Android · Display options（Bottom sheet） |
| **UE03** 长按菜单 / Pin | [`ios-pin-menu`](ios/ios-pin-menu.png) | [`and-context-menu`](android/and-context-menu.png) | — | iOS `ConversationContextPreviewMenu`<br>Android `ConversationContextSheetScreen`（`ConversationContextSheet.kt`） | iOS · 长按菜单 / Pin<br>Android · 会话操作 / Pin（长按 Bottom sheet） |
| **UE04** 项目详情 | [`ios-project-detail`](ios/ios-project-detail.png)<br>[`ios-project`](ios/ios-project.png) | [`and-project`](android/and-project.png) | — | iOS `ProjectDetailViewController`<br>Android `ProjectDetailScreen` | iOS · 项目详情（UE04）<br>iOS · 项目长按菜单 / New Conversation in Project<br>Android · 项目详情（UE04） |
| **UE05** Create Project | [`ios-new-project`](ios/ios-new-project.png) | [`and-new-project`](android/and-new-project.png) | — | iOS `CreateProjectSheetView`<br>Android `CreateProjectScreen`（`CreateProjectDialog.kt`） | iOS · Create New Project<br>Android · New project（全屏对话框） |
| **UE06** Automations | [`ios-automations`](ios/ios-automations.png)<br>[`ios-automation-detail`](ios/ios-automation-detail.png)<br>[`ios-automation-edit`](ios/ios-automation-edit.png) | [`and-automations`](android/and-automations.png)<br>[`and-automation-detail`](android/and-automation-detail.png)<br>[`and-automation-edit`](android/and-automation-edit.png) | — | iOS `AutomationsViewController`<br>Android `AutomationsScreen` | iOS · Automations<br>iOS · Automation 详情 / 运行记录<br>iOS · Edit Schedule & Prompt（新建同表单）<br>Android · Automations（筛选 + 溢出菜单）<br>Android · Automation 详情 / 运行记录<br>Android · 编辑 Automation |
| **UE07** 对话 & 输入框 | [`ios-chat`](ios/ios-chat.png)<br>[`ios-preset`](ios/ios-preset.png) | [`and-chat`](android/and-chat.png)<br>[`and-preset`](android/and-preset.png) | [`watch-chat`](watch/watch-chat.png) | iOS `CascadeChatViewController` + `ChatComposerView` + `PermissionsSheetView`<br>Android `CascadeChatScreen`（`ChatComposerCard`） | iOS · 消息列表与输入框<br>iOS · 权限预设<br>Android · 对话与输入<br>Android · 权限预设菜单<br>Watch · 对话流 |
| **UE08** Add Context / `/` Actions | [`ios-add-context`](ios/ios-add-context.png)<br>[`ios-slash`](ios/ios-slash.png) | [`and-add-context`](android/and-add-context.png)<br>[`and-slash`](android/and-slash.png) | — | iOS `AddContextSheetView` + `ChatComposerView`（`/` slash popup）<br>Android `AddContextSheetScreen`（`AddContextSheet.kt`） | iOS · Add Context（Files / Folder / Mentions / Actions / Drive）<br>iOS · / Actions 与 Skills<br>Android · Add Context 菜单<br>Android · / Actions 与 Skills |
| **UE09** 模型与思考档位 | [`ios-model`](ios/ios-model.png) | [`and-model`](android/and-model.png) | — | iOS `ModelAndModeSheetView`<br>Android `ModelAndModeSheetScreen`（`ModelAndModeSheet.kt`） | iOS · 模型与思考档位<br>Android · 模型与思考档位（Bottom sheet） |
| **UE10** 结构化多选问答 | [`ios-ask`](ios/ios-ask.png) | [`and-ask`](android/and-ask.png) | — | iOS `StructuredQuestionCardView`<br>Android `StructuredQuestionScreen` | iOS · 结构化多选问答（可交互）<br>Android · 结构化多选问答 |
| **UE11** Implementation Plan 审阅 | [`ios-plan-review`](ios/ios-plan-review.png) | [`and-plan-review`](android/and-plan-review.png) | — | iOS `ImplementationPlanReviewViewController`<br>Android `ImplementationPlanReviewScreen` | iOS · Implementation Plan 审阅<br>Android · Implementation Plan 审阅 |
| **UE12** Turn Diff 行级审查 | [`ios-diff`](ios/ios-diff.png) | [`and-diff`](android/and-diff.png) | [`watch-code`](watch/watch-code.png)<br>[`watch-files-many`](watch/watch-files-many.png) | iOS `TurnDiffReviewViewController`<br>Android `TurnDiffReviewScreen` | iOS · Turn Diff 行级审查<br>Android · Turn Diff 行级审查<br>Watch · 改动文件（少量）<br>Watch · 改动文件（大量，按意图分组） |
| **UE13** Live Activity / Live Update | [`live-activity`](ios/live-activity.png) | [`and-live-update`](android/and-live-update.png) | [`watch-notify`](watch/watch-notify.png) | iOS `AntigravityLiveActivityWidget`（target `AGPocketLiveActivity`）+ `LiveActivityCoordinator`<br>Android `AndroidLiveUpdateBuilder` + `AgentProgressForegroundService` + `AndroidLiveUpdatesSpecGallery` | 灵动岛 / Live Activity 规格<br>Android · Live Update 通知<br>Watch · 通知（待批准） |
| 扩展 · Overview | [`ios-overview`](ios/ios-overview.png) | [`and-overview`](android/and-overview.png) | — | iOS `ConversationOverviewSheetView`<br>Android `ConversationOverviewSheet`（`V233ExtensionSheets.kt`） | iOS · Conversation Overview<br>Android · Conversation overview |
| 扩展 · `/btw` | [`ios-btw`](ios/ios-btw.png) | [`and-btw`](android/and-btw.png) | — | iOS `SideQuestionSheetView`<br>Android `SideQuestionSheet`（`V233ExtensionSheets.kt`） | iOS · /btw 旁路提问<br>Android · /btw 旁路提问 |
| 扩展 · Swarm | [`ios-swarm`](ios/ios-swarm.png) | [`and-swarm`](android/and-swarm.png) | — | iOS `SwarmBoardSheetView`<br>Android `SwarmBoardSheet`（`V233ExtensionSheets.kt`） | iOS · Agent Swarm Board<br>Android · Agent swarm board |
| 扩展 · Voice | [`ios-voice`](ios/ios-voice.png) | [`and-voice`](android/and-voice.png) | [`watch-voice`](watch/watch-voice.png) | iOS `VoiceModeSheetView` + `VoiceInputManager`<br>Android `VoiceModeSheet`（`V233ExtensionSheets.kt`） | iOS · Voice Mode（语音对话）<br>Android · Voice mode<br>Watch · 语音输入 |
| 扩展 · Artifact Viewer | [`ios-artifact`](ios/ios-artifact.png) | [`and-artifact`](android/and-artifact.png) | [`watch-artifact`](watch/watch-artifact.png) | iOS `RichArtifactViewerSheet`<br>Android `RichArtifactViewerSheet`（`TurnDiffReviewScreen.kt`） | iOS · Artifact Viewer（Markdown / 图 / 区域评论）<br>Android · Artifact viewer<br>Watch · 产物摘要 |
| 扩展 · Rules & skills | [`ios-customizations`](ios/ios-customizations.png) | [`and-customizations`](android/and-customizations.png) | — | 入口：iOS `ProjectDetailViewController` / Android `ProjectDetailScreen` 的 `project-row-skills` 行（两端均为空 action，目标页未实现）<br>现状：iOS `CustomizationsSettingsView` 仅包裹 `PermissionsSheetView`；Android Skills / Rules / MCP 面板在 `SettingsAndCustomizationsScreen` | iOS · 项目 Rules & skills（轻量 Customizations）<br>Android · 项目 Rules & skills |
| 扩展 · 欢迎页 | [`ios-welcome`](ios/ios-welcome.png) | [`and-welcome`](android/and-welcome.png) | — | iOS `AntigravityWelcomeView`<br>Android `WelcomeAndPairingScreen` | iOS · 首次启动 / 欢迎页<br>Android · 首次启动 / 欢迎页 |
| 扩展 · Cloud Relay 登录 | [`ios-signin`](ios/ios-signin.png) | [`and-signin`](android/and-signin.png) | — | iOS `CloudRelaySignInSheet`<br>Android `CloudRelaySignInScreen`（`CloudRelaySignInDialog.kt`） | iOS · Google 登录（Cloud Relay）<br>Android · Google 登录（Cloud Relay WebView） |
| 扩展 · Face ID / BiometricPrompt | [`ios-faceid`](ios/ios-faceid.png) | [`and-biometric`](android/and-biometric.png) | — | iOS `InlineCommandApprovalCardView`（`LAContext`，`StepCellViews.swift`）<br>Android `BiometricApprovalController` + `BiometricApprovalTrampolineActivity` | iOS · Face ID 批准<br>Android · BiometricPrompt（锁屏批准） |
| 扩展 · 小组件 | [`ios-widget`](ios/ios-widget.png) | [`and-widget`](android/and-widget.png) | — | iOS —（仓库仅有 `AGPocketLiveActivity`，无 WidgetKit 主屏 / 锁屏小组件）<br>Android `AntigravityAgentsGlanceWidget` | iOS · 桌面 / 锁屏小组件<br>Android · Glance 桌面小组件 |
| 扩展 · 分享 | [`ios-share`](ios/ios-share.png) | [`and-share`](android/and-share.png) | — | iOS `AntigravityShareExtensionViewController` + `AntigravityShareSheetView`（target `AGPocketShare`）<br>Android `AndroidSharePayloadParser`（`ACTION_SEND`） | iOS · 分享扩展（Send to AG Pocket）<br>Android · 分享接收（ACTION_SEND） |
| 扩展 · 离线 | [`ios-offline`](ios/ios-offline.png) | [`and-offline`](android/and-offline.png) | — | iOS `LocalProjectionStore` + Durable Outbox（`AntigravitySessionStore`）<br>Android / KMP `LocalProjectionStorage` + `CascadeChatDomainStore` outbox，`CascadeChatScreen` | iOS · 离线缓存 + 排队消息<br>Android · 离线缓存 + 排队消息 |
| 补充 · 设置 / 扫码配对 | [`ios-settings`](ios/ios-settings.png)<br>[`ios-settings-more`](ios/ios-settings-more.png)<br>[`ios-scan`](ios/ios-scan.png) | [`and-settings`](android/and-settings.png)<br>[`and-settings-more`](android/and-settings-more.png)<br>[`and-scan`](android/and-scan.png) | — | iOS `RemotePairingViewController` + `RemoteControlQRScannerSheet`<br>Android `SettingsAndCustomizationsScreen` + `RemoteControlLinkDialog` | iOS · 设置（连接 / 主题 / 语言）<br>iOS · 设置（下滑：权限 / 通知 / 关于）<br>iOS · 扫描 Remote Control 二维码<br>Android · 设置（连接 / 外观主题 / 语言）<br>Android · 设置（权限 / 通知 / 关于）<br>Android · Connect to Desktop（扫码 / 粘贴链接） |

说明：

- `UE01`–`UE13` 编号与 `specs/esdd-ir.json`、`specs/android/esdd-android-ir.json` 的状态 ID 一致；“扩展”行对应 `docs/PLATFORM_STATUS.md` §2.2 的 v2.33 能力与系统集成页；“补充”行收录不属于前两类的画板。
- 仓库目前没有 watchOS target，Watch 画板仅作概念参考，按最接近的 UE 归入对应行。
- 概念稿与现有 specs / 文档存在差异（例如 UE09 的 Planning / Fast、Display Options 分组、Workflows → Skills、Customizations 现状），本次同步**不**修改 `specs/` 与 `verification/` 视觉基线，差异清单见引入本目录的 PR 描述。

## 画板清单

| 画板 | 平台 | 尺寸（pt） | PNG（@2x） | 源文件 | 画布标题 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `Main` | ios | 390×844 | [Main.png](ios/Main.png) | [Main.dc.html](source/Main.dc.html) | iOS · New Conversation（首页） |
| `ios-drawer` | ios | 390×844 | [ios-drawer.png](ios/ios-drawer.png) | [ios-drawer.dc.html](source/ios-drawer.dc.html) | iOS · 侧栏（对齐 PC Sidebar） |
| `ios-display-options` | ios | 390×844 | [ios-display-options.png](ios/ios-display-options.png) | [ios-display-options.dc.html](source/ios-display-options.dc.html) | iOS · Display Options |
| `ios-pin-menu` | ios | 390×844 | [ios-pin-menu.png](ios/ios-pin-menu.png) | [ios-pin-menu.dc.html](source/ios-pin-menu.dc.html) | iOS · 长按菜单 / Pin |
| `ios-new-project` | ios | 390×844 | [ios-new-project.png](ios/ios-new-project.png) | [ios-new-project.dc.html](source/ios-new-project.dc.html) | iOS · Create New Project |
| `ios-project` | ios | 390×844 | [ios-project.png](ios/ios-project.png) | [ios-project.dc.html](source/ios-project.dc.html) | iOS · 项目长按菜单 / New Conversation in Project |
| `ios-project-detail` | ios | 390×844 | [ios-project-detail.png](ios/ios-project-detail.png) | [ios-project-detail.dc.html](source/ios-project-detail.dc.html) | iOS · 项目详情（UE04） |
| `ios-chat` | ios | 390×844 | [ios-chat.png](ios/ios-chat.png) | [ios-chat.dc.html](source/ios-chat.dc.html) | iOS · 消息列表与输入框 |
| `ios-add-context` | ios | 390×844 | [ios-add-context.png](ios/ios-add-context.png) | [ios-add-context.dc.html](source/ios-add-context.dc.html) | iOS · Add Context（Files / Folder / Mentions / Actions / Drive） |
| `ios-slash` | ios | 390×844 | [ios-slash.png](ios/ios-slash.png) | [ios-slash.dc.html](source/ios-slash.dc.html) | iOS · / Actions 与 Skills |
| `ios-model` | ios | 390×844 | [ios-model.png](ios/ios-model.png) | [ios-model.dc.html](source/ios-model.dc.html) | iOS · 模型与思考档位 |
| `ios-preset` | ios | 390×844 | [ios-preset.png](ios/ios-preset.png) | [ios-preset.dc.html](source/ios-preset.dc.html) | iOS · 权限预设 |
| `ios-ask` | ios | 390×844 | [ios-ask.png](ios/ios-ask.png) | [ios-ask.dc.html](source/ios-ask.dc.html) | iOS · 结构化多选问答（可交互） |
| `ios-plan-review` | ios | 390×844 | [ios-plan-review.png](ios/ios-plan-review.png) | [ios-plan-review.dc.html](source/ios-plan-review.dc.html) | iOS · Implementation Plan 审阅 |
| `ios-diff` | ios | 390×844 | [ios-diff.png](ios/ios-diff.png) | [ios-diff.dc.html](source/ios-diff.dc.html) | iOS · Turn Diff 行级审查 |
| `ios-automations` | ios | 390×844 | [ios-automations.png](ios/ios-automations.png) | [ios-automations.dc.html](source/ios-automations.dc.html) | iOS · Automations |
| `ios-automation-detail` | ios | 390×844 | [ios-automation-detail.png](ios/ios-automation-detail.png) | [ios-automation-detail.dc.html](source/ios-automation-detail.dc.html) | iOS · Automation 详情 / 运行记录 |
| `ios-automation-edit` | ios | 390×844 | [ios-automation-edit.png](ios/ios-automation-edit.png) | [ios-automation-edit.dc.html](source/ios-automation-edit.dc.html) | iOS · Edit Schedule & Prompt（新建同表单） |
| `live-activity` | ios | 1380×844 | [live-activity.png](ios/live-activity.png) | [live-activity.dc.html](source/live-activity.dc.html) | 灵动岛 / Live Activity 规格 |
| `ios-settings` | ios | 390×844 | [ios-settings.png](ios/ios-settings.png) | [ios-settings.dc.html](source/ios-settings.dc.html) | iOS · 设置（连接 / 主题 / 语言） |
| `ios-settings-more` | ios | 390×844 | [ios-settings-more.png](ios/ios-settings-more.png) | [ios-settings-more.dc.html](source/ios-settings-more.dc.html) | iOS · 设置（下滑：权限 / 通知 / 关于） |
| `ios-scan` | ios | 390×844 | [ios-scan.png](ios/ios-scan.png) | [ios-scan.dc.html](source/ios-scan.dc.html) | iOS · 扫描 Remote Control 二维码 |
| `ios-welcome` | ios | 390×844 | [ios-welcome.png](ios/ios-welcome.png) | [ios-welcome.dc.html](source/ios-welcome.dc.html) | iOS · 首次启动 / 欢迎页 |
| `ios-signin` | ios | 390×844 | [ios-signin.png](ios/ios-signin.png) | [ios-signin.dc.html](source/ios-signin.dc.html) | iOS · Google 登录（Cloud Relay） |
| `ios-overview` | ios | 390×844 | [ios-overview.png](ios/ios-overview.png) | [ios-overview.dc.html](source/ios-overview.dc.html) | iOS · Conversation Overview |
| `ios-btw` | ios | 390×844 | [ios-btw.png](ios/ios-btw.png) | [ios-btw.dc.html](source/ios-btw.dc.html) | iOS · /btw 旁路提问 |
| `ios-swarm` | ios | 390×844 | [ios-swarm.png](ios/ios-swarm.png) | [ios-swarm.dc.html](source/ios-swarm.dc.html) | iOS · Agent Swarm Board |
| `ios-voice` | ios | 390×844 | [ios-voice.png](ios/ios-voice.png) | [ios-voice.dc.html](source/ios-voice.dc.html) | iOS · Voice Mode（语音对话） |
| `ios-artifact` | ios | 390×844 | [ios-artifact.png](ios/ios-artifact.png) | [ios-artifact.dc.html](source/ios-artifact.dc.html) | iOS · Artifact Viewer（Markdown / 图 / 区域评论） |
| `ios-customizations` | ios | 390×844 | [ios-customizations.png](ios/ios-customizations.png) | [ios-customizations.dc.html](source/ios-customizations.dc.html) | iOS · 项目 Rules & skills（轻量 Customizations） |
| `ios-faceid` | ios | 390×844 | [ios-faceid.png](ios/ios-faceid.png) | [ios-faceid.dc.html](source/ios-faceid.dc.html) | iOS · Face ID 批准 |
| `ios-widget` | ios | 390×844 | [ios-widget.png](ios/ios-widget.png) | [ios-widget.dc.html](source/ios-widget.dc.html) | iOS · 桌面 / 锁屏小组件 |
| `ios-share` | ios | 390×844 | [ios-share.png](ios/ios-share.png) | [ios-share.dc.html](source/ios-share.dc.html) | iOS · 分享扩展（Send to AG Pocket） |
| `ios-offline` | ios | 390×844 | [ios-offline.png](ios/ios-offline.png) | [ios-offline.dc.html](source/ios-offline.dc.html) | iOS · 离线缓存 + 排队消息 |
| `and-new` | android | 412×915 | [and-new.png](android/and-new.png) | [and-new.dc.html](source/and-new.dc.html) | Android · New Conversation（首页） |
| `and-home` | android | 412×915 | [and-home.png](android/and-home.png) | [and-home.dc.html](source/and-home.dc.html) | Android · 导航抽屉（对齐 PC Sidebar） |
| `and-display-options` | android | 412×915 | [and-display-options.png](android/and-display-options.png) | [and-display-options.dc.html](source/and-display-options.dc.html) | Android · Display options（Bottom sheet） |
| `and-context-menu` | android | 412×915 | [and-context-menu.png](android/and-context-menu.png) | [and-context-menu.dc.html](source/and-context-menu.dc.html) | Android · 会话操作 / Pin（长按 Bottom sheet） |
| `and-project` | android | 412×915 | [and-project.png](android/and-project.png) | [and-project.dc.html](source/and-project.dc.html) | Android · 项目详情（UE04） |
| `and-new-project` | android | 412×915 | [and-new-project.png](android/and-new-project.png) | [and-new-project.dc.html](source/and-new-project.dc.html) | Android · New project（全屏对话框） |
| `and-chat` | android | 412×915 | [and-chat.png](android/and-chat.png) | [and-chat.dc.html](source/and-chat.dc.html) | Android · 对话与输入 |
| `and-add-context` | android | 412×915 | [and-add-context.png](android/and-add-context.png) | [and-add-context.dc.html](source/and-add-context.dc.html) | Android · Add Context 菜单 |
| `and-slash` | android | 412×915 | [and-slash.png](android/and-slash.png) | [and-slash.dc.html](source/and-slash.dc.html) | Android · / Actions 与 Skills |
| `and-model` | android | 412×915 | [and-model.png](android/and-model.png) | [and-model.dc.html](source/and-model.dc.html) | Android · 模型与思考档位（Bottom sheet） |
| `and-preset` | android | 412×915 | [and-preset.png](android/and-preset.png) | [and-preset.dc.html](source/and-preset.dc.html) | Android · 权限预设菜单 |
| `and-ask` | android | 412×915 | [and-ask.png](android/and-ask.png) | [and-ask.dc.html](source/and-ask.dc.html) | Android · 结构化多选问答 |
| `and-plan-review` | android | 412×915 | [and-plan-review.png](android/and-plan-review.png) | [and-plan-review.dc.html](source/and-plan-review.dc.html) | Android · Implementation Plan 审阅 |
| `and-diff` | android | 412×915 | [and-diff.png](android/and-diff.png) | [and-diff.dc.html](source/and-diff.dc.html) | Android · Turn Diff 行级审查 |
| `and-automations` | android | 412×915 | [and-automations.png](android/and-automations.png) | [and-automations.dc.html](source/and-automations.dc.html) | Android · Automations（筛选 + 溢出菜单） |
| `and-automation-detail` | android | 412×915 | [and-automation-detail.png](android/and-automation-detail.png) | [and-automation-detail.dc.html](source/and-automation-detail.dc.html) | Android · Automation 详情 / 运行记录 |
| `and-automation-edit` | android | 412×915 | [and-automation-edit.png](android/and-automation-edit.png) | [and-automation-edit.dc.html](source/and-automation-edit.dc.html) | Android · 编辑 Automation |
| `and-settings` | android | 412×915 | [and-settings.png](android/and-settings.png) | [and-settings.dc.html](source/and-settings.dc.html) | Android · 设置（连接 / 外观主题 / 语言） |
| `and-settings-more` | android | 412×915 | [and-settings-more.png](android/and-settings-more.png) | [and-settings-more.dc.html](source/and-settings-more.dc.html) | Android · 设置（权限 / 通知 / 关于） |
| `and-scan` | android | 412×915 | [and-scan.png](android/and-scan.png) | [and-scan.dc.html](source/and-scan.dc.html) | Android · Connect to Desktop（扫码 / 粘贴链接） |
| `and-welcome` | android | 412×915 | [and-welcome.png](android/and-welcome.png) | [and-welcome.dc.html](source/and-welcome.dc.html) | Android · 首次启动 / 欢迎页 |
| `and-signin` | android | 412×915 | [and-signin.png](android/and-signin.png) | [and-signin.dc.html](source/and-signin.dc.html) | Android · Google 登录（Cloud Relay WebView） |
| `and-live-update` | android | 412×915 | [and-live-update.png](android/and-live-update.png) | [and-live-update.dc.html](source/and-live-update.dc.html) | Android · Live Update 通知 |
| `and-overview` | android | 412×915 | [and-overview.png](android/and-overview.png) | [and-overview.dc.html](source/and-overview.dc.html) | Android · Conversation overview |
| `and-btw` | android | 412×915 | [and-btw.png](android/and-btw.png) | [and-btw.dc.html](source/and-btw.dc.html) | Android · /btw 旁路提问 |
| `and-swarm` | android | 412×915 | [and-swarm.png](android/and-swarm.png) | [and-swarm.dc.html](source/and-swarm.dc.html) | Android · Agent swarm board |
| `and-voice` | android | 412×915 | [and-voice.png](android/and-voice.png) | [and-voice.dc.html](source/and-voice.dc.html) | Android · Voice mode |
| `and-artifact` | android | 412×915 | [and-artifact.png](android/and-artifact.png) | [and-artifact.dc.html](source/and-artifact.dc.html) | Android · Artifact viewer |
| `and-customizations` | android | 412×915 | [and-customizations.png](android/and-customizations.png) | [and-customizations.dc.html](source/and-customizations.dc.html) | Android · 项目 Rules & skills |
| `and-biometric` | android | 412×915 | [and-biometric.png](android/and-biometric.png) | [and-biometric.dc.html](source/and-biometric.dc.html) | Android · BiometricPrompt（锁屏批准） |
| `and-widget` | android | 412×915 | [and-widget.png](android/and-widget.png) | [and-widget.dc.html](source/and-widget.dc.html) | Android · Glance 桌面小组件 |
| `and-share` | android | 412×915 | [and-share.png](android/and-share.png) | [and-share.dc.html](source/and-share.dc.html) | Android · 分享接收（ACTION_SEND） |
| `and-offline` | android | 412×915 | [and-offline.png](android/and-offline.png) | [and-offline.dc.html](source/and-offline.dc.html) | Android · 离线缓存 + 排队消息 |
| `watch-home` | watch | 208×248 | [watch-home.png](watch/watch-home.png) | [watch-home.dc.html](source/watch-home.dc.html) | Watch · 会话列表 |
| `watch-devices` | watch | 208×248 | [watch-devices.png](watch/watch-devices.png) | [watch-devices.dc.html](source/watch-devices.dc.html) | Watch · 在线设备 |
| `watch-chat` | watch | 208×248 | [watch-chat.png](watch/watch-chat.png) | [watch-chat.dc.html](source/watch-chat.dc.html) | Watch · 对话流 |
| `watch-artifact` | watch | 208×248 | [watch-artifact.png](watch/watch-artifact.png) | [watch-artifact.dc.html](source/watch-artifact.dc.html) | Watch · 产物摘要 |
| `watch-code` | watch | 208×248 | [watch-code.png](watch/watch-code.png) | [watch-code.dc.html](source/watch-code.dc.html) | Watch · 改动文件（少量） |
| `watch-files-many` | watch | 208×248 | [watch-files-many.png](watch/watch-files-many.png) | [watch-files-many.dc.html](source/watch-files-many.dc.html) | Watch · 改动文件（大量，按意图分组） |
| `watch-voice` | watch | 208×248 | [watch-voice.png](watch/watch-voice.png) | [watch-voice.dc.html](source/watch-voice.dc.html) | Watch · 语音输入 |
| `watch-notify` | watch | 208×248 | [watch-notify.png](watch/watch-notify.png) | [watch-notify.dc.html](source/watch-notify.dc.html) | Watch · 通知（待批准） |
