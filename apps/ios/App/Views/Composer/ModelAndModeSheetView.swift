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

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var catalogModels: [CascadeModelConfig] {
        store.availableModels.isEmpty ? CascadeModelConfig.liveDefaultCatalog : store.availableModels
    }

    private var orchestratorModels: [CascadeModelConfig] {
        catalogModels.filter(\.isOrchestrator)
    }

    private var activeOrchestrator: CascadeModelConfig? {
        orchestratorModels.first(where: { $0.containsModelId(store.selectedModelConfig.modelId) })
            ?? orchestratorModels.first
    }

    private var partitionedModels: (primary: [CascadeModelConfig], extra: [CascadeModelConfig]) {
        CascadeModelConfig.partitionPrimaryAndExtraModels(catalogModels)
    }

    private var primaryModels: [CascadeModelConfig] {
        partitionedModels.primary
    }

    private var extraModels: [CascadeModelConfig] {
        partitionedModels.extra
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
        .onAppear {
            revealExtraModelsIfSelected()
        }
        .task {
            if store.hasPairedBackend || store.isLiveBackendConnected {
                await store.refreshModelCatalog()
                revealExtraModelsIfSelected()
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
                Text(lang.t("Model", "模型"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkReading)

                HStack {
                    Spacer()
                    Button {
                        applyAndDismiss()
                    } label: {
                        Text(lang.t("Done", "完成"))
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
        let isOrchSelected = store.selectedModelConfig.isOrchestrator
        let primaries = primaryModels
        let extras = extraModels

        return VStack(spacing: 0) {
            // Row 0: Orchestrator (with inline planner selector when selected and multiple presets exist)
            if let orch = activeOrchestrator {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectModelOption(orch)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lang.t("Orchestrator", "编排器"))
                                    .font(.system(size: 16.5, weight: isOrchSelected ? .semibold : .medium))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                Text(orch.orchestratorSubtitle)
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("model-row-orchestrator")

                    if isOrchSelected && orchestratorModels.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(orchestratorModels, id: \.modelId) { preset in
                                let isPresetSelected = preset.containsModelId(store.selectedModelConfig.modelId)
                                Button {
                                    selectModelOption(preset)
                                } label: {
                                    Text(preset.shortOrchestratorRoleLabel)
                                        .font(.system(size: 13.5, weight: isPresetSelected ? .semibold : .regular))
                                        .foregroundStyle(isPresetSelected ? AntigravityTheme.inkReading : AntigravityTheme.inkSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                        .frame(maxWidth: .infinity, minHeight: 34)
                                        .background(
                                            Group {
                                                if isPresetSelected {
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
                                .accessibilityIdentifier("orchestrator-chip-\(preset.shortOrchestratorRoleLabel.lowercased())")
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
                .padding(.vertical, isOrchSelected && orchestratorModels.count > 1 ? 14 : 13)
                .background(isOrchSelected ? AntigravityTheme.surfaceSelectionTint : Color.clear)

                if !primaries.isEmpty {
                    Divider().overlay(AntigravityTheme.subtleDivider)
                }
            }

            // Primary Models (one clean row per model family; effort selector expands only for the selected model)
            ForEach(Array(primaries.enumerated()), id: \.element.modelId) { idx, model in
                modelRowView(model)
                if idx < primaries.count - 1 {
                    Divider().overlay(AntigravityTheme.subtleDivider)
                }
            }

            if showMoreModels && !extras.isEmpty {
                ForEach(extras, id: \.modelId) { extra in
                    Divider().overlay(AntigravityTheme.subtleDivider)
                    modelRowView(extra)
                }
            }

            if !extras.isEmpty {
                Divider().overlay(AntigravityTheme.subtleDivider)

                // More models expandable footer row
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showMoreModels.toggle()
                    }
                } label: {
                    HStack {
                        Text(showMoreModels ? lang.t("Fewer models", "收起更多模型") : lang.t("More models", "更多模型"))
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
        let isSelected = model.containsModelId(store.selectedModelConfig.modelId)
        let cleanName = model.canonicalDisplayName
        let supportsEfforts = model.supportsEffortAdjustment
        let isFlagshipNeon = model.modelId == "MODEL_GOOGLE_GEMINI_4_NEON"
            || cleanName.lowercased().contains("gemini 4 neon")
        let nonNewStatusTag: String? = {
            guard let tag = model.badgeTitle,
                  !tag.isEmpty,
                  tag.caseInsensitiveCompare("New") != .orderedSame else {
                return nil
            }
            return tag
        }()

        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    selectModelOption(model)
                }
            } label: {
                HStack(spacing: 8) {
                    Text(cleanName)
                        .font(.system(size: 16.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)

                    if model.isNewBadge && isFlagshipNeon {
                        Text(lang.t("New", "新"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(AntigravityTheme.accentPeriwinkle.opacity(0.16))
                            )
                    } else if let statusTag = nonNewStatusTag {
                        Text(statusTag)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(AntigravityTheme.surfaceElevated)
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

            // Step 2: Inline Thinking Effort selector showing ONLY the selected model's supported tiers
            if isSelected && supportsEfforts {
                HStack(spacing: 4) {
                    ForEach(model.supportedEfforts, id: \.self) { effort in
                        let isEffortSelected = (store.selectedModelConfig.effort == effort)
                        Button {
                            selectEffortOption(effort)
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
        case .low: return lang.t("Low", "低")
        case .medium: return lang.t("Medium", "中")
        case .high: return lang.t("High", "高")
        case .extra: return lang.t("Extra High", "极高")
        }
    }

    // MARK: - Dual Quota Progress Bars (`Five Hour Limit Remaining` / `Weekly Limit Remaining`)

    private var quotaLimitsFooter: some View {
        let fiveHourPct = max(0, min(100, store.usageQuota.geminiFiveHourPercent))
        let weeklyPct = max(0, min(100, store.usageQuota.geminiWeeklyPercent))

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(lang.t("Five Hour Limit Remaining", "5 小时剩余额度"))
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Spacer()
                    Button {
                        showUsageExpanded.toggle()
                    } label: {
                        Text(lang.t("View Usage", "查看用量"))
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
                    Text(lang.t("Weekly Limit Remaining", "每周剩余额度"))
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Spacer()
                    if showUsageExpanded {
                        Text(lang.t("\(weeklyPct)% · resets Mon", "\(weeklyPct)% · 周一重置"))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                    }
                }

                quotaProgressBar(fraction: Double(weeklyPct) / 100.0)
            }

            if showUsageExpanded {
                HStack {
                    Text(lang.t("Plan: \(store.usageQuota.planDisplayName)", "套餐：\(store.usageQuota.planDisplayName)"))
                    Spacer()
                    Text(lang.t("5h: \(fiveHourPct)% · Partner: \(store.usageQuota.partnerFiveHourPercent)%", "5 小时：\(fiveHourPct)% · 合作方：\(store.usageQuota.partnerFiveHourPercent)%"))
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

    private func revealExtraModelsIfSelected() {
        if extraModels.contains(where: { $0.containsModelId(store.selectedModelConfig.modelId) }) {
            showMoreModels = true
        }
    }

    private func selectModelOption(_ option: CascadeModelConfig) {
        store.selectModel(option)
        onSelectConfiguration?(
            store.selectedModelConfig.mode.rawValue,
            store.selectedModelConfig.displayName,
            store.selectedModelConfig.agentPersona
        )
    }

    private func selectEffortOption(_ effort: ThinkingEffortLevel) {
        store.selectThinkingEffort(effort)
        onSelectConfiguration?(
            store.selectedModelConfig.mode.rawValue,
            store.selectedModelConfig.displayName,
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
        let lower = option.canonicalDisplayName.lowercased()
        if lower.contains("gemini 4 neon") { return "model-row-gemini-4-neon" }
        if lower.contains("gemini 4 carbon") { return "model-row-gemini-4-carbon" }
        if lower.contains("opus") { return "model-row-claude-opus" }
        if lower.contains("3.8 flash") { return "model-row-gemini-flash" }
        return "model-row-\(option.modelId)"
    }
}
