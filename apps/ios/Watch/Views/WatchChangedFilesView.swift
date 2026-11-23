import SwiftUI
import AntigravityData

/// Screens `W05_CHANGED_FILES_COMPACT` (<= 5 files AND zero risk items -> Watch `Accept all`)
/// & `W06_CHANGED_FILES_GROUPED` (> 5 files OR any risk item -> `WORTH A LOOK` + intent groups + iPhone review).
/// Never displays source code diffs on Apple Watch—only file path, `A`/`M`/`D` badge, and a one-line summary.
public struct WatchChangedFilesView: View {
    @Bindable public var store: WatchAppStore
    public let cascadeId: String
    public var onBack: () -> Void
    @State private var expandedGroupIds: Set<String> = []

    public init(store: WatchAppStore, cascadeId: String, onBack: @escaping () -> Void) {
        self.store = store
        self.cascadeId = cascadeId
        self.onBack = onBack
    }

    private var session: WatchSessionSnapshot? {
        store.session(for: cascadeId) ?? store.snapshot.sessions.first
    }

    private var changes: WatchChangesSnapshot {
        session?.changes ?? WatchVerificationFixtures.makeCompactChanges()
    }

    private var isAccepted: Bool {
        store.acceptedChangesCascadeIds.contains(cascadeId)
    }

    private var showsCompactAcceptBar: Bool {
        changes.canAcceptAllOnWatch
    }

    public var body: some View {
        ZStack(alignment: showsCompactAcceptBar ? .bottom : .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    WatchNavigationHeader(title: "Changes", onBack: onBack)

                    statsHeaderLine
                        .padding(.horizontal, 8)
                        .padding(.bottom, 2)

                    if changes.isGroupedMode || !changes.worthALookFiles.isEmpty {
                        groupedChangesContent
                    } else {
                        compactChangesContent
                    }
                }
                .padding(.bottom, 54)
            }
            .contentMargins(.vertical, 0, for: .scrollContent)
            .background(WatchTheme.canvas.ignoresSafeArea())

