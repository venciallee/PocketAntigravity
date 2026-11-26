import SwiftUI
import AntigravityData

/// State `UE14_RULES_AND_SKILLS`: Mobile Rules & Skills viewer (`iOS · 项目 Rules & skills`)
/// aligned 1:1 with `docs/ue/ios/ios-customizations.png`.
/// Reachable from Left Sidebar `Customizations` and sidebar project context menus (`Project Rules & Skills`).
public struct CustomizationsSettingsView: View {
    @Bindable public var store: AntigravitySessionStore
    public var projectName: String
    public var onBack: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private enum CustomizationTab: Int, CaseIterable, Identifiable {
        case skills = 0
        case rules = 1
        case plugins = 2
        case agents = 3

        var id: Int { rawValue }
    }

    @State private var selectedTab: CustomizationTab = .skills

    public init(
        store: AntigravitySessionStore,
        projectName: String = "ledger-svc",
        onBack: (() -> Void)? = nil
    ) {
        self.store = store
        self.projectName = projectName
        self.onBack = onBack
    }

    private var catalog: CustomizationsCatalog {
        store.customizations
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                topBackBar
                titleHeader
                tokenBudgetCard
                segmentedTabsBar
                activeListCard
                if selectedTab == .skills || selectedTab == .plugins {
                    pluginsInProjectSection
                }
                desktopOnlyFootnote
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 20)
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rules-skills-screen")
    }

    // MARK: - Top Navigation

    private var topBackBar: some View {
        HStack {
            Button {
                if let onBack {
                    onBack()
                } else {
                    store.presentedSheet = nil
                    if case .rulesAndSkills = store.activeRoute {
                        store.activeRoute = .tabRoot
                    }
                    dismiss()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text(projectName)
                        .font(.system(size: 17, weight: .regular))
                }
                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                .frame(minWidth: 76, minHeight: AntigravityTheme.minTouchTargetPt, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-back")
            Spacer()
        }
    }

    private var titleHeader: some View {
        Text("Rules & skills")
            .font(.system(size: 32, weight: .bold))
            .tracking(-0.5)
            .foregroundStyle(AntigravityTheme.textPrimary)
    }

    // MARK: - Token Budget Card ("Loaded every turn · 6.2k tokens")

    private var tokenBudgetCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Loaded every turn")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(AntigravityTheme.inkLabel)
                Spacer()
                Text(catalog.loadedTokensLabel)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textSecondary)
            }

            GeometryReader { geo in
                let totalW = max(1, geo.size.width)
                HStack(spacing: 2) {
                    Capsule()
                        .fill(AntigravityTheme.accentPeriwinkle)
                        .frame(width: totalW * 0.34)
                    Capsule()
                        .fill(AntigravityTheme.statusDone)
                        .frame(width: totalW * 0.16)
                    Capsule()
                        .fill(AntigravityTheme.statusWaiting)
                        .frame(width: totalW * 0.18)
                    Capsule()
                        .fill(AntigravityTheme.surfaceElevated)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 6)

            HStack(spacing: 14) {
                legendDot(label: "Rules", color: AntigravityTheme.accentPeriwinkle)
                legendDot(label: "Skills", color: AntigravityTheme.statusDone)
                legendDot(label: "Plugins", color: AntigravityTheme.statusWaiting)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AntigravityTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rules-token-budget-card")
    }

    private func legendDot(label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(AntigravityTheme.inkSecondary.opacity(0.65))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(color)
        }
    }

    // MARK: - 4-Segment Control (Skills 5 | Rules 4 | Plugins 2 | Agents 1)

    private var segmentedTabsBar: some View {
        let labels: [(CustomizationTab, String)] = [
            (.skills, "Skills \(catalog.skills.count)"),
            (.rules, "Rules \(catalog.rules.count)"),
            (.plugins, "Plugins \(catalog.plugins.count)"),
            (.agents, "Agents \(catalog.customAgents.count)")
        ]
        return HStack(spacing: 3) {
            ForEach(labels, id: \.0.id) { tab, title in
                let isSelected = (selectedTab == tab)
                Button {
                    selectedTab = tab
                } label: {
                    Text(title)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            Group {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(AntigravityTheme.surfaceActiveTabSlot)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("customizations-tab-\(tab.rawValue)")
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AntigravityTheme.surfaceSubtleBox)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Active Tab Catalog Card

    @ViewBuilder
    private var activeListCard: some View {
        switch selectedTab {
        case .skills:
            VStack(spacing: 0) {
                ForEach(Array(catalog.skills.enumerated()), id: \.element.id) { idx, skill in
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: skill.scope == "Plugin" ? "puzzlepiece.extension" : "sparkle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(skill.name)
                                    .font(.system(size: 15.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.textPrimary)
                                    .lineLimit(1)
                                if skill.scope == "Global" || skill.scope == "Plugin" {
                                    scopeBadge(skill.scope)
                                }
                            }
                            Text(skill.description)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9.5)
                    .accessibilityIdentifier("skill-row-\(skill.name)")

                    if idx < catalog.skills.count - 1 {
                        Divider()
                            .overlay(AntigravityTheme.subtleDivider)
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )

        case .rules:
            VStack(spacing: 0) {
                ForEach(Array(catalog.rules.enumerated()), id: \.element.id) { idx, rule in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .frame(width: 22)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(rule.name)
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.textPrimary)
                                scopeBadge(rule.scope)
                            }
                            Text(rule.preview)
                                .font(.system(size: 13))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("rule-row-\(rule.name)")

                    if idx < catalog.rules.count - 1 {
                        Divider()
                            .overlay(AntigravityTheme.subtleDivider)
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )

        case .plugins:
            EmptyView()

        case .agents:
            VStack(spacing: 0) {
                ForEach(Array(catalog.customAgents.enumerated()), id: \.element) { idx, agent in
                    HStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent)
                                .font(.system(size: 15.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                            Text("Custom persona · .agents/agents/\(agent).md")
                                .font(.system(size: 13))
                                .foregroundStyle(AntigravityTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("agent-row-\(agent)")

                    if idx < catalog.customAgents.count - 1 {
                        Divider()
                            .overlay(AntigravityTheme.subtleDivider)
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - PLUGINS IN THIS PROJECT

    private var pluginsInProjectSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PLUGINS IN THIS PROJECT")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(AntigravityTheme.textMuted)
                .padding(.leading, 2)
                .padding(.top, 2)

            VStack(spacing: 0) {
                ForEach(Array(catalog.plugins.enumerated()), id: \.element.id) { idx, plugin in
                    let hasError = (plugin.mcpStartupError != nil) || plugin.description.lowercased().contains("api key")
                    HStack(spacing: 9) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.textPrimary)
                            Text(plugin.mcpStartupError ?? plugin.description)
                                .font(.system(size: 12.5))
                                .foregroundStyle(hasError ? AntigravityTheme.statusError : AntigravityTheme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.84)
                        }
                        .layoutPriority(1)

                        Spacer(minLength: 4)

                        scopeBadge(plugin.scope)
                            .fixedSize(horizontal: true, vertical: false)

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { plugin.isEnabled },
                                set: { enabled in
                                    store.togglePlugin(plugin.id, isEnabled: enabled)
                                }
                            )
                        )
                        .labelsHidden()
                        .tint(AntigravityTheme.statusDone)
                        .accessibilityIdentifier("switch-plugin-\(plugin.id)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("plugin-row-\(plugin.id)")

                    if idx < catalog.plugins.count - 1 {
                        Divider()
                            .overlay(AntigravityTheme.subtleDivider)
                            .padding(.leading, 42)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )
        }
    }

    private func scopeBadge(_ scope: String) -> some View {
        let isGlobal = scope.caseInsensitiveCompare("Global") == .orderedSame
        return Text(scope)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isGlobal ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isGlobal ? AntigravityTheme.surfaceSelectionTint : AntigravityTheme.surfaceBadge)
            )
    }

    private var desktopOnlyFootnote: some View {
        Text("Phone can view and switch plugins on or off. Installing from Marketplace, editing rules or SKILL.md, and entering API keys stay in Antigravity Desktop → Customizations.")
            .font(.system(size: 12.5, weight: .regular))
            .lineSpacing(2.5)
            .foregroundStyle(AntigravityTheme.textSecondary)
            .padding(.top, 2)
    }
}
