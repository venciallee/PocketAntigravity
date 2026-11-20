import SwiftUI
import AntigravityData

/// State `UE09_MODEL_AND_MODE`: Official Model, Mode & Custom Agent Picker sheet (`iOS · 模型 / Agent 模式选择`).
/// Features:
/// - `Model & Mode` header + Periwinkle `Done` button (`btn-model-done`)
/// - Compact equal-height side-by-side `Planning` (`mode-card-planning` with `#8EB4FF` border) and `Fast` (`mode-card-fast`) mode cards
/// - `MODEL` grouped card with clean badge pills (`New`, `Thinking`), descriptive subtitles, and inline effort tier controls (`Low` / `Medium` / `High` / `XHigh`) for multi-tier model families
/// - Note: `A new model takes effect on the next turn.`
/// - `AGENT` flowing persona pills (`Default` pure white active pill, custom agents).
public struct ModelAndModeSheetView: View {
    @Bindable public var store: AntigravitySessionStore
    public var isPresentedAsNativeSheet: Bool
    public var onSelectConfiguration: ((String, String, String) -> Void)?
    public var onDismiss: (() -> Void)?

    public static let sheetSurfaceColor = Color(red: 0x16 / 255.0, green: 0x17 / 255.0, blue: 0x1C / 255.0)
    private static let periwinkle = Color(red: 0x8E / 255.0, green: 0xB4 / 255.0, blue: 0xFF / 255.0) // #8EB4FF
    private static let cardSurface = Color(red: 0x1F / 255.0, green: 0x21 / 255.0, blue: 0x29 / 255.0)
    private static let activeModeSurface = Color(red: 0x1C / 255.0, green: 0x23 / 255.0, blue: 0x33 / 255.0)
    private static let effortTrackSurface = Color(red: 0x14 / 255.0, green: 0x16 / 255.0, blue: 0x1C / 255.0)
    private static let hairlineBorder = Color.white.opacity(0.07)

    private struct ModelVariantEntry: Identifiable {
        let id: String
        let tierLabel: String
        let sortRank: Int
        let config: CascadeModelConfig
        let originalIndex: Int
    }

    private struct ModelDisplayGroup: Identifiable {
        let id: String
        let baseName: String
        let variants: [ModelVariantEntry]
        let firstOriginalIndex: Int

        var isMultiTier: Bool { variants.count >= 2 }

        var defaultVariant: ModelVariantEntry {
            variants.first(where: { $0.sortRank == 3 })
                ?? variants.min(by: { $0.originalIndex < $1.originalIndex })
                ?? variants[0]
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

    private var displayedModels: [CascadeModelConfig] {
        store.availableModels.isEmpty ? CascadeModelConfig.liveDefaultCatalog : store.availableModels
    }

    private var displayedModelGroups: [ModelDisplayGroup] {
        Self.buildModelGroups(from: displayedModels)
    }

    private var displayedAgents: [String] {
        store.availableAgents.isEmpty ? ["Default"] : store.availableAgents
    }

    public var body: some View {
        Group {
            if isPresentedAsNativeSheet {
                nativeSheetContent
            } else {
                standaloneBackdropContent
            }
        }
        .sensoryFeedback(.selection, trigger: store.selectedModelConfig)
        .task {
            if store.hasPairedBackend || store.isLiveBackendConnected {
                await store.refreshModelCatalog()
            }
        }
    }

    // MARK: - Presentation Containers

    private var nativeSheetContent: some View {
        VStack(spacing: 0) {
            sheetHeaderBar
                .padding(.top, 16)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                sheetSectionsBody
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Self.sheetSurfaceColor.ignoresSafeArea())
    }

    private var standaloneBackdropContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Top Grabber (only rendered in standalone ESDD showcase mode)
                HStack {
                    Spacer()
                    Capsule()
                        .fill(Color.white.opacity(0.26))
                        .frame(width: 38, height: 5)
                    Spacer()
                }
                .padding(.top, 10)
                .padding(.bottom, 4)

                sheetHeaderBar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)

