import SwiftUI
import AntigravityData

/// Unified Antigravity 2.0 Settings & Customizations Hub (v2.26 - v2.33):
/// 1. Permissions & Terminal Sandbox (`Request Review` / `Default` / `Auto` / `Turbo` + Deny/Ask/Allow rules)
/// 2. Customizations Hub with collapsible counts (Skills, Rules, Custom Agents, MCP Servers + Restart, Plugins Marketplace + Featured Partner badges, Lifecycle Hooks)
/// 3. Appearance & Notifications (`Software Engineering` vs `Knowledge Work`, Theme, 12/14/16pt Font Size, Proactive Notifications)
public struct CustomizationsSettingsView: View {
    @Bindable private var store: AntigravitySessionStore
    @State private var expandSkills: Bool = true
    @State private var expandRules: Bool = false
    @State private var expandMcp: Bool = true
    @State private var expandPlugins: Bool = true
    @State private var expandHooks: Bool = false
    @State private var newRuleTarget: String = ""
    @State private var newRuleList: PermissionRuleListKind = .allow
    @State private var newRuleAction: PermissionRuleAction = .command
    @Environment(\.dismiss) private var dismiss

    public init(store: AntigravitySessionStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    permissionsSection
                    customizationsHubSection
                    appearanceSection
                }
                .padding(16)
            }
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
            .navigationTitle("Permissions & Customizations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        store.saveAppearancePreferences()
                        store.presentedSheet = nil
                        dismiss()
                    }
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }
            }
            .task {
                await store.refreshCustomizations()
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("sheet_customizations_settings")
    }

    // MARK: - 1. Permissions & Terminal Sandbox

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Permissions & Terminal Sandbox", systemImage: "shield.lefthalf.filled")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AntigravityTheme.inkReading)

            ForEach(AgentPermissionPreset.concretePresets) { preset in
                let isSelected = store.appearancePreferences.globalPermissionPreset == preset
                Button {
                    store.appearancePreferences.globalPermissionPreset = preset
                    store.appearancePreferences.terminalSandboxEnabled = preset.usesTerminalSandbox
                    store.saveAppearancePreferences()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.inkMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(preset.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                if preset.usesTerminalSandbox {
                                    Text("SANDBOX")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(AntigravityTheme.statusDone)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AntigravityTheme.statusDone.opacity(0.15), in: Capsule())
                                }
                            }
                            Text(preset.shortDescription)
                                .font(.system(size: 12))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        isSelected ? AntigravityTheme.surfaceElevated : AntigravityTheme.surfaceObsidian,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
            }

            // Fine-grained Deny / Ask / Allow Rule List
            VStack(alignment: .leading, spacing: 8) {
                Text("RULES (\(store.permissionRules.count))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkSecondary)

                ForEach(store.permissionRules) { rule in
                    HStack {
                        Text(rule.list.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ruleColor(rule.list))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(ruleColor(rule.list).opacity(0.15), in: Capsule())
                        Text(rule.formattedRule)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AntigravityTheme.inkReading)
                        Spacer()
                        Button {
                            store.removePermissionRule(id: rule.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(AntigravityTheme.inkMuted)
                        }
                    }
                    .padding(8)
                    .background(AntigravityTheme.surfaceObsidian, in: RoundedRectangle(cornerRadius: 10))
                }

                HStack(spacing: 8) {
                    Picker("List", selection: $newRuleList) {
                        ForEach(PermissionRuleListKind.allCases, id: \.self) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AntigravityTheme.accentPeriwinkle)

                    Picker("Action", selection: $newRuleAction) {
                        ForEach(PermissionRuleAction.allCases, id: \.self) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AntigravityTheme.accentPeriwinkle)

                    TextField("pattern (e.g. git *)", text: $newRuleTarget)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .padding(8)
                        .background(AntigravityTheme.surfaceObsidian, in: RoundedRectangle(cornerRadius: 8))

                    Button("Add") {
                        let t = newRuleTarget.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        store.addPermissionRule(PermissionRuleEntry(list: newRuleList, action: newRuleAction, target: t))
                        newRuleTarget = ""
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AntigravityTheme.accentPeriwinkle, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }

    // MARK: - 2. Customizations Hub (Collapsible Sections with Counts)

    private var customizationsHubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Customizations Hub", systemImage: "puzzlepiece.extension")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AntigravityTheme.inkReading)

            // Skills
            DisclosureGroup("Skills (\(store.customizations.skills.count))", isExpanded: $expandSkills) {
                VStack(spacing: 8) {
                    ForEach(store.customizations.skills) { skill in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("/\(skill.name)")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                Text(skill.description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                            }
                            Spacer()
                            Text(skill.scope)
                                .font(.system(size: 11))
                                .foregroundStyle(AntigravityTheme.inkMuted)
                        }
                        .padding(8)
                        .background(AntigravityTheme.surfaceObsidian, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.top, 6)
            }
            .foregroundStyle(AntigravityTheme.inkReading)

            // Rules
            DisclosureGroup("Rules (\(store.customizations.rules.count))", isExpanded: $expandRules) {
                VStack(spacing: 8) {
                    ForEach(store.customizations.rules) { rule in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(rule.name) · \(rule.scope)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkReading)
                            Text(rule.preview)
                                .font(.system(size: 12))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(AntigravityTheme.surfaceObsidian, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.top, 6)
            }
            .foregroundStyle(AntigravityTheme.inkReading)

            // MCP Servers + One-Tap Restart
            DisclosureGroup("MCP Servers (\(store.customizations.mcpServers.count))", isExpanded: $expandMcp) {
                VStack(spacing: 8) {
                    ForEach(store.customizations.mcpServers) { server in
                        HStack {
                            Circle()
                                .fill(server.state == .connected ? AntigravityTheme.statusDone : AntigravityTheme.statusError)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(server.name) · \(server.toolCount) tools")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                Text(server.errorMessage ?? "\(server.transport) · \(server.oauthConnected ? "OAuth connected" : "Local")")
                                    .font(.system(size: 11))
                                    .foregroundStyle(server.errorMessage != nil ? AntigravityTheme.statusError : AntigravityTheme.inkSecondary)
                            }
                            Spacer()
                            Button("Restart") {
                                store.restartMcpServer(server.name)
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AntigravityTheme.surfaceElevated, in: Capsule())
                        }
                        .padding(8)
                        .background(AntigravityTheme.surfaceObsidian, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.top, 6)
            }
            .foregroundStyle(AntigravityTheme.inkReading)

            // Plugins Marketplace
            DisclosureGroup("Plugins Marketplace (\(store.customizations.plugins.count))", isExpanded: $expandPlugins) {
                VStack(spacing: 8) {
                    ForEach(store.customizations.plugins) { plugin in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(plugin.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AntigravityTheme.inkReading)
                                    if plugin.isFeaturedPartner {
                                        Text("PARTNER")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(AntigravityTheme.accentPeriwinkle.opacity(0.16), in: Capsule())
                                    }
                                }
                                Text(plugin.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                            }
                            Spacer()
                            if plugin.isInstalled {
                                Toggle("", isOn: Binding(
                                    get: { plugin.isEnabled },
                                    set: { store.togglePlugin(plugin.id, isEnabled: $0) }
                                ))
                                .labelsHidden()
                                .tint(AntigravityTheme.accentPeriwinkle)
                            } else {
                                Button("Install") {
                                    store.installPlugin(plugin.id)
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AntigravityTheme.accentPeriwinkle, in: Capsule())
                            }
                        }
                        .padding(8)
                        .background(AntigravityTheme.surfaceObsidian, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.top, 6)
            }
            .foregroundStyle(AntigravityTheme.inkReading)

            // Lifecycle Hooks
            DisclosureGroup("Hooks (\(store.customizations.hooks.count))", isExpanded: $expandHooks) {
                VStack(spacing: 8) {
                    ForEach(store.customizations.hooks) { hook in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(hook.eventName) [\(hook.matcher)]")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkReading)
                            Text(hook.command)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(AntigravityTheme.surfaceObsidian, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.top, 6)
            }
            .foregroundStyle(AntigravityTheme.inkReading)
        }
        .padding(14)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }

    // MARK: - 3. Appearance, Interface Layout & Proactive Notifications

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Appearance & Notifications", systemImage: "paintbrush")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AntigravityTheme.inkReading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Interface Layout")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                Picker("Interface Layout", selection: $store.appearancePreferences.interfaceLayout) {
                    ForEach(InterfaceLayoutMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.appearancePreferences.interfaceLayout) { _, _ in
                    store.saveAppearancePreferences()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Theme Preset")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                Picker("Theme", selection: $store.appearancePreferences.theme) {
                    ForEach(AppThemePreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .tint(AntigravityTheme.accentPeriwinkle)
                .onChange(of: store.appearancePreferences.theme) { _, _ in
                    store.saveAppearancePreferences()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Chat Font Size")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                Picker("Font Size", selection: $store.appearancePreferences.fontSizePt) {
                    Text("12 pt").tag(12)
                    Text("14 pt").tag(14)
                    Text("16 pt").tag(16)
                }
                .pickerStyle(.segmented)
                .onChange(of: store.appearancePreferences.fontSizePt) { _, _ in
                    store.saveAppearancePreferences()
                }
            }

            Toggle("Notify on Waiting Approval & Run Complete", isOn: $store.appearancePreferences.notificationsEnabled)
                .font(.system(size: 13))
                .foregroundStyle(AntigravityTheme.inkReading)
                .tint(AntigravityTheme.accentPeriwinkle)
                .onChange(of: store.appearancePreferences.notificationsEnabled) { _, _ in
                    store.saveAppearancePreferences()
                    NotificationCoordinator.shared.requestAuthorizationIfNeeded(preferences: store.appearancePreferences)
                }

            Toggle("Suppress Notification on Manual Stop", isOn: $store.appearancePreferences.suppressManualStopNotification)
                .font(.system(size: 13))
                .foregroundStyle(AntigravityTheme.inkReading)
                .tint(AntigravityTheme.accentPeriwinkle)
                .onChange(of: store.appearancePreferences.suppressManualStopNotification) { _, _ in
                    store.saveAppearancePreferences()
                }
        }
        .padding(14)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }

    private func ruleColor(_ kind: PermissionRuleListKind) -> Color {
        switch kind {
        case .deny: return AntigravityTheme.statusError
        case .ask: return AntigravityTheme.statusWaiting
        case .allow: return AntigravityTheme.statusDone
        }
    }
}
