import SwiftUI
import AntigravityData

/// State `UE09_MODEL_AND_MODE`: Official Model Picker sheet (`docs/ue/ios/ios-model.png`).
/// Per official Google Antigravity 2.x docs, Planning/Fast mode cards are removed (planning is `/plan`).
/// Displays `Orchestrator` (`Neon plans · Hydrogen executes`), `Gemini 4 Neon` `[New]` with 4-level
/// thinking segmented control (`Low` / `Medium` / `High` / `Extra High`), primary models,
/// expandable `More models`, and `Five Hour Limit Remaining` / `Weekly Limit Remaining` quota bars.
public struct ModelAndModeSheetView: View {
    @Bindable public var store: AntigravitySessionStore
    public var isPresentedAsNativeSheet: Bool
    public var onSelectConfiguration: ((String, String, String) -> Void)?
    public var onDismiss: (() -> Void)?

    public static let sheetSurfaceColor = AntigravityTheme.surfaceSheet

    @State private var showMoreModels: Bool = false
    @State private var showUsageExpanded: Bool = false

    public init(
        store: AntigravitySessionStore,
        isPresentedAsNativeSheet: Bool = false,
        onSelectConfiguration: ((String, String, String) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.isPresentedAsNativeSheet = isPresentedAsNativeSheet
        self.onSelectConfiguration = onSelectConfiguration
        self.onDismiss = onDismiss
    }

    private var catalogModels: [CascadeModelConfig] {
        store.availableModels.isEmpty ? CascadeModelConfig.liveDefaultCatalog : store.availableModels
    }

    private var orchestratorModel: CascadeModelConfig {
        catalogModels.first(where: \.isOrchestrator)
            ?? CascadeModelConfig(
                modelId: "MODEL_ORCHESTRATOR_NEON",
                displayName: "Orchestrator",
                subtitle: "Neon plans · Hydrogen executes",
                isOrchestrator: true,
                plannerModelName: "Gemini 4 Neon",
                executorModelName: "Gemini 4 Hydrogen",
                supportedEfforts: []
            )
    }

    private var primaryModels: [CascadeModelConfig] {
        let nonOrch = catalogModels.filter { !$0.isOrchestrator }
        let preferredIds = [
            "MODEL_GOOGLE_GEMINI_4_NEON",
            "MODEL_GOOGLE_GEMINI_4_CARBON",
            "MODEL_GOOGLE_GEMINI_4_ARGON",
            "MODEL_GOOGLE_GEMINI_4_HYDROGEN",
            "MODEL_CLAUDE_5_5_OPUS_THINKING",
            "MODEL_GOOGLE_GEMINI_3_8_FLASH"
        ]
        var ordered: [CascadeModelConfig] = []
        for pid in preferredIds {
            if let found = nonOrch.first(where: { $0.modelId == pid }) {
                ordered.append(found)
            }
        }
        if ordered.isEmpty {
            return Array(nonOrch.prefix(6))
        }
        return ordered
    }

    private var extraModels: [CascadeModelConfig] {
        let primaryIds = Set(primaryModels.map(\.modelId))
        return catalogModels.filter { !$0.isOrchestrator && !primaryIds.contains($0.modelId) }
    }

    public var body: some View {
        Group {
            if isPresentedAsNativeSheet {
                sheetInnerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Self.sheetSurfaceColor.ignoresSafeArea())
            } else {
                ZStack(alignment: .bottom) {
                    AntigravityTheme.canvasObsidian.ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { applyAndDismiss() }

                    sheetInnerContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 28,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 28,
                                style: .continuous
                            )
                            .fill(Self.sheetSurfaceColor)
                        )
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 28,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 28,
                                style: .continuous
                            )
                            .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                        )
                        .padding(.top, 118)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: store.selectedModelConfig.modelId)
        .sensoryFeedback(.selection, trigger: store.selectedModelConfig.effort)
        .task {
            if store.hasPairedBackend || store.isLiveBackendConnected {
                await store.refreshModelCatalog()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("model-picker-sheet")
    }

    // MARK: - Sheet Inner Content

    private var sheetInnerContent: some View {
        VStack(spacing: 0) {
            if !isPresentedAsNativeSheet {
                Capsule()
                    .fill(AntigravityTheme.sheetHandle)
                    .frame(width: 38, height: 4.5)
                    .padding(.top, 10)
            }

            // Header: centered `Model`, trailing blue `Done`
            ZStack {
                Text("Model")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkReading)

                HStack {
                    Spacer()
                    Button {
                        applyAndDismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 16.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .frame(minWidth: 52, minHeight: AntigravityTheme.minTouchTargetPt, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-model-done")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, isPresentedAsNativeSheet ? 10 : 6)
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    groupedModelCard
                    quotaLimitsFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Single Grouped Model Card (`ios-model.png`)

    private var groupedModelCard: some View {
        let orch = orchestratorModel
        let isOrchSelected = store.selectedModelConfig.isOrchestrator

        return VStack(spacing: 0) {
            // Row 0: Orchestrator
            Button {
                selectModelOption(orch)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Orchestrator")
                            .font(.system(size: 16.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.inkReading)
                        Text("Neon plans · Hydrogen executes")
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                    }
                    Spacer()
                    if isOrchSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(isOrchSelected ? AntigravityTheme.surfaceSelectionTint : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("model-row-orchestrator")

            Divider().overlay(AntigravityTheme.subtleDivider)

            // Primary Models (`Gemini 4 Neon` + inline 4-segment effort, Carbon, Argon, Hydrogen, Claude Opus 5.5, Gemini 3.8 Flash)
            ForEach(Array(primaryModels.enumerated()), id: \.element.modelId) { idx, model in
                modelRowView(model)
                if idx < primaryModels.count - 1 {
                    Divider().overlay(AntigravityTheme.subtleDivider)
                }
            }

            if showMoreModels && !extraModels.isEmpty {
                ForEach(extraModels, id: \.modelId) { extra in
                    Divider().overlay(AntigravityTheme.subtleDivider)
                    modelRowView(extra)
                }
            }

            Divider().overlay(AntigravityTheme.subtleDivider)

            // More models expandable footer row
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showMoreModels.toggle()
                }
            } label: {
                HStack {
                    Text(showMoreModels ? "Fewer models" : "More models")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Spacer()
                    Image(systemName: showMoreModels ? "chevron.up" : "chevron.right")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-more-models")
        }
        .background(AntigravityTheme.surfaceSheetGroup)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func modelRowView(_ model: CascadeModelConfig) -> some View {
        let isSelected = (store.selectedModelConfig.modelId == model.modelId)
        let cleanName = model.displayName.replacingOccurrences(of: " (Thinking)", with: "")
        let supportsEfforts = !model.supportedEfforts.isEmpty

        VStack(alignment: .leading, spacing: 12) {
            Button {
                selectModelOption(model)
            } label: {
                HStack(spacing: 8) {
                    Text(cleanName)
                        .font(.system(size: 16.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)

                    if model.isNewBadge && model.modelId == "MODEL_GOOGLE_GEMINI_4_NEON" {
                        Text("New")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(AntigravityTheme.accentPeriwinkle.opacity(0.16))
                            )
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(Self.accessibilityId(for: model))

            // Inline 4-segment Thinking Effort selector when selected model supports thinking tiers (`ios-model.png`)
            if isSelected && supportsEfforts {
                HStack(spacing: 4) {
                    ForEach(model.supportedEfforts, id: \.self) { effort in
                        let isEffortSelected = (store.selectedModelConfig.effort == effort)
                        Button {
                            store.selectedModelConfig.effort = effort
                        } label: {
                            Text(effortDisplayLabel(effort))
                                .font(.system(size: 13.5, weight: isEffortSelected ? .semibold : .regular))
                                .foregroundStyle(isEffortSelected ? AntigravityTheme.inkReading : AntigravityTheme.inkSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(
                                    Group {
                                        if isEffortSelected {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(AntigravityTheme.surfaceActiveTabSlot)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                                                )
                                        }
                                    }
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("effort-chip-\(effort.rawValue.lowercased())")
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(AntigravityTheme.surfaceObsidian)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isSelected && supportsEfforts ? 14 : 13)
        .background(isSelected ? AntigravityTheme.surfaceSelectionTint : Color.clear)
    }

    private func effortDisplayLabel(_ level: ThinkingEffortLevel) -> String {
        switch level {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .extra: return "Extra High"
        }
    }

    // MARK: - Dual Quota Progress Bars (`Five Hour Limit Remaining` / `Weekly Limit Remaining`)

    private var quotaLimitsFooter: some View {
        let fiveHourPct = max(0, min(100, store.usageQuota.geminiFiveHourPercent))
        let weeklyPct = max(0, min(100, store.usageQuota.geminiWeeklyPercent))

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Five Hour Limit Remaining")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Spacer()
                    Button {
                        showUsageExpanded.toggle()
                    } label: {
                        Text("View Usage")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-view-usage")
                }

                quotaProgressBar(fraction: Double(fiveHourPct) / 100.0)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Weekly Limit Remaining")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Spacer()
                    if showUsageExpanded {
                        Text("\(weeklyPct)% · resets Mon")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                    }
                }

                quotaProgressBar(fraction: Double(weeklyPct) / 100.0)
            }

            if showUsageExpanded {
                HStack {
                    Text("Plan: \(store.usageQuota.planDisplayName)")
                    Spacer()
                    Text("5h: \(fiveHourPct)% · Partner: \(store.usageQuota.partnerFiveHourPercent)%")
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AntigravityTheme.inkMuted)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("model-usage-quota-card")
    }

    private func quotaProgressBar(fraction: Double) -> some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width * min(1, max(0, fraction)))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AntigravityTheme.surfaceElevated)
                Capsule()
                    .fill(AntigravityTheme.accentPeriwinkle)
                    .frame(width: width)
            }
        }
        .frame(height: 5)
    }

    // MARK: - Actions

    private func selectModelOption(_ option: CascadeModelConfig) {
        let isSameModel = (store.selectedModelConfig.modelId == option.modelId)
        let resolvedEffort: ThinkingEffortLevel = {
            if isSameModel, option.supportedEfforts.contains(store.selectedModelConfig.effort) {
                return store.selectedModelConfig.effort
            }
            return option.effort
        }()
        store.selectedModelConfig = CascadeModelConfig(
            modelId: option.modelId,
            displayName: option.displayName,
            subtitle: option.subtitle,
            hasThinkingBadge: option.hasThinkingBadge,
            requiresUpgradeNote: option.requiresUpgradeNote,
            mode: store.selectedModelConfig.mode,
            agentPersona: store.selectedModelConfig.agentPersona,
            effort: resolvedEffort,
            isModelAlias: option.isModelAlias,
            badgeTitle: option.badgeTitle,
            isOrchestrator: option.isOrchestrator,
            plannerModelName: option.plannerModelName,
            executorModelName: option.executorModelName,
            supportedEfforts: option.supportedEfforts,
            isNewBadge: option.isNewBadge
        )
        onSelectConfiguration?(
            store.selectedModelConfig.mode.rawValue,
            option.displayName,
            store.selectedModelConfig.agentPersona
        )
    }

    private func applyAndDismiss() {
        onSelectConfiguration?(
            store.selectedModelConfig.mode.rawValue,
            store.selectedModelConfig.displayName,
            store.selectedModelConfig.agentPersona
        )
        if let onDismiss {
            onDismiss()
        } else {
            store.presentedSheet = nil
            store.currentRoute = .chatAndComposer
        }
    }

    private static func accessibilityId(for option: CascadeModelConfig) -> String {
        let lower = option.displayName.lowercased()
        if lower.contains("neon") { return "model-row-gemini-4-neon" }
        if lower.contains("opus") { return "model-row-claude-opus" }
        if lower.contains("flash") { return "model-row-gemini-flash" }
        return "model-row-\(option.modelId)"
    }
}
