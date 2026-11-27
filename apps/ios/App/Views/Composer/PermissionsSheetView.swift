import SwiftUI
import AntigravityData

/// Reusable Antigravity 2.x Local & Remote Permissions preset card (`Request Review`, `Default`, `Auto`, `Turbo`).
/// Mirrors Antigravity Desktop's `Remote Permissions` / `Permissions` selector in Matte Obsidian + Liquid Glass.
public struct PermissionsPresetListCard: View {
    @Bindable public var store: AntigravitySessionStore
    public var isRemoteOverride: Bool?
    public var accessibilityIdPrefix: String
    public var footerTextOverride: String?
    public var onSelectPreset: ((AgentPermissionPreset) -> Void)?

    public init(
        store: AntigravitySessionStore,
        isRemoteOverride: Bool? = nil,
        accessibilityIdPrefix: String = "permission-row",
        footerTextOverride: String? = nil,
        onSelectPreset: ((AgentPermissionPreset) -> Void)? = nil
    ) {
        self.store = store
        self.isRemoteOverride = isRemoteOverride
        self.accessibilityIdPrefix = accessibilityIdPrefix
        self.footerTextOverride = footerTextOverride
        self.onSelectPreset = onSelectPreset
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var isRemote: Bool {
        isRemoteOverride ?? store.isActiveSessionCloud
    }

    private var selectedPreset: AgentPermissionPreset {
        store.permissionPreset(isRemote: isRemote)
    }

    private var presets: [AgentPermissionPreset] {
        AgentPermissionPreset.availablePresets(isRemote: isRemote)
    }

    private var defaultPreset: AgentPermissionPreset {
        AgentPermissionPreset.defaultPreset(isRemote: isRemote)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                ForEach(Array(presets.enumerated()), id: \.element.id) { idx, preset in
                    presetRow(preset)
                    if idx < presets.count - 1 {
                        Divider()
                            .overlay(AntigravityTheme.subtleDivider)
                            .padding(.leading, 56)
                    }
                }
            }
            .background(AntigravityTheme.surfaceSheetGroup)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )

            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.top, 1.5)
                Text(
                    footerTextOverride ?? (
                        isRemote
                            ? lang.t("Remote sessions default to Turbo inside an isolated Cloud VM.", "远程会话在隔离的云端虚拟机中默认使用极速模式。")
                            : lang.t("Controls terminal commands and tool approvals on the next turn.", "控制下一轮对话的终端命令与工具审批策略。")
                    )
                )
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(AntigravityTheme.inkMuted)
            .padding(.leading, 4)
            .padding(.top, 2)
        }
    }

    private func presetRow(_ preset: AgentPermissionPreset) -> some View {
        let isSelected = (selectedPreset == preset)
        let isDefault = preset == defaultPreset
        let accentColor: Color = (preset == .turbo) ? AntigravityTheme.statusWaiting : AntigravityTheme.accentPeriwinkle

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                store.setActivePermissionPreset(preset, isRemoteOverride: isRemote)
            }
            onSelectPreset?(preset)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? accentColor.opacity(0.16) : AntigravityTheme.surfaceSubtleBox)
                        .frame(width: 30, height: 30)
                    Image(systemName: preset.semanticIcon.sfSymbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? accentColor : AntigravityTheme.inkSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(preset.localizedTitle(for: lang))
                            .font(.system(size: 15.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .lineLimit(1)

                        if isDefault && preset != .defaultPolicy {
                            HStack(spacing: 3) {
                                Text(lang.t("Default", "默认"))
                                Image(systemName: "info.circle")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(AntigravityTheme.inkSecondary.opacity(0.14))
                            .clipShape(Capsule())
                        }
                    }

                    Text(preset.localizedSummaryDescription(for: lang))
                        .font(.system(size: 12.5))
                        .foregroundStyle(isSelected ? AntigravityTheme.inkLabel : AntigravityTheme.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(isSelected ? accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(accessibilityIdPrefix)-\(preset.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityValue(isSelected ? "selected" : "unselected")
    }
}

/// Compact native iOS sheet for selecting `Remote Permissions` / `Permissions` directly from the composer shield button.
public struct PermissionsSheetView: View {
    @Bindable public var store: AntigravitySessionStore
    public var isRemoteOverride: Bool?
    public var onDismiss: (() -> Void)?

    public static let sheetSurfaceColor = AntigravityTheme.surfaceSheet

    public init(
        store: AntigravitySessionStore,
        isRemoteOverride: Bool? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.isRemoteOverride = isRemoteOverride
        self.onDismiss = onDismiss
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var resolvedIsRemote: Bool {
        isRemoteOverride ?? store.isActiveSessionCloud
    }

    private var headerTitle: String {
        resolvedIsRemote
            ? lang.t("Remote Permissions", "远程权限")
            : lang.t("Permissions", "权限设置")
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(headerTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)

                HStack {
                    Spacer()
                    Button {
                        onDismiss?()
                    } label: {
                        Text(lang.t("Done", "完成"))
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(AntigravityTheme.accentPeriwinkle.opacity(0.14))
                            .overlay(
                                Capsule()
                                    .strokeBorder(AntigravityTheme.accentPeriwinkle.opacity(0.28), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                            .frame(
                                minWidth: AntigravityTheme.minTouchTargetPt,
                                minHeight: AntigravityTheme.minTouchTargetPt,
                                alignment: .trailing
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-permissions-done")
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            ScrollView(.vertical, showsIndicators: false) {
                PermissionsPresetListCard(
                    store: store,
                    isRemoteOverride: resolvedIsRemote
                )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Self.sheetSurfaceColor.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: store.permissionPreset(isRemote: resolvedIsRemote))
    }
}

/// State `UE07B_PERMISSIONS_PRESET`: Anchored composer Permissions Preset popover (`docs/ue/ios/ios-preset.png`).
public struct PermissionsPresetPopoverView: View {
    @Bindable public var store: AntigravitySessionStore
    public var isRemoteOverride: Bool?
    public var showHomeBackdrop: Bool
    public var onDismiss: (() -> Void)?
    public var onOpenSettings: (() -> Void)?

    public init(
        store: AntigravitySessionStore,
        isRemoteOverride: Bool? = nil,
        showHomeBackdrop: Bool = true,
        onDismiss: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.store = store
        self.isRemoteOverride = isRemoteOverride
        self.showHomeBackdrop = showHomeBackdrop
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var resolvedIsRemote: Bool {
        isRemoteOverride ?? store.isActiveSessionCloud
    }

    private var presets: [AgentPermissionPreset] {
        AgentPermissionPreset.availablePresets(isRemote: resolvedIsRemote)
    }

    private var selectedPreset: AgentPermissionPreset {
        store.permissionPreset(isRemote: resolvedIsRemote)
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Dimmed New Conversation backdrop (`ios-preset.png`)
            Group {
                if showHomeBackdrop {
                    VStack {
                        Spacer()
                        Text(store.homeCompactBackdropGreetingText)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(AntigravityTheme.textPrimary.opacity(0.32))
                            .padding(.bottom, 120)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
                } else {
                    Color.black.opacity(0.45).ignoresSafeArea()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onDismiss?()
            }

            VStack(spacing: 12) {
                // Anchored Popover Card aligned above `🛡 Default ⌄` pill
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        resolvedIsRemote
                            ? lang.t("Remote Permissions", "远程权限")
                            : lang.t("Permissions for this conversation", "当前对话权限")
                    )
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                    ForEach(presets) { preset in
                        let isSelected = (selectedPreset == preset)
                        let shieldColor: Color = {
                            if isSelected { return AntigravityTheme.accentPeriwinkle }
                            if preset == .turbo { return AntigravityTheme.statusWaiting }
                            return AntigravityTheme.textBody
                        }()
                        Button {
                            store.setActivePermissionPreset(preset, isRemoteOverride: resolvedIsRemote)
                            onDismiss?()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "shield")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(shieldColor)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.localizedTitle(for: lang))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AntigravityTheme.textPrimary)
                                    Text(preset.localizedSummaryDescription(for: lang))
                                        .font(.system(size: 13.5, weight: .regular))
                                        .foregroundStyle(AntigravityTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14.5, weight: .bold))
                                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                        .padding(.top, 4)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(isSelected ? AntigravityTheme.surfaceElevated : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .accessibilityIdentifier("preset-option-\(preset.rawValue)")
                    }

                    Divider()
                        .overlay(AntigravityTheme.subtleDivider)
                        .padding(.top, 4)

                    Button {
                        if let onOpenSettings {
                            onOpenSettings()
                        } else {
                            store.activeRoute = .pairingSettings
                        }
                        onDismiss?()
                    } label: {
                        HStack {
                            Text(lang.t("Default for new turns: Settings › Permissions", "新对话默认权限：设置 › 权限"))
                                .font(.system(size: 13.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("preset-settings-footer")
                }
                .frame(maxWidth: 324)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AntigravityTheme.surfacePopover)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
                .shadow(color: AntigravityTheme.glassShadow, radius: 20, x: 0, y: 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 14)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("permissions-preset-popover")

                if showHomeBackdrop {
                    dockedBackdropComposerBar(
                        highlightPermissions: true,
                        highlightAdd: false,
                        draftText: nil,
                        language: lang
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        }
        .background((showHomeBackdrop ? AntigravityTheme.canvasObsidian : Color.clear).ignoresSafeArea())
    }
}

/// State `UE08B_SLASH_MENU`: Categorized Slash Actions & Skills menu (`docs/ue/ios/ios-slash.png`).
public struct SlashCommandMenuOverlayView: View {
    @Bindable public var store: AntigravitySessionStore
    public var showHomeBackdrop: Bool
    public var onSelectCommand: ((String) -> Void)?
    public var onDismiss: (() -> Void)?

    public init(
        store: AntigravitySessionStore,
        showHomeBackdrop: Bool = true,
        onSelectCommand: ((String) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.showHomeBackdrop = showHomeBackdrop
        self.onSelectCommand = onSelectCommand
        self.onDismiss = onDismiss
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var actionItems: [(cmd: String, desc: String)] {
        var items: [(String, String)] = [
            ("/plan", lang.t("Explore first, then draft a reviewable plan", "先探索代码库，再起草可审查的方案")),
            ("/goal", lang.t("Keep working until the goal is verified", "持续执行直至目标验证通过")),
            ("/schedule", lang.t("Wake this conversation later", "稍后自动唤醒此对话")),
            ("/automation", lang.t("Set up a recurring automation", "配置定时循环自动化任务"))
        ]
        if store.includeSideQuestionInSlashMenu {
            items.append(("/btw", lang.t("Side question in a read-only fork", "在只读分支中提出临时旁路问题")))
        }
        return items
    }

    private var skillItems: [(cmd: String, desc: String)] {
        [
            ("/go-testing", lang.t("Table-driven tests with -race", "带 -race 检测的表驱动测试")),
            ("/api-review", lang.t("Check handlers against API rules", "按 API 规范检查接口处理器"))
        ]
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if showHomeBackdrop {
                    AntigravityTheme.canvasObsidian.ignoresSafeArea()
                } else {
                    Color.black.opacity(0.45).ignoresSafeArea()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onDismiss?()
            }

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lang.t("Actions", "快捷指令"))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    ForEach(Array(actionItems.enumerated()), id: \.element.cmd) { idx, item in
                        let isHighlighted = (idx == 0)
                        Button {
                            if let onSelectCommand {
                                onSelectCommand(item.cmd)
                            } else {
                                store.composerDraftText = "\(item.cmd) "
                            }
                            onDismiss?()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "slash.circle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isHighlighted ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.textSecondary)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isHighlighted ? AntigravityTheme.surfaceSelectionTint : AntigravityTheme.surfaceElevated)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.cmd)
                                        .font(.system(size: 15.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(AntigravityTheme.textPrimary)
                                    Text(item.desc)
                                        .font(.system(size: 13))
                                        .foregroundStyle(AntigravityTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isHighlighted ? AntigravityTheme.surfaceElevated : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .accessibilityIdentifier("slash-item-\(item.cmd.dropFirst())")
                    }

                    Text(lang.t("Skills", "技能"))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    ForEach(skillItems, id: \.cmd) { item in
                        Button {
                            if let onSelectCommand {
                                onSelectCommand(item.cmd)
                            } else {
                                store.composerDraftText = "\(item.cmd) "
                            }
                            onDismiss?()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "cube")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(AntigravityTheme.textSecondary)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(AntigravityTheme.surfaceElevated)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.cmd)
                                        .font(.system(size: 15.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(AntigravityTheme.textPrimary)
                                    Text(item.desc)
                                        .font(.system(size: 13))
                                        .foregroundStyle(AntigravityTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .accessibilityIdentifier("slash-skill-\(item.cmd.dropFirst())")
                    }
                    .padding(.bottom, 10)
                }
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AntigravityTheme.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
                .padding(.horizontal, 14)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("slash-menu-card")

                if showHomeBackdrop {
                    dockedBackdropComposerBar(
                        highlightPermissions: false,
                        highlightAdd: false,
                        draftText: "/",
                        language: lang
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        }
        .background((showHomeBackdrop ? AntigravityTheme.canvasObsidian : Color.clear).ignoresSafeArea())
    }
}

/// Shared dimmed docked composer backdrop used by anchored overlays (`UE07B`, `UE08`, `UE08B`).
@ViewBuilder
func dockedBackdropComposerBar(
    highlightPermissions: Bool,
    highlightAdd: Bool,
    draftText: String?,
    language: AppLanguage = .english
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 14) {
            Text("ledger-svc")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(AntigravityTheme.textSecondary)
            Text(language.t("Repo default", "仓库默认"))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(AntigravityTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 6)

        VStack(alignment: .leading, spacing: 12) {
            Text(draftText ?? language.t("Ask anything, @ to mention, / for actions", "输入任何问题，@ 引用上下文，/ 使用快捷指令"))
                .font(.system(size: 16, weight: draftText != nil ? .medium : .regular))
                .foregroundStyle(draftText != nil ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary.opacity(0.65))
                .padding(.horizontal, 4)

            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(highlightAdd ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(highlightAdd ? AntigravityTheme.surfaceElevated : Color.clear))

                HStack(spacing: 4) {
                    Text("Gemini 4 Neon")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textBody)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }

                Spacer()

                HStack(spacing: 5) {
                    if highlightPermissions {
                        Image(systemName: "shield")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    Text(language.t("Default", "默认"))
                        .font(.system(size: 13.5, weight: .medium))
                    if highlightPermissions {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(highlightPermissions ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
                .padding(.horizontal, highlightPermissions ? 12 : 4)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(highlightPermissions ? AntigravityTheme.surfaceElevated : Color.clear)
                )

                Circle()
                    .fill(draftText != nil ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.surfaceElevated)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Group {
                            if draftText != nil {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                            }
                        }
                    )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AntigravityTheme.surfaceObsidian)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
        )
    }
    .padding(10)
    .background(
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(AntigravityTheme.surfaceCard)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
    )
}
