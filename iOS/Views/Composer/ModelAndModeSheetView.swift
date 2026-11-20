import SwiftUI
import AntigravityData

/// State `UE09_MODEL_AND_MODE`: Official Model, Permissions & Custom Agent Picker sheet.
/// - In live Antigravity 2.x mode (aligned with PC 2.x where Planning/Fast moved to `/plan`):
///   displays grouped `MODEL` families with inline effort-tier segmented controls (`Low` / `Medium` / `High` / `XHigh`),
///   `REMOTE PERMISSIONS` / `PERMISSIONS` (`Request Review`, `Default`, `Auto`, `Turbo`), and optional `AGENT` pills.
/// - In ESDD verification mode (`UE09_MODEL_AND_MODE`), preserves compact equal-height `Planning` & `Fast` mode cards
///   alongside `MODEL` and `AGENT` pills for full spec parity.
public struct ModelAndModeSheetView: View {
    @Bindable public var store: AntigravitySessionStore
    public var isPresentedAsNativeSheet: Bool
    public var onSelectConfiguration: ((String, String, String) -> Void)?
    public var onDismiss: (() -> Void)?

    public static let sheetSurfaceColor = Color(red: 0x13 / 255.0, green: 0x14 / 255.0, blue: 0x1A / 255.0)
    private static let periwinkle = AntigravityTheme.accentPeriwinkle // #8EB4FF
    private static let emerald = AntigravityTheme.statusDone // #57C88A
    private static let cardSurface = Color(red: 0x1B / 255.0, green: 0x1D / 255.0, blue: 0x24 / 255.0)
    private static let modeSelectedTop = Color(red: 0x21 / 255.0, green: 0x2A / 255.0, blue: 0x3E / 255.0)
    private static let modeSelectedBottom = Color(red: 0x18 / 255.0, green: 0x1E / 255.0, blue: 0x2C / 255.0)
    private static let modeDescriptionSelected = Color(red: 0xB0 / 255.0, green: 0xB8 / 255.0, blue: 0xC8 / 255.0)
    private static let segmentTrackSurface = Color(red: 0x11 / 255.0, green: 0x12 / 255.0, blue: 0x17 / 255.0)
    private static let segmentActiveSurface = Color(red: 0x25 / 255.0, green: 0x30 / 255.0, blue: 0x47 / 255.0)

    private struct ModelEffortVariant: Identifiable {
        let option: CascadeModelConfig
        let effortLabel: String
        let effortRank: Int

        var id: String { option.modelId }
    }

    private struct ModelFamilyGroup: Identifiable {
        let id: String
        let familyName: String
        let variants: [ModelEffortVariant]
        let singleOption: CascadeModelConfig?
        let singleEffortBadge: String?
        let preferredOption: CascadeModelConfig
        let firstIndex: Int

        var isGroupedFamily: Bool {
            variants.count >= 2
        }

        func selectedVariant(for selected: CascadeModelConfig) -> CascadeModelConfig? {
            if let single = singleOption {
                return Self.matches(single, selected: selected) ? single : nil
            }
            return variants.first(where: { Self.matches($0.option, selected: selected) })?.option
        }

        static func matches(_ option: CascadeModelConfig, selected: CascadeModelConfig) -> Bool {
            option.modelId == selected.modelId || option.displayName == selected.displayName
        }
    }

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

    private var isLiveAntigravity2Mode: Bool {
        !store.isVerificationMode || store.hasPairedBackend || store.isLiveBackendConnected
    }

    private var sheetTitle: String {
        isLiveAntigravity2Mode ? "Model & Permissions" : "Model & Mode"
    }

    private var displayedModels: [CascadeModelConfig] {
        store.availableModels.isEmpty ? CascadeModelConfig.liveDefaultCatalog : store.availableModels
    }

    private var modelGroups: [ModelFamilyGroup] {
        Self.buildModelGroups(from: displayedModels)
    }

    private var displayedAgents: [String] {
        store.availableAgents.isEmpty ? ["Default"] : store.availableAgents
    }