                ScrollView(.vertical, showsIndicators: false) {
                    sheetSectionsBody
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                        .padding(.bottom, 28)
                }
            }
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
                .strokeBorder(Self.hairlineBorder, lineWidth: 1)
            )
            .padding(.top, 118)
            .ignoresSafeArea(edges: .bottom)
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
    }

    // MARK: - Header & Main Sections

    private var sheetHeaderBar: some View {
        ZStack {
            Text("Model & Mode")
                .font(.system(size: 17.5, weight: .bold))
                .foregroundStyle(AntigravityTheme.inkReading)

            HStack {
                Spacer()
                Button {
                    applyAndDismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Self.periwinkle)
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
    }

    private var sheetSectionsBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Planning vs Fast Mode Cards (compact equal height, never vertically stretched)
            HStack(alignment: .top, spacing: 10) {
                modeCardButton(
                    mode: .planning,
                    iconName: "doc.text",
                    description: "Plans first and writes artifacts for you to review",
                    testId: "mode-card-planning"
                )

                modeCardButton(
                    mode: .fast,
                    iconName: "bolt",
                    description: "Acts directly — best for small, local edits",
                    testId: "mode-card-fast"
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            // MODEL Picker Section
            VStack(alignment: .leading, spacing: 8) {
                Text("MODEL")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .padding(.leading, 2)

                modelRowsCard

                Text("A new model takes effect on the next turn.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .padding(.leading, 2)
                    .padding(.top, 2)
            }

            // AGENT Persona Section
            VStack(alignment: .leading, spacing: 8) {
                Text("AGENT")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .padding(.leading, 2)

                FlowPillLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                    ForEach(displayedAgents, id: \.self) { agentName in
                        agentPersonaPill(
                            name: agentName,
                            isMonospaced: agentName != "Default",
                            testId: "agent-pill-\(agentName.lowercased())"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Mode Cards

    private func modeCardButton(
        mode: CascadeExecutionMode,
        iconName: String,
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
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? Self.periwinkle : AntigravityTheme.inkSecondary)

                    Text(mode.rawValue)
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Self.periwinkle)
                    }
                }

                Text(description)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(isSelected ? AntigravityTheme.inkLabel.opacity(0.84) : AntigravityTheme.inkSecondary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Self.activeModeSurface : Self.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Self.periwinkle : Self.hairlineBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(testId)
    }

    // MARK: - Model Grouped Card

    private var modelRowsCard: some View {
        let groups = displayedModelGroups
        return VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                modelGroupRow(group)
                if idx < groups.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                        .padding(.leading, 16)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Self.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Self.hairlineBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func modelGroupRow(_ group: ModelDisplayGroup) -> some View {
        let matchedVariant = group.variants.first(where: { isOptionSelected($0.config) })
        let isGroupSelected = matchedVariant != nil
        let activeVariant = matchedVariant ?? group.defaultVariant
        let option = activeVariant.config
        let titleText = Self.cleanedRowTitle(for: group, activeOption: option)
        let badgeLabel = Self.resolvedBadgeTitle(for: option)
        let subtitleText = Self.resolvedSubtitle(for: option)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    selectModel(activeVariant.config)
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(titleText)
                                .font(.system(size: 15.5, weight: isGroupSelected ? .semibold : .medium))
                                .foregroundStyle(AntigravityTheme.inkReading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.86)

                            if let badgeLabel {
                                Text(badgeLabel)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Self.periwinkle)
                                    .padding(.horizontal, 6.5)
                                    .padding(.vertical, 2)
                                    .background(Self.periwinkle.opacity(0.15))
                                    .clipShape(Capsule())
                                    .fixedSize()
                            }

                            if option.hasThinkingBadge {
                                Text("Thinking")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.inkLabel)
                                    .padding(.horizontal, 6.5)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.09))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .fixedSize()
                            }
                        }

                        Text(subtitleText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    if isGroupSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Self.periwinkle)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, group.isMultiTier ? 10 : 12)
                .frame(minHeight: 58)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
                group.isMultiTier
                    ? Self.groupAccessibilityId(for: group)
                    : Self.accessibilityId(for: option, index: activeVariant.originalIndex)
            )

            if group.isMultiTier {
                effortTierSelector(for: group, isGroupSelected: isGroupSelected)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .background(isGroupSelected ? Self.periwinkle.opacity(0.065) : Color.clear)
    }

    private func effortTierSelector(for group: ModelDisplayGroup, isGroupSelected: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(group.variants) { variant in
                let isTierSelected = isGroupSelected && isOptionSelected(variant.config)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectModel(variant.config)
                    }
                } label: {
                    Text(variant.tierLabel)
                        .font(.system(size: 12, weight: isTierSelected ? .semibold : .medium))
                        .foregroundStyle(
                            isTierSelected
                                ? Self.periwinkle
                                : (isGroupSelected ? AntigravityTheme.inkLabel.opacity(0.82) : AntigravityTheme.inkSecondary)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isTierSelected ? Self.periwinkle.opacity(0.16) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    isTierSelected ? Self.periwinkle.opacity(0.50) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(Self.accessibilityId(for: variant.config, index: variant.originalIndex))
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Self.effortTrackSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Agent Persona Pills

    private func agentPersonaPill(
        name: String,
        isMonospaced: Bool,
        testId: String
    ) -> some View {
        let isSelected = store.selectedModelConfig.agentPersona == name
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
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
                        ? .system(size: 13.5, weight: isSelected ? .bold : .medium, design: .monospaced)
                        : .system(size: 14, weight: .semibold)
                )
                .foregroundStyle(isSelected ? AntigravityTheme.inkOnPrimaryCTA : AntigravityTheme.inkReading)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(isSelected ? Color.white : Self.cardSurface)
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : Self.hairlineBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(testId)
    }

    // MARK: - Selection & Model Grouping Helpers

    private func isOptionSelected(_ option: CascadeModelConfig) -> Bool {
        store.selectedModelConfig.modelId == option.modelId
            || store.selectedModelConfig.displayName == option.displayName
    }

    private func selectModel(_ option: CascadeModelConfig) {
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

    private static func extractEffortSuffix(from displayName: String) -> (baseName: String, tierLabel: String, sortRank: Int)? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"),
              let openRange = trimmed.range(of: " (", options: .backwards) else {
            return nil
        }
        let baseName = String(trimmed[..<openRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseName.isEmpty else { return nil }
        let suffixStart = openRange.upperBound
        let suffixEnd = trimmed.index(before: trimmed.endIndex)
        guard suffixStart < suffixEnd else { return nil }
        let rawTier = String(trimmed[suffixStart..<suffixEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        switch rawTier.lowercased() {
        case "minimal":
            return (baseName, "Minimal", 0)
        case "low":
            return (baseName, "Low", 1)
        case "medium", "med":
            return (baseName, "Medium", 2)
        case "high":
            return (baseName, "High", 3)
        case "xhigh", "x-high", "extra high":
            return (baseName, "XHigh", 4)
        case "max":
            return (baseName, "Max", 5)
        default:
            return nil
        }
    }

    private static func buildModelGroups(from models: [CascadeModelConfig]) -> [ModelDisplayGroup] {
        var bucketByKey: [String: (baseName: String, variants: [ModelVariantEntry])] = [:]
        for (idx, model) in models.enumerated() {
            guard let parsed = extractEffortSuffix(from: model.displayName) else { continue }
            let key = parsed.baseName.lowercased()
            let entry = ModelVariantEntry(
                id: model.modelId,
                tierLabel: parsed.tierLabel,
                sortRank: parsed.sortRank,
                config: model,
                originalIndex: idx
            )
            if var existing = bucketByKey[key] {
                existing.variants.append(entry)
                bucketByKey[key] = existing
            } else {
                bucketByKey[key] = (baseName: parsed.baseName, variants: [entry])
            }
        }

        let groupableKeys = Set(
            bucketByKey.compactMap { key, bucket -> String? in
                guard bucket.variants.count >= 2 else { return nil }
                let distinctTiers = Set(bucket.variants.map(\.tierLabel))
                return distinctTiers.count == bucket.variants.count ? key : nil
            }
        )

        var emittedGroupKeys = Set<String>()
        var result: [ModelDisplayGroup] = []

        for (idx, model) in models.enumerated() {
            if let parsed = extractEffortSuffix(from: model.displayName) {
                let key = parsed.baseName.lowercased()
                if groupableKeys.contains(key) {
                    if emittedGroupKeys.contains(key) { continue }
                    emittedGroupKeys.insert(key)
                    if let bucket = bucketByKey[key] {
                        let sortedVariants = bucket.variants.sorted { lhs, rhs in
                            if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
                            return lhs.originalIndex < rhs.originalIndex
                        }
                        result.append(
                            ModelDisplayGroup(
                                id: "group-\(key)",
                                baseName: bucket.baseName,
                                variants: sortedVariants,
                                firstOriginalIndex: idx
                            )
                        )
                    }
                    continue
                }
            }

            result.append(
                ModelDisplayGroup(
                    id: model.modelId,
                    baseName: model.displayName,
                    variants: [
                        ModelVariantEntry(
                            id: model.modelId,
                            tierLabel: "",
                            sortRank: 0,
                            config: model,
                            originalIndex: idx
                        )
                    ],
                    firstOriginalIndex: idx
                )
            )
        }

        return result
    }

    private static func cleanedRowTitle(for group: ModelDisplayGroup, activeOption: CascadeModelConfig) -> String {
        let raw = (group.isMultiTier ? group.baseName : activeOption.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeOption.hasThinkingBadge else { return raw }
        if let range = raw.range(of: " (Thinking)", options: [.caseInsensitive, .anchored, .backwards]) {
            let trimmed = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return raw
    }

    private static func resolvedBadgeTitle(for option: CascadeModelConfig) -> String? {
        if let explicit = option.badgeTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }
        let sub = option.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if CascadeModelConfig.isGenericBadgeLabel(sub) {
            return sub
        }
        return nil
    }

    private static func resolvedSubtitle(for option: CascadeModelConfig) -> String {
        let sub = option.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if sub.isEmpty || CascadeModelConfig.isGenericBadgeLabel(sub) {
            return CascadeModelConfig.descriptiveSubtitle(forModelLabel: option.displayName)
        }
        return sub
    }

    private static func groupAccessibilityId(for group: ModelDisplayGroup) -> String {
        let slug = group.baseName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "model-group-\(slug)"
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
}

/// Compact flow layout that wraps agent persona pills naturally across rows without clipping.
private struct FlowPillLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                currentY += rowHeight + verticalSpacing
                currentX = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            currentX += size.width
            maxRowWidth = max(maxRowWidth, currentX)
            currentX += horizontalSpacing
        }

        let resolvedWidth = proposal.width ?? maxRowWidth
        return CGSize(width: resolvedWidth, height: currentY + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentY += rowHeight + verticalSpacing
                currentX = bounds.minX
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + horizontalSpacing
        }
    }
}
