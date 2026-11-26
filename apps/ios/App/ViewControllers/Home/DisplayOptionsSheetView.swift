import SwiftUI
import AntigravityData

/// State `UE02_DISPLAY_OPTIONS`: Display Options & Sort Conversations Popover Sheet.
/// Matches `/home/antigravity/iOS_·_Display_Options.png` 1:1.
public struct DisplayOptionsSheetView: View {
    @Bindable public var store: AntigravitySessionStore
    public var onDismiss: (() -> Void)?

    public typealias GroupByOption = DisplayGroupBy
    public typealias ConversationSortField = AntigravityData.ConversationSortField

    public enum SortOrderDirection: String, CaseIterable, Identifiable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"

        public var id: String { rawValue }

        public func localizedTitle(for language: AppLanguage) -> String {
            switch self {
            case .newestFirst: return language.t("Newest First", "最新优先")
            case .oldestFirst: return language.t("Oldest First", "最早优先")
            }
        }
    }

    @State private var isSortPopoverPresented: Bool

    public init(
        store: AntigravitySessionStore,
        initialSortPopoverPresented: Bool? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.onDismiss = onDismiss
        _isSortPopoverPresented = State(
            initialValue: initialSortPopoverPresented ?? (store.isVerificationMode && store.isSortPopoverPresented)
        )
    }

    private var lang: AppLanguage {
        store.appearancePreferences.language
    }

    private var currentSortDirection: SortOrderDirection {
        store.displayOptions.newestFirst ? .newestFirst : .oldestFirst
    }

    private var autoPinBinding: Binding<Bool> {
        Binding(
            get: { store.displayOptions.autoPinOnMessage },
            set: { newValue in
                store.updateDisplayOptions { $0.autoPinOnMessage = newValue }
            }
        )
    }

    private var archivedOnlyBinding: Binding<Bool> {
        Binding(
            get: { store.displayOptions.archivedOnly },
            set: { newValue in
                store.updateDisplayOptions { $0.archivedOnly = newValue }
            }
        )
    }

    private func localizedSortProjectsOrder(_ raw: String) -> String {
        switch raw {
        case "Custom Order": return lang.t("Custom Order", "自定义顺序")
        case "Alphabetical": return lang.t("Alphabetical", "按字母排序")
        default: return raw
        }
    }

    private func localizedFilterScope(_ raw: String) -> String {
        switch raw {
        case "All conversations": return lang.t("All conversations", "全部对话")
        case "Active only": return lang.t("Active only", "仅进行中")
        default: return raw
        }
    }

    private func localizedDensity(_ raw: String) -> String {
        if raw.hasPrefix("Comfortable") {
            return lang.t("Comfortable · Previews", "舒适 · 显示预览")
        }
        if raw.hasPrefix("Compact") {
            return lang.t("Compact · Titles only", "紧凑 · 仅标题")
        }
        return raw
    }

    private func setSortPopoverPresented(_ presented: Bool) {
        if store.isVerificationMode {
            isSortPopoverPresented = presented
        } else {
            withAnimation(.easeOut(duration: 0.16)) {
                isSortPopoverPresented = presented
            }
        }
        store.isSortPopoverPresented = presented
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Dimmed Sidebar Projects backdrop matching UE02 reference composition (`ios-display-options.png`)
            VStack(alignment: .leading, spacing: 0) {
                Text(lang.t("Projects", "项目"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AntigravityTheme.textSecondary.opacity(0.45))
                    .padding(.leading, 18)
                    .padding(.top, 56)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                ZStack {
                    AntigravityTheme.canvasObsidian
                    AntigravityTheme.scrimOverlay
                }
                .ignoresSafeArea()
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if isSortPopoverPresented {
                    setSortPopoverPresented(false)
                } else {
                    onDismiss?()
                }
            }

            // Bottom Sheet Surface
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    Capsule()
                        .fill(AntigravityTheme.sheetHandle)
                        .frame(width: 38, height: 5)
                        .padding(.top, 10)

                    sheetHeaderBar

                    VStack(spacing: 12) {
                        groupingAndSortingCard
                        filterAndDisplayCard
                        togglesCard
                        markAllAsReadCard
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 10)
                }
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 28,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 28,
                        style: .continuous
                    )
                    .fill(AntigravityTheme.surfaceSheet)
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

                // Transparent full-sheet dismiss scrim + floating Sort Popover Menu anchored below "Sort Conversations"
                if isSortPopoverPresented {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            setSortPopoverPresented(false)
                        }
                        .accessibilityIdentifier("sort-popover-dismiss-scrim")

                    sortPopoverMenu
                        .padding(.top, 180)
                        .padding(.trailing, 24)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                }
            }
            .padding(.top, 108)
            .ignoresSafeArea(edges: .bottom)
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
        .onDisappear {
            if !store.isVerificationMode {
                store.isSortPopoverPresented = false
            }
        }
    }

    // MARK: - Header Bar (Reset / Display Options / Done)

    private var sheetHeaderBar: some View {
        HStack {
            Button {
                setSortPopoverPresented(false)
                store.resetDisplayOptions()
            } label: {
                Text(lang.t("Reset", "重置"))
                    .font(.system(size: 16.5, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textSecondary)
                    .frame(minWidth: 56, minHeight: AntigravityTheme.minTouchTargetPt, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sheet-reset-btn")

            Spacer()

            Text(lang.t("Display Options", "显示选项"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AntigravityTheme.textPrimary)

            Spacer()

            Button {
                setSortPopoverPresented(false)
                onDismiss?()
            } label: {
                Text(lang.t("Done", "完成"))
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .frame(minWidth: 56, minHeight: AntigravityTheme.minTouchTargetPt, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sheet-done-btn")
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Card 1: Group By / Sort Conversations / Sort Projects

    private var groupingAndSortingCard: some View {
        VStack(spacing: 0) {
            Button {
                let all = GroupByOption.allCases
                if let idx = all.firstIndex(of: store.displayOptions.groupBy) {
                    let next = all[(idx + 1) % all.count]
                    store.updateDisplayOptions { $0.groupBy = next }
                }
            } label: {
                HStack {
                    Text(lang.t("Group By", "分组方式"))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(store.displayOptions.groupBy.localizedTitle(for: lang))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("row-group-by")

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            Button {
                setSortPopoverPresented(!isSortPopoverPresented)
            } label: {
                HStack {
                    Text(lang.t("Sort Conversations", "对话排序"))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(store.displayOptions.sortBy.localizedTitle(for: lang))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(isSortPopoverPresented ? AntigravityTheme.textPrimary.opacity(0.05) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("row-sort-conversations")

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            Button {
                let nextOrder = (store.displayOptions.sortProjectsOrder == "Custom Order") ? "Alphabetical" : "Custom Order"
                store.updateDisplayOptions { $0.sortProjectsOrder = nextOrder }
            } label: {
                HStack {
                    Text(lang.t("Sort Projects", "项目排序"))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(localizedSortProjectsOrder(store.displayOptions.sortProjectsOrder))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("row-sort-projects")
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AntigravityTheme.surfaceSheetGroup)
        )
    }

    // MARK: - Card 2: Filter / Display

    private var filterAndDisplayCard: some View {
        VStack(spacing: 0) {
            Button {
                let nextFilter = (store.displayOptions.filterScopeLabel == "All conversations")
                    ? "Active only"
                    : "All conversations"
                store.updateDisplayOptions { $0.filterScopeLabel = nextFilter }
            } label: {
                HStack {
                    Text(lang.t("Filter", "筛选"))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(localizedFilterScope(store.displayOptions.filterScopeLabel))
                            .font(.system(size: 15.5, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.textMuted)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("row-filter-scope")

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            Button {
                let nextDensity = store.displayOptions.densityLabel.hasPrefix("Comfortable")
                    ? "Compact · Titles only"
                    : "Comfortable · Previews"
                store.updateDisplayOptions { $0.densityLabel = nextDensity }
            } label: {
                HStack {
                    Text(lang.t("Display", "视图密度"))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(localizedDensity(store.displayOptions.densityLabel))
                            .font(.system(size: 15.5, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.textMuted)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("row-display-density")
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AntigravityTheme.surfaceSheetGroup)
        )
    }

    // MARK: - Card 3: Auto Pin & Archived Only Toggles

    private var togglesCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    store.updateDisplayOptions { $0.autoPinOnMessage.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.t("Auto Pin", "自动置顶"))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Text(lang.t("Pin a conversation when you message it", "发送消息后自动置顶该对话"))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toggle-auto-pin")

                Spacer()

                Toggle("", isOn: autoPinBinding)
                    .labelsHidden()
                    .tint(AntigravityTheme.accentPeriwinkle)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            HStack(spacing: 12) {
                Button {
                    store.updateDisplayOptions { $0.archivedOnly.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.t("Archived Only", "仅显示已归档"))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Text(lang.t("Show only archived conversations", "只展示已归档的对话"))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toggle-archived-only")

                Spacer()

                Toggle("", isOn: archivedOnlyBinding)
                    .labelsHidden()
                    .tint(AntigravityTheme.accentPeriwinkle)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AntigravityTheme.surfaceSheetGroup)
        )
    }

    // MARK: - Card 4: Mark All as Read

    private var markAllAsReadCard: some View {
        Button {
            store.markAllConversationsAsRead()
        } label: {
            HStack {
                Text(lang.t("Mark All as Read", "全部标为已读"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                Spacer()
                Text(lang.t("\(store.unreadCount) unread", "\(store.unreadCount) 条未读"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AntigravityTheme.surfaceSheetGroup)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("btn-mark-all-read")
    }

    // MARK: - Sort Popover Menu

    private var sortPopoverMenu: some View {
        VStack(spacing: 0) {
            ForEach(Array(ConversationSortField.allCases.enumerated()), id: \.element.id) { index, field in
                Button {
                    store.updateDisplayOptions { $0.sortBy = field }
                    setSortPopoverPresented(false)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(store.displayOptions.sortBy == field ? AntigravityTheme.textPrimary : Color.clear)
                            .frame(width: 16)
                        Text(field.localizedTitle(for: lang))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sort-opt-\(field.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")

                if index < ConversationSortField.allCases.count - 1 {
                    Divider()
                        .overlay(AntigravityTheme.subtleDivider)
                }
            }

            Rectangle()
                .fill(AntigravityTheme.surfaceElevated)
                .frame(height: 7)

            ForEach(Array(SortOrderDirection.allCases.enumerated()), id: \.element.id) { index, direction in
                Button {
                    store.updateDisplayOptions { $0.newestFirst = (direction == .newestFirst) }
                    setSortPopoverPresented(false)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(currentSortDirection == direction ? AntigravityTheme.textPrimary : Color.clear)
                            .frame(width: 16)
                        Text(direction.localizedTitle(for: lang))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(direction == .newestFirst ? "sort-dir-newest" : "sort-dir-oldest")

                if index < SortOrderDirection.allCases.count - 1 {
                    Divider()
                        .overlay(AntigravityTheme.subtleDivider)
                }
            }
        }
        .frame(width: 236)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AntigravityTheme.surfacePopover.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AntigravityTheme.glassHairline, lineWidth: 1)
        )
        .shadow(color: AntigravityTheme.glassShadow, radius: 24, x: 0, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sort-popover-menu")
    }
}