    private var shouldShowAgentSection: Bool {
        displayedAgents.count > 1 || (!isLiveAntigravity2Mode && store.isVerificationMode)
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
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .padding(.top, 118)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: store.selectedModelConfig.mode)
        .sensoryFeedback(.selection, trigger: store.selectedModelConfig.modelId)
        .sensoryFeedback(.selection, trigger: store.activePermissionPreset)
        .task {
            if store.hasPairedBackend || store.isLiveBackendConnected {
                await store.refreshModelCatalog()
            }
        }
    }

    // MARK: - Sheet Content

    private var sheetInnerContent: some View {
        VStack(spacing: 0) {
            if !isPresentedAsNativeSheet {
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 36, height: 4.5)
                    .padding(.top, 10)
            }

            headerBar
                .padding(.horizontal, 16)
                .padding(.top, isPresentedAsNativeSheet ? 14 : 6)
                .padding(.bottom, 8)

            Divider()
                .overlay(Color.white.opacity(0.06))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if !isLiveAntigravity2Mode {
                        modeSection
                    }

                    modelSection

                    if isLiveAntigravity2Mode {
                        permissionsSection
                    }

                    if shouldShowAgentSection {
                        agentSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var headerBar: some View {
        ZStack {
            Text(sheetTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkReading)

            HStack {
                Spacer()
                Button {
                    applyAndDismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Self.periwinkle)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Self.periwinkle.opacity(0.14))
                        .overlay(
                            Capsule()
                                .strokeBorder(Self.periwinkle.opacity(0.28), lineWidth: 1)
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
                .accessibilityIdentifier("btn-model-done")
            }
        }
        .frame(height: 44)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(AntigravityTheme.inkSecondary)
            .padding(.leading, 4)
    }

    // MARK: - MODE Section (ESDD UE09 Verification Parity)

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("MODE")

            HStack(spacing: 10) {
                modeCardButton(
                    mode: .planning,
                    iconName: "doc.text",
                    activeIconName: "doc.text.fill",
                    description: "Plans first and writes artifacts for you to review",
                    testId: "mode-card-planning"
                )

                modeCardButton(
                    mode: .fast,
                    iconName: "bolt",
                    activeIconName: "bolt.fill",
                    description: "Acts directly — best for small, local edits",
                    testId: "mode-card-fast"
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modeCardButton(
        mode: CascadeExecutionMode,
        iconName: String,
        activeIconName: String,
        description: String,
        testId: String
    ) -> some View {
        let isSelected = store.selectedModelConfig.mode == mode
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                store.selectedModelConfig.mode = mode
            }
            onSelectConfiguration?(
                mode.rawValue,
                store.selectedModelConfig.displayName,
                store.selectedModelConfig.agentPersona
            )
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Self.periwinkle.opacity(0.18) : Color.white.opacity(0.06))
                            .frame(width: 28, height: 28)
                        Image(systemName: isSelected ? activeIconName : iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? Self.periwinkle : AntigravityTheme.inkSecondary)
                    }

                    Text(mode.rawValue)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(isSelected ? AntigravityTheme.inkReading : AntigravityTheme.inkLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)

                    Spacer(minLength: 2)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Self.periwinkle)
                    } else {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1.25)
                            .frame(width: 16, height: 16)
                    }
                }

                Text(description)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(isSelected ? Self.modeDescriptionSelected : AntigravityTheme.inkSecondary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Self.modeSelectedTop, Self.modeSelectedBottom],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Self.cardSurface)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Self.periwinkle.opacity(0.85) : Color.white.opacity(0.07),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
            .shadow(color: isSelected ? Self.periwinkle.opacity(0.12) : .clear, radius: 10, x: 0, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(testId)
    }

    // MARK: - MODEL Section

    private var modelSection: some View {
        let groups = modelGroups
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("MODEL")

            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                    modelGroupRow(group)
                    if idx < groups.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.06))
                            .padding(.leading, 14)
                    }
                }
            }
            .background(Self.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )

            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11.5, weight: .medium))
                Text("A new model takes effect on the next turn.")
                    .font(.system(size: 12))
            }
            .foregroundStyle(AntigravityTheme.inkMuted)
            .padding(.leading, 4)
            .padding(.top, 2)
        }
    }

    // MARK: - PERMISSIONS Section (Antigravity 2.x Local & Remote Permissions)

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(store.isActiveSessionCloud ? "REMOTE PERMISSIONS" : "PERMISSIONS")
            PermissionsPresetListCard(store: store)
        }
    }

    @ViewBuilder
    private func modelGroupRow(_ group: ModelFamilyGroup) -> some View {
        let selectedOption = group.selectedVariant(for: store.selectedModelConfig)
        let isSelected = selectedOption != nil
        let activeOption = selectedOption ?? group.preferredOption
        let tagBadge = Self.effectiveBadgeTitle(for: activeOption)
            ?? group.variants.compactMap { Self.effectiveBadgeTitle(for: $0.option) }.first
        let subtitle = Self.effectiveSubtitle(for: activeOption)

        if group.isGroupedFamily {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        selectModelOption(activeOption)
                    }
                } label: {
                    modelRowHeaderContent(
                        title: group.familyName,
                        subtitle: subtitle,
                        tagBadge: tagBadge,
                        effortBadge: nil,
                        hasThinkingBadge: activeOption.hasThinkingBadge,
                        isSelected: isSelected,
                        unselectedTierCount: group.variants.count
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(Self.accessibilityId(for: group.preferredOption, index: group.firstIndex))

                if isSelected {
                    effortTierSegmentedBar(variants: group.variants)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(isSelected ? Self.periwinkle.opacity(0.08) : Color.clear)
        } else {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    selectModelOption(activeOption)
                }
            } label: {
                modelRowHeaderContent(
                    title: group.familyName,
                    subtitle: subtitle,
                    tagBadge: tagBadge,
                    effortBadge: group.singleEffortBadge,
                    hasThinkingBadge: activeOption.hasThinkingBadge,
                    isSelected: isSelected,
                    unselectedTierCount: nil
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .background(isSelected ? Self.periwinkle.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(Self.accessibilityId(for: activeOption, index: group.firstIndex))
        }
    }

    private func modelRowHeaderContent(
        title: String,
        subtitle: String,
        tagBadge: String?,
        effortBadge: String?,
        hasThinkingBadge: Bool,
        isSelected: Bool,
        unselectedTierCount: Int?
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)

                    if let tagBadge {
                        Text(tagBadge)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Self.emerald)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2)
                            .background(Self.emerald.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    if let effortBadge {
                        Text(effortBadge)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkLabel)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }

                    if hasThinkingBadge {
                        Text("Thinking")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkLabel)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.09))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isSelected ? Self.modeDescriptionSelected : AntigravityTheme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Self.periwinkle)
            } else if let tierCount = unselectedTierCount {
                Text("\(tierCount) levels")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }
        }
        .contentShape(Rectangle())
    }

    private func effortTierSegmentedBar(variants: [ModelEffortVariant]) -> some View {
        HStack(spacing: 4) {
            ForEach(variants) { variant in
                let isVariantSelected = ModelFamilyGroup.matches(variant.option, selected: store.selectedModelConfig)
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selectModelOption(variant.option)
                    }
                } label: {
                    Text(variant.effortLabel)
                        .font(.system(size: 12.5, weight: isVariantSelected ? .semibold : .medium))
                        .foregroundStyle(isVariantSelected ? Self.periwinkle : AntigravityTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                                .fill(isVariantSelected ? Self.segmentActiveSurface : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                                .strokeBorder(
                                    isVariantSelected ? Self.periwinkle.opacity(0.45) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("model-effort-\(variant.option.modelId)")
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Self.segmentTrackSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - AGENT Section

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("AGENT")

            VStack(alignment: .leading, spacing: 6) {
                let agentList = displayedAgents
                ForEach(Array(stride(from: 0, to: agentList.count, by: 2)), id: \.self) { rowStart in
                    HStack(spacing: 8) {
                        let firstName = agentList[rowStart]
                        agentPersonaPill(
                            name: firstName,
                            isMonospaced: firstName != "Default",
                            testId: "agent-pill-\(firstName.lowercased())"
                        )
                        if rowStart + 1 < agentList.count {
                            let secondName = agentList[rowStart + 1]
                            agentPersonaPill(
                                name: secondName,
                                isMonospaced: secondName != "Default",
                                testId: "agent-pill-\(secondName.lowercased())"
                            )
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func agentPersonaPill(
        name: String,
        isMonospaced: Bool,
        testId: String
    ) -> some View {
        let isSelected = store.selectedModelConfig.agentPersona == name
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                store.selectedModelConfig.agentPersona = name
            }
            onSelectConfiguration?(
                store.selectedModelConfig.mode.rawValue,
                store.selectedModelConfig.displayName,
                name
            )
        } label: {
            Text(name)
                .font(
                    isMonospaced
                        ? .system(size: 13, weight: isSelected ? .bold : .medium, design: .monospaced)
                        : .system(size: 13.5, weight: .semibold)
                )
                .foregroundStyle(isSelected ? AntigravityTheme.inkOnPrimaryCTA : AntigravityTheme.inkLabel)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(isSelected ? Color.white : Self.cardSurface)
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(Capsule())
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(testId)
    }

    // MARK: - Actions & Model Grouping Helpers

    private func selectModelOption(_ option: CascadeModelConfig) {
        store.selectedModelConfig = CascadeModelConfig(
            modelId: option.modelId,
            displayName: option.displayName,
            subtitle: option.subtitle,
            hasThinkingBadge: option.hasThinkingBadge,
            requiresUpgradeNote: option.requiresUpgradeNote,
            mode: store.selectedModelConfig.mode,
            agentPersona: store.selectedModelConfig.agentPersona,
            effort: option.effort,
            isModelAlias: option.isModelAlias,
            badgeTitle: option.badgeTitle
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
            store.currentRoute = .chatAndComposer
        }
    }

    private static func accessibilityId(for option: CascadeModelConfig, index: Int) -> String {
        let lower = option.displayName.lowercased()
        if option.modelId == "gemini-3-1-pro" || (index == 0 && lower.contains("gemini") && lower.contains("pro")) {
            return "model-row-gemini-pro"
        }
        if lower.contains("flash") {
            return "model-row-gemini-flash"
        }
        if lower.contains("opus") {
            return "model-row-claude-opus"
        }
        if lower.contains("sonnet") {
            return "model-row-claude-sonnet"
        }
        return "model-row-\(option.modelId)"
    }

    private static func parseEffortSuffix(from displayName: String) -> (baseName: String, effortLabel: String, rank: Int)? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"), let openIdx = trimmed.lastIndex(of: "(") else {
            return nil
        }
        let insideStart = trimmed.index(after: openIdx)
        let insideEnd = trimmed.index(before: trimmed.endIndex)
        guard insideStart < insideEnd else { return nil }
        let token = trimmed[insideStart..<insideEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let base = trimmed[..<openIdx].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }

        switch token {
        case "minimal":
            return (base, "Minimal", 0)
        case "low":
            return (base, "Low", 1)
        case "med", "medium":
            return (base, "Medium", 2)
        case "high":
            return (base, "High", 3)
        case "xhigh", "x-high", "extra", "extra high":
            return (base, "XHigh", 4)
        case "max":
            return (base, "Max", 5)
        default:
            return nil
        }
    }

    private static func cleanedSingleTitle(for option: CascadeModelConfig) -> (title: String, effortBadge: String?) {
        let trimmed = option.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = parseEffortSuffix(from: trimmed) {
            return (parsed.baseName, parsed.effortLabel)
        }
        if option.hasThinkingBadge, trimmed.lowercased().hasSuffix(" (thinking)") {
            return (String(trimmed.dropLast(" (thinking)".count)), nil)
        }
        return (trimmed, nil)
    }

    private static func buildModelGroups(from models: [CascadeModelConfig]) -> [ModelFamilyGroup] {
        var familyOrder: [String] = []
        var familyEntries: [String: [(index: Int, option: CascadeModelConfig, effortLabel: String, rank: Int)]] = [:]

        for (idx, option) in models.enumerated() {
            if let parsed = parseEffortSuffix(from: option.displayName) {
                if familyEntries[parsed.baseName] == nil {
                    familyOrder.append(parsed.baseName)
                }
                familyEntries[parsed.baseName, default: []].append(
                    (index: idx, option: option, effortLabel: parsed.effortLabel, rank: parsed.rank)
                )
            }
        }

        var mergeableFamilies: Set<String> = []
        for baseName in familyOrder {
            if let entries = familyEntries[baseName], entries.count >= 2 {
                let uniqueLabels = Set(entries.map(\.effortLabel))
                if uniqueLabels.count == entries.count {
                    mergeableFamilies.insert(baseName)
                }
            }
        }

        var groups: [ModelFamilyGroup] = []
        var emittedFamilies: Set<String> = []

        for (idx, option) in models.enumerated() {
            if let parsed = parseEffortSuffix(from: option.displayName),
               mergeableFamilies.contains(parsed.baseName) {
                guard !emittedFamilies.contains(parsed.baseName),
                      let entries = familyEntries[parsed.baseName] else {
                    continue
                }
                emittedFamilies.insert(parsed.baseName)
                let sortedVariants = entries
                    .sorted { $0.rank < $1.rank }
                    .map { ModelEffortVariant(option: $0.option, effortLabel: $0.effortLabel, effortRank: $0.rank) }
                groups.append(
                    ModelFamilyGroup(
                        id: "family:\(parsed.baseName)",
                        familyName: parsed.baseName,
                        variants: sortedVariants,
                        singleOption: nil,
                        singleEffortBadge: nil,
                        preferredOption: entries[0].option,
                        firstIndex: entries[0].index
                    )
                )
            } else {
                let cleaned = cleanedSingleTitle(for: option)
                groups.append(
                    ModelFamilyGroup(
                        id: "single:\(option.modelId)",
                        familyName: cleaned.title,
                        variants: [],
                        singleOption: option,
                        singleEffortBadge: cleaned.effortBadge,
                        preferredOption: option,
                        firstIndex: idx
                    )
                )
            }
        }

        return groups
    }

    private static func effectiveBadgeTitle(for option: CascadeModelConfig) -> String? {
        if let badge = option.badgeTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !badge.isEmpty {
            return badge
        }
        let rawSub = option.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if CascadeModelConfig.isGenericBadgeLabel(rawSub) {
            return rawSub
        }
        return nil
    }

    private static func effectiveSubtitle(for option: CascadeModelConfig) -> String {
        let raw = option.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchesTag = option.badgeTitle.map { raw.caseInsensitiveCompare($0) == .orderedSame } ?? false
        if raw.isEmpty || matchesTag || CascadeModelConfig.isGenericBadgeLabel(raw) {
            return CascadeModelConfig.descriptiveSubtitle(forModelLabel: option.displayName)
        }
        return raw
    }
}
