import SwiftUI
import AntigravityData

/// State `UE08_ADD_CONTEXT`: Official Add Context modal sheet (`iOS · Add Context`).
/// Features:
/// - `Add Context` header with circular `×` close button
/// - Search input (`Search files, folders, skills...`, `context-search-input`)
/// - 5 category tiles (`Files`, `Folder`, `Mentions`, `Actions`, `Skills`)
/// - Grouped multi-select sections: `FILES & FOLDERS`, `MENTIONS`, `ACTIONS & SKILLS`
/// - Sticky footer with `3 selected` count and Periwinkle `#8EB4FF` `Add to message` CTA (`btn-add-to-message`).
public struct AddContextSheetView: View {
    public enum CategoryTile: String, CaseIterable, Identifiable, Sendable {
        case files = "Files"
        case folder = "Folder"
        case mentions = "Mentions"
        case actions = "Actions"
        case skills = "Skills"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .files: return "doc"
            case .folder: return "folder"
            case .mentions: return "at"
            case .actions: return "bolt"
            case .skills: return "cube"
            }
        }

        public func localizedTitle(for lang: AppLanguage) -> String {
            switch self {
            case .files: return lang.t("Files", "文件")
            case .folder: return lang.t("Folder", "文件夹")
            case .mentions: return lang.t("Mentions", "引用")
            case .actions: return lang.t("Actions", "快捷指令")
            case .skills: return lang.t("Skills", "技能")
            }
        }

        public var testId: String {
            switch self {
            case .files: return "tile-files"
            case .folder: return "tile-folder"
            case .mentions: return "tile-mentions"
            case .actions: return "tile-actions"
            case .skills: return "tile-skills"
            }
        }
    }

    private struct ContextRowSpec: Identifiable {
        let id: String
        let section: String
        let category: CategoryTile
        let iconName: String
        let title: String
        let subtitle: String
        let isMonospacedTitle: Bool
        let usesPlusAffordance: Bool
        let testId: String
    }

    @Bindable public var store: AntigravitySessionStore
    public var onAddLabels: (([String]) -> Void)?
    public var onPickPhotos: (() -> Void)?
    public var onPickDeviceFile: (() -> Void)?
    public var onDismiss: (() -> Void)?

    @State private var searchQuery: String = ""
    @State private var activeCategoryFilter: CategoryTile? = nil
    @State private var selectedItemIds: Set<String>
    @State private var isExpandedToPicker: Bool

    public var showHomeBackdrop: Bool
    public var isPresentedAsNativeSheet: Bool

    private var lang: AppLanguage { store.appearancePreferences.language }

    private func localizedSectionTitle(_ section: String) -> String {
        switch section {
        case "FILES & FOLDERS": return lang.t("FILES & FOLDERS", "文件与文件夹")
        case "MENTIONS": return lang.t("MENTIONS", "引用")
        case "ACTIONS & SKILLS": return lang.t("ACTIONS & SKILLS", "指令与技能")
        default: return section
        }
    }

    private let verificationRows: [ContextRowSpec] = [
        ContextRowSpec(
            id: "ratelimit.go",
            section: "FILES & FOLDERS",
            category: .files,
            iconName: "doc",
            title: "ratelimit.go",
            subtitle: "internal/middleware · changed this turn",
            isMonospacedTitle: true,
            usesPlusAffordance: false,
            testId: "ctx-row-ratelimit"
        ),
        ContextRowSpec(
            id: "load/",
            section: "FILES & FOLDERS",
            category: .folder,
            iconName: "folder",
            title: "load/",
            subtitle: "Folder · 3 files",
            isMonospacedTitle: true,
            usesPlusAffordance: false,
            testId: "ctx-row-load-folder"
        ),
        ContextRowSpec(
            id: "idempotency-payouts",
            section: "MENTIONS",
            category: .mentions,
            iconName: "bubble.left",
            title: "Idempotency keys for payouts",
            subtitle: "Conversation · ledger-svc",
            isMonospacedTitle: false,
            usesPlusAffordance: false,
            testId: "ctx-row-idempotency"
        ),
        ContextRowSpec(
            id: "terminal-last-test",
            section: "MENTIONS",
            category: .mentions,
            iconName: "terminal",
            title: "Terminal · last test run",
            subtitle: "Output · 214 lines",
            isMonospacedTitle: false,
            usesPlusAffordance: false,
            testId: "ctx-row-terminal"
        ),
        ContextRowSpec(
            id: "/plan",
            section: "ACTIONS & SKILLS",
            category: .actions,
            iconName: "slash.circle",
            title: "/plan",
            subtitle: "Action · explore first, then draft a reviewable plan",
            isMonospacedTitle: true,
            usesPlusAffordance: true,
            testId: "ctx-row-plan"
        ),
        ContextRowSpec(
            id: "go-testing",
            section: "ACTIONS & SKILLS",
            category: .skills,
            iconName: "cube",
            title: "go-testing",
            subtitle: "Skill · table-driven tests, -race, golden files",
            isMonospacedTitle: false,
            usesPlusAffordance: false,
            testId: "ctx-row-go-testing"
        )
    ]

    private var effectiveRows: [ContextRowSpec] {
        guard !store.isVerificationMode else { return verificationRows }
        var rows: [ContextRowSpec] = []
        var seenIds = Set<String>()
        for ws in store.workspaces {
            for filePath in ws.indexedFiles.prefix(20) {
                guard seenIds.insert(filePath).inserted else { continue }
                let fileName = filePath.split(separator: "/").last.map(String.init) ?? filePath
                rows.append(
                    ContextRowSpec(
                        id: filePath,
                        section: "FILES & FOLDERS",
                        category: .files,
                        iconName: "doc",
                        title: fileName,
                        subtitle: filePath,
                        isMonospacedTitle: true,
                        usesPlusAffordance: false,
                        testId: "ctx-row-\(fileName)"
                    )
                )
            }
        }
        for summary in store.summaries.prefix(12) {
            let rowId = "conv:\(summary.cascadeId)"
            guard seenIds.insert(rowId).inserted else { continue }
            rows.append(
                ContextRowSpec(
                    id: rowId,
                    section: "MENTIONS",
                    category: .mentions,
                    iconName: "bubble.left",
                    title: summary.title,
                    subtitle: lang.t("Conversation · \(summary.projectSlug)", "对话 · \(summary.projectSlug)"),
                    isMonospacedTitle: false,
                    usesPlusAffordance: false,
                    testId: "ctx-row-\(summary.cascadeId)"
                )
            )
        }
        if seenIds.insert("/plan").inserted {
            rows.append(
                ContextRowSpec(
                    id: "/plan",
                    section: "ACTIONS & SKILLS",
                    category: .actions,
                    iconName: "slash.circle",
                    title: "/plan",
                    subtitle: lang.t("Action · step-by-step implementation plan", "指令 · 制定分步实施方案"),
                    isMonospacedTitle: true,
                    usesPlusAffordance: true,
                    testId: "ctx-row-plan"
                )
            )
        }
        if seenIds.insert("/goal").inserted {
            rows.append(
                ContextRowSpec(
                    id: "/goal",
                    section: "ACTIONS & SKILLS",
                    category: .actions,
                    iconName: "slash.circle",
                    title: "/goal",
                    subtitle: lang.t("Action · thorough autonomous execution", "指令 · 持续自主执行直至达成目标"),
                    isMonospacedTitle: true,
                    usesPlusAffordance: true,
                    testId: "ctx-row-goal"
                )
            )
        }
        return rows
    }

    public init(
        store: AntigravitySessionStore,
        startExpanded: Bool = false,
        showHomeBackdrop: Bool = true,
        isPresentedAsNativeSheet: Bool = false,
        onAddLabels: (([String]) -> Void)? = nil,
        onPickPhotos: (() -> Void)? = nil,
        onPickDeviceFile: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.showHomeBackdrop = showHomeBackdrop
        self.isPresentedAsNativeSheet = isPresentedAsNativeSheet
        self.onAddLabels = onAddLabels
        self.onPickPhotos = onPickPhotos
        self.onPickDeviceFile = onPickDeviceFile
        self.onDismiss = onDismiss
        self._isExpandedToPicker = State(initialValue: startExpanded)
        if store.isVerificationMode {
            self._selectedItemIds = State(initialValue: ["ratelimit.go", "idempotency-payouts", "go-testing"])
        } else {
            self._selectedItemIds = State(initialValue: [])
        }
    }

    private func filteredRows(in section: String, from allRows: [ContextRowSpec]) -> [ContextRowSpec] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allRows.filter { row in
            guard row.section == section else { return false }
            if let cat = activeCategoryFilter, row.category != cat {
                return false
            }
            guard !q.isEmpty else { return true }
            return row.title.lowercased().contains(q) || row.subtitle.lowercased().contains(q)
        }
    }

    public var body: some View {
        if !isExpandedToPicker {
            anchoredAddContextPopover
        } else {
            fullMultiSelectPickerBody
        }
    }

    /// Official anchored `Add Context` popover (`docs/ue/ios/ios-add-context.png`).
    private var anchoredAddContextPopover: some View {
        ZStack(alignment: .bottom) {
            Group {
                if showHomeBackdrop {
                    VStack {
                        Spacer()
                        Text(store.homeAddContextBackdropGreetingText)
                            .font(.system(size: 30, weight: .bold))
                            .multilineTextAlignment(.center)
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
                dismissSheet()
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.t("Add Context", "添加上下文"))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    if let onPickPhotos {
                        popoverCategoryRow(icon: "photo.on.rectangle.angled", title: lang.t("Photos", "相册"), trailingLabel: nil, testId: "ctx-menu-photos") {
                            onPickPhotos()
                        }
                    }
                    popoverCategoryRow(icon: "paperclip", title: lang.t("Files", "文件"), trailingLabel: nil, testId: "ctx-menu-files") {
                        activeCategoryFilter = .files
                        isExpandedToPicker = true
                    }
                    popoverCategoryRow(icon: "folder", title: lang.t("Folder", "文件夹"), trailingLabel: nil, testId: "ctx-menu-folder") {
                        activeCategoryFilter = .folder
                        isExpandedToPicker = true
                    }
                    popoverCategoryRow(icon: "at", title: lang.t("Mentions", "引用"), trailingLabel: nil, testId: "ctx-menu-mentions") {
                        activeCategoryFilter = .mentions
                        isExpandedToPicker = true
                    }
                    popoverCategoryRow(icon: "slash.circle", title: lang.t("Actions", "快捷指令"), trailingLabel: nil, testId: "ctx-menu-actions") {
                        activeCategoryFilter = .actions
                        isExpandedToPicker = true
                    }
                    popoverCategoryRow(icon: "externaldrive", title: lang.t("Drive", "云端硬盘"), trailingLabel: lang.t("Set up", "去配置"), testId: "ctx-menu-drive") {
                        activeCategoryFilter = nil
                        isExpandedToPicker = true
                    }
                }
                .padding(.bottom, 10)
                .frame(width: 274)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AntigravityTheme.surfacePopover)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                )
                .shadow(color: AntigravityTheme.glassShadow, radius: 22, x: 0, y: 10)
                .padding(.leading, 14)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("add-context-popover")

                if showHomeBackdrop {
                    dockedBackdropComposerBar(
                        highlightPermissions: false,
                        highlightAdd: true,
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

    private func popoverCategoryRow(
        icon: String,
        title: String,
        trailingLabel: String?,
        testId: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textBody)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 16.5, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                Spacer()
                if let trailingLabel {
                    Text(trailingLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(testId)
    }

    private var fullMultiSelectPickerBody: some View {
        let allRows = effectiveRows
        return VStack(spacing: 0) {
            if !isPresentedAsNativeSheet {
                Spacer(minLength: 18)
            }

            VStack(spacing: 0) {
                // Sheet Grabber (only needed outside native .sheet which draws its own drag indicator)
                if !isPresentedAsNativeSheet {
                    Capsule()
                        .fill(AntigravityTheme.sheetHandle)
                        .frame(width: 38, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                }

                // Header Bar
                ZStack {
                    Text(lang.t("Add Context", "添加上下文"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AntigravityTheme.inkReading)

                    HStack {
                        Spacer()
                        Button {
                            dismissSheet()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(AntigravityTheme.surfaceBadge)
                                    .frame(width: 32, height: 32)
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AntigravityTheme.inkLabel)
                            }
                            .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("btn-close-add-context")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, isPresentedAsNativeSheet ? 10 : 0)

                // Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    TextField(lang.t("Search files, folders, skills...", "搜索文件、文件夹、技能..."), text: $searchQuery)
                        .font(.system(size: 15))
                        .foregroundStyle(AntigravityTheme.inkReading)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                .background(AntigravityTheme.surfaceBadge)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityIdentifier("context-search-input")

                // 5 Category Tiles
                HStack(spacing: 8) {
                    ForEach(CategoryTile.allCases) { tile in
                        let isSelected = activeCategoryFilter == tile
                        Button {
                            activeCategoryFilter = (activeCategoryFilter == tile) ? nil : tile
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: tile.iconName)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(isSelected ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.inkReading)
                                Text(tile.localizedTitle(for: lang))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(isSelected ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.inkLabel)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background(isSelected ? AntigravityTheme.surfaceSelectionTint : AntigravityTheme.surfaceSheetGroup)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(
                                        isSelected ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.cardBorder,
                                        lineWidth: isSelected ? 1.5 : 1
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(tile.testId)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Grouped Sections ScrollView
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !store.isVerificationMode, (onPickPhotos != nil || onPickDeviceFile != nil) {
                            HStack(spacing: 10) {
                                if let onPickPhotos {
                                    Button {
                                        onPickPhotos()
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "photo.on.rectangle.angled")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                                .frame(width: 22)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(lang.t("Photos", "相册"))
                                                    .font(.system(size: 14.5, weight: .semibold))
                                                    .foregroundStyle(AntigravityTheme.inkReading)
                                                    .lineLimit(1)
                                                Text(lang.t("Photo Library", "照片图库"))
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 13)
                                        .frame(maxWidth: .infinity, minHeight: 54)
                                        .background(AntigravityTheme.surfaceSheetGroup)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(lang.t("Choose images from Photos", "从相册选择图片"))
                                    .accessibilityIdentifier("ctx-row-pick-photos")
                                }

                                if let onPickDeviceFile {
                                    Button {
                                        onPickDeviceFile()
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "paperclip")
                                                .font(.system(size: 15.5, weight: .semibold))
                                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                                .frame(width: 22)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(lang.t("Files", "文件"))
                                                    .font(.system(size: 14.5, weight: .semibold))
                                                    .foregroundStyle(AntigravityTheme.inkReading)
                                                    .lineLimit(1)
                                                Text(lang.t("PDF, doc, media", "PDF、文档、媒体"))
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 13)
                                        .frame(maxWidth: .infinity, minHeight: 54)
                                        .background(AntigravityTheme.surfaceSheetGroup)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(lang.t("Attach file or media from Files", "从“文件”附加文档或媒体"))
                                    .accessibilityIdentifier("ctx-row-attach-device-file")
                                }
                            }
                        }

                        ForEach(["FILES & FOLDERS", "MENTIONS", "ACTIONS & SKILLS"], id: \.self) { sectionTitle in
                            let rows = filteredRows(in: sectionTitle, from: allRows)
                            if !rows.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(localizedSectionTitle(sectionTitle))
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .tracking(0.6)
                                        .foregroundStyle(AntigravityTheme.inkSecondary)
                                        .padding(.horizontal, 4)

                                    VStack(spacing: 0) {
                                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                                            contextRowButton(row)
                                            if idx < rows.count - 1 {
                                                Divider()
                                                    .overlay(AntigravityTheme.subtleDivider)
                                                    .padding(.leading, 44)
                                            }
                                        }
                                    }
                                    .background(AntigravityTheme.surfaceSheetGroup)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                // Sticky Bottom Footer
                Divider()
                    .overlay(AntigravityTheme.subtleDivider)

                HStack {
                    Text(lang.t("\(selectedItemIds.count) selected", "已选 \(selectedItemIds.count) 项"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)

                    Spacer()

                    Button {
                        commitSelection()
                    } label: {
                        Text(lang.t("Add to message", "添加到消息"))
                            .font(.system(size: 15.5, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                            .padding(.horizontal, 24)
                            .frame(minHeight: 48)
                            .background(AntigravityTheme.accentPeriwinkle)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-add-to-message")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(AntigravityTheme.surfaceSheet)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: isPresentedAsNativeSheet ? 0 : 28,
                    style: .continuous
                )
            )
        }
        .background(isPresentedAsNativeSheet ? AntigravityTheme.surfaceSheet : AntigravityTheme.canvasObsidian)
    }

    private func contextRowButton(_ row: ContextRowSpec) -> some View {
        let isSelected = selectedItemIds.contains(row.id)
        return Button {
            if isSelected {
                selectedItemIds.remove(row.id)
            } else {
                selectedItemIds.insert(row.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: row.iconName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(
                            row.isMonospacedTitle
                                ? .system(size: 14.5, weight: .medium, design: .monospaced)
                                : .system(size: 15, weight: .medium)
                        )
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    ZStack {
                        Circle()
                            .fill(AntigravityTheme.accentPeriwinkle)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                    }
                } else if row.usesPlusAffordance {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .frame(width: 24, height: 24)
                } else {
                    Circle()
                        .stroke(AntigravityTheme.inkSecondary.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(row.testId)
    }

    private func commitSelection() {
        let rows = effectiveRows
        let labels = rows
            .filter { selectedItemIds.contains($0.id) }
            .map { row in
                row.category == .files ? "@\(row.title)" : row.title
            }
        if store.isVerificationMode && selectedItemIds.contains("ratelimit.go") {
            store.attachFileMention("internal/middleware/ratelimit.go")
        } else {
            for row in rows where selectedItemIds.contains(row.id) && row.category == .files {
                store.attachFileMention(row.id)
            }
        }
        onAddLabels?(labels)
        dismissSheet()
    }

    private func dismissSheet() {
        if let onDismiss {
            onDismiss()
        } else {
            store.currentRoute = .chatAndComposer
        }
    }
}