            if showsCompactAcceptBar {
                compactBottomActionBar
            } else {
                floatingPhoneHandoffButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .automatic)
        .onAppear {
            store.advertiseHandoff(cascadeId: cascadeId, target: .changes)
        }
    }

    private var statsHeaderLine: some View {
        (
            Text("\(changes.totalFiles) \(changes.totalFiles == 1 ? "file" : "files") · ")
                .foregroundStyle(WatchTheme.inkSecondary)
            + Text("+\(changes.totalAdditions)")
                .foregroundStyle(WatchTheme.emerald)
            + Text(" ")
                .foregroundStyle(WatchTheme.inkSecondary)
            + Text("-\(changes.totalDeletions)")
                .foregroundStyle(WatchTheme.coralRed)
        )
        .font(.system(size: 12, weight: .regular))
        .lineLimit(1)
    }

    // MARK: - W05 Compact Mode (<= 5 files AND zero risk items)

    private var compactChangesContent: some View {
        VStack(spacing: 4.5) {
            ForEach(changes.compactFiles) { file in
                compactFileCard(file)
            }
        }
        .padding(.horizontal, WatchTheme.horizontalInset)
    }

    private func compactFileCard(_ file: WatchChangedFileItem) -> some View {
        HStack(spacing: 6.5) {
            fileStatusBadge(file.statusLetter)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName)
                    .font(.system(size: 12.2, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WatchTheme.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(file.summary)
                    .font(.system(size: 10.8, weight: .regular))
                    .foregroundStyle(WatchTheme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 0.5) {
                if file.additions > 0 {
                    Text("+\(file.additions)")
                        .font(.system(size: 10.8, weight: .regular, design: .monospaced))
                        .foregroundStyle(WatchTheme.emerald)
                }
                if file.deletions > 0 {
                    Text("-\(file.deletions)")
                        .font(.system(size: 10.8, weight: .regular, design: .monospaced))
                        .foregroundStyle(WatchTheme.coralRed)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: WatchTheme.cardCornerRadius, style: .continuous)
                .fill(WatchTheme.card)
        )
        .accessibilityIdentifier("watch.changes.file.\(file.filePath)")
    }

    private var compactBottomActionBar: some View {
        HStack(spacing: 7) {
            WatchCircleChromeButton(
                systemName: "iphone",
                foreground: WatchTheme.inkPrimary,
                background: WatchTheme.elevatedButton,
                diameter: WatchTheme.bottomControlHeight,
                iconSize: 14,
                accessibilityId: "watch.changes.openOnPhone"
            ) {
                store.openOnPhone(cascadeId: cascadeId, target: .changes)
            }

            Button {
                store.acceptAllChanges(for: cascadeId)
            } label: {
                HStack(spacing: 5) {
                    if isAccepted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12.5, weight: .bold))
                    }
                    Text(isAccepted ? "Accepted" : "Accept all")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(WatchTheme.inkOnPeriwinkle)
                .frame(maxWidth: .infinity)
                .frame(height: WatchTheme.bottomControlHeight)
                .background(
                    Capsule().fill(isAccepted ? WatchTheme.emerald : WatchTheme.accentPeriwinkle)
                )
            }
            .buttonStyle(.plain)
            .watchPrimaryDoubleTap(enabled: !isAccepted)
            .accessibilityIdentifier("watch.changes.acceptAll")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, WatchTheme.bottomBezelInset)
        .background(
            LinearGradient(
                colors: [WatchTheme.canvas.opacity(0.0), WatchTheme.canvas.opacity(0.92), WatchTheme.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - W06 Intent-Grouped Triage Mode (> 5 files OR any risk item)

    private var groupedChangesContent: some View {
        VStack(alignment: .leading, spacing: 4.5) {
            if !changes.worthALookFiles.isEmpty {
                Text("WORTH A LOOK · \(changes.worthALookFiles.count)")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(WatchTheme.amber)
                    .padding(.horizontal, 8)
                    .padding(.top, 1)

                VStack(spacing: 4.5) {
                    ForEach(changes.worthALookFiles) { file in
                        worthALookCard(file)
                    }
                }
                .padding(.horizontal, WatchTheme.horizontalInset)
            }

            if !changes.intentGroups.isEmpty {
                Text("GROUPED · \(changes.groupedFileCount)")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(WatchTheme.inkMuted)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                VStack(spacing: 4.5) {
                    ForEach(changes.intentGroups) { group in
                        intentGroupCard(group)
                    }
                }
                .padding(.horizontal, WatchTheme.horizontalInset)
            }
        }
    }

    private func worthALookCard(_ file: WatchChangedFileItem) -> some View {
        HStack(spacing: 7) {
            fileStatusBadge(file.statusLetter)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName)
                    .font(.system(size: 12.2, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WatchTheme.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(file.summary)
                    .font(.system(size: 11.2, weight: .regular))
                    .foregroundStyle(WatchTheme.amberSubtitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: WatchTheme.cardCornerRadius, style: .continuous)
                .fill(WatchTheme.cardWorthALook)
        )
        .accessibilityIdentifier("watch.changes.worthALook.\(file.filePath)")
    }

    private func intentGroupCard(_ group: WatchFileIntentGroup) -> some View {
        let isExpanded = expandedGroupIds.contains(group.id)
        return Button {
            WatchHaptics.click()
            if isExpanded {
                expandedGroupIds.remove(group.id)
            } else {
                expandedGroupIds.insert(group.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text("\(group.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WatchTheme.inkPrimary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                .fill(WatchTheme.countTile)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(WatchTheme.inkPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(group.subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(WatchTheme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }

                if isExpanded && !group.filePaths.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(group.filePaths.prefix(5), id: \.self) { path in
                            Text(path)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(WatchTheme.inkSecondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        if group.filePaths.count > 5 {
                            Text("+\(group.filePaths.count - 5) more on iPhone")
                                .font(.system(size: 10.5))
                                .foregroundStyle(WatchTheme.accentPeriwinkle)
                        }
                    }
                    .padding(.leading, 27)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WatchTheme.cardCornerRadius, style: .continuous)
                    .fill(WatchTheme.card)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watch.changes.group.\(group.id)")
    }

    private var floatingPhoneHandoffButton: some View {
        Button {
            store.openOnPhone(cascadeId: cascadeId, target: .changes)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "iphone")
                    .font(.system(size: 13, weight: .semibold))
                Text("iPhone")
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundStyle(WatchTheme.inkOnPeriwinkle)
            .padding(.horizontal, 14)
            .frame(height: WatchTheme.bottomControlHeight)
            .background(Capsule().fill(WatchTheme.accentPeriwinkle))
        }
        .buttonStyle(.plain)
        .watchPrimaryDoubleTap()
        .padding(.trailing, 8)
        .padding(.bottom, WatchTheme.bottomBezelInset)
        .accessibilityIdentifier("watch.changes.handoffIPhone")
    }

    // MARK: - Shared File Status Letter Tile

    private func fileStatusBadge(_ status: WatchFileStatusLetter) -> some View {
        let colors: (bg: Color, fg: Color) = {
            switch status {
            case .added: return (WatchTheme.iconTileGreen, WatchTheme.emerald)
            case .modified: return (WatchTheme.iconTileBlue, WatchTheme.accentPeriwinkle)
            case .deleted: return (WatchTheme.iconTileRed, WatchTheme.coralRed)
            case .renamed: return (WatchTheme.iconTileBlue, WatchTheme.accentPeriwinkle)
            }
        }()

        return Text(status.rawValue)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(colors.fg)
            .frame(width: 19, height: 19)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(colors.bg)
            )
    }
}
