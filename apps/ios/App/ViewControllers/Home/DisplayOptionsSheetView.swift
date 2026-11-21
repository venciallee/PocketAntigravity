import SwiftUI
import AntigravityData

/// State `UE02_DISPLAY_OPTIONS`: Display Options & Sort Conversations Popover Sheet.
/// Matches `/home/antigravity/iOS_·_Display_Options.png` 1:1.
public struct DisplayOptionsSheetView: View {
    @Bindable public var store: AntigravitySessionStore
    public var onDismiss: (() -> Void)?

    public enum GroupByOption: String, CaseIterable {
        case project = "Project"
        case host = "Host"
        case none = "None"
    }

    public enum ConversationSortField: String, CaseIterable, Identifiable {
        case lastUpdated = "Last Updated"
        case dateCreated = "Date Created"
        case title = "Title"

        public var id: String { rawValue }
    }

    public enum SortOrderDirection: String, CaseIterable, Identifiable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"

        public var id: String { rawValue }
    }

    @State private var groupBy: GroupByOption = .project
    @State private var sortField: ConversationSortField = .lastUpdated
    @State private var sortDirection: SortOrderDirection = .newestFirst
    @State private var sortProjectsLabel: String = "Custom Order"
    @State private var autoPin: Bool = false
    @State private var archivedOnly: Bool = false
    @State private var unreadCount: Int = 3
    @State private var isSortPopoverPresented: Bool = true

    public init(
        store: AntigravitySessionStore,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Dimmed Agents backdrop matching UE02 reference composition
            VStack(alignment: .leading, spacing: 0) {
                Text("Agents")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AntigravityTheme.textPrimary.opacity(0.24))
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

                // Floating iOS pull-down Sort Popover Menu anchored below "Sort Conversations"
                if isSortPopoverPresented {
                    sortPopoverMenu
                        .padding(.top, 180)
                        .padding(.trailing, 24)
                }
            }
            .padding(.top, 108)
            .ignoresSafeArea(edges: .bottom)
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
    }

    // MARK: - Header Bar (Reset / Display Options / Done)

    private var sheetHeaderBar: some View {
        HStack {
            Button {
                groupBy = .project
                sortField = .lastUpdated
                sortDirection = .newestFirst
                autoPin = false
                archivedOnly = false
            } label: {
                Text("Reset")
                    .font(.system(size: 16.5, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textSecondary)
                    .frame(minWidth: 56, minHeight: AntigravityTheme.minTouchTargetPt, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sheet-reset-btn")

            Spacer()

            Text("Display Options")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AntigravityTheme.textPrimary)

            Spacer()

            Button {
                isSortPopoverPresented = false
                onDismiss?()
            } label: {
                Text("Done")
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
                if let idx = all.firstIndex(of: groupBy) {
                    groupBy = all[(idx + 1) % all.count]
                }
            } label: {
                HStack {
                    Text("Group By")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(groupBy.rawValue)
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
                isSortPopoverPresented.toggle()
            } label: {
                HStack {
                    Text("Sort Conversations")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(sortField.rawValue)
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
                sortProjectsLabel = (sortProjectsLabel == "Custom Order") ? "Alphabetical" : "Custom Order"
            } label: {
                HStack {
                    Text("Sort Projects")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(sortProjectsLabel)
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
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AntigravityTheme.surfaceSheetGroup)
        )
    }

    // MARK: - Card 2: Filter / Display

    private var filterAndDisplayCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Filter")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                Spacer()
                HStack(spacing: 6) {
                    Text("All conversations")
                        .font(.system(size: 15.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textMuted)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            HStack {
                Text("Display")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                Spacer()
                HStack(spacing: 6) {
                    Text("Comfortable · Previews")
                        .font(.system(size: 15.5, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textMuted)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
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
                    autoPin.toggle()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto Pin")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Text("Pin a conversation when you message it")
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

                Toggle("", isOn: $autoPin)
                    .labelsHidden()
                    .tint(AntigravityTheme.accentPeriwinkle)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Archived Only")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Text("Show only archived conversations")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                }

                Spacer()

                Toggle("", isOn: $archivedOnly)
                    .labelsHidden()
                    .tint(AntigravityTheme.accentPeriwinkle)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .accessibilityIdentifier("toggle-archived-only")
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AntigravityTheme.surfaceSheetGroup)
        )
    }

    // MARK: - Card 4: Mark All as Read

    private var markAllAsReadCard: some View {
        Button {
            unreadCount = 0
        } label: {
            HStack {
                Text("Mark All as Read")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                Spacer()
                Text("\(unreadCount) unread")
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
                    sortField = field
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(sortField == field ? AntigravityTheme.textPrimary : Color.clear)
                            .frame(width: 16)
                        Text(field.rawValue)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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
                    sortDirection = direction
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(sortDirection == direction ? AntigravityTheme.textPrimary : Color.clear)
                            .frame(width: 16)
                        Text(direction.rawValue)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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
        .accessibilityIdentifier("sort-popover-menu")
    }
}
