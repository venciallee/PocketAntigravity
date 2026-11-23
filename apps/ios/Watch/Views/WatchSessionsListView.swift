import SwiftUI
import AntigravityData

/// Screen `W01_SESSIONS`: Watch · 会话列表 (`Agents` home with device selector, voice shortcut & live status rows).
public struct WatchSessionsListView: View {
    @Bindable public var store: WatchAppStore

    public init(store: WatchAppStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topActionBar
                    .padding(.horizontal, 8)
                    .padding(.top, WatchTheme.topSafeInsetWithRightChrome)

                headerTitleRow
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 5)

                if store.snapshot.sessions.isEmpty {
                    emptyStateCard
                        .padding(.horizontal, WatchTheme.horizontalInset)
                } else {
                    VStack(spacing: 5) {
                        ForEach(store.snapshot.sessions) { session in
                            sessionRowCard(session)
                        }
                    }
                    .padding(.horizontal, WatchTheme.horizontalInset)
                    .padding(.bottom, 16)
                }
            }
        }
        .contentMargins(.vertical, 0, for: .scrollContent)
        .background(WatchTheme.canvas.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .toolbar(.hidden, for: .automatic)
    }

    private var topActionBar: some View {
        HStack {
            Button {
                WatchHaptics.click()
                store.navigationPath.append(.devices)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: store.snapshot.activeDeviceKind.sfSymbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WatchTheme.inkPrimary)
                        .frame(width: WatchTheme.topChromeDiameter, height: WatchTheme.topChromeDiameter)
                        .background(Circle().fill(WatchTheme.topChromeCircle))

                    Circle()
                        .fill(store.snapshot.activeDeviceOnline ? WatchTheme.emerald : WatchTheme.inkMuted)
                        .frame(width: 9, height: 9)
                        .overlay(
                            Circle()
                                .stroke(WatchTheme.canvas, lineWidth: 1.5)
                        )
                        .offset(x: 1, y: -1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("watch.home.devicesButton")

            Spacer()

            WatchCircleChromeButton(
                systemName: "mic",
                foreground: WatchTheme.inkOnPeriwinkle,
                background: WatchTheme.accentPeriwinkle,
                diameter: WatchTheme.topChromeDiameter,
                iconSize: 13.5,
                accessibilityId: "watch.home.voiceButton"
            ) {
                store.openNewVoiceTask()
            }
        }
    }

    private var headerTitleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Agents")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(WatchTheme.inkPrimary)
            Spacer(minLength: 4)
            Button {
                WatchHaptics.click()
                store.navigationPath.append(.devices)
            } label: {
                Text(store.snapshot.activeDeviceName)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(WatchTheme.inkSecondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("watch.home.activeDeviceLabel")
        }
    }

    private func sessionRowCard(_ session: WatchSessionSnapshot) -> some View {
        Button {
            WatchHaptics.click()
            store.navigationPath.append(.chat(cascadeId: session.cascadeId))
        } label: {
            HStack(alignment: .top, spacing: 7) {
                leadingIndicator(for: session)
                    .frame(width: 15, height: 17, alignment: .center)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(session.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(WatchTheme.inkPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    sessionSubtitleView(for: session)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WatchTheme.cardCornerRadius, style: .continuous)
                    .fill(WatchTheme.card)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watch.home.session.\(session.cascadeId)")
    }

    @ViewBuilder
    private func leadingIndicator(for session: WatchSessionSnapshot) -> some View {
        switch session.status {
        case .waitingApproval:
            WatchAmberHaloDot()
        case .running:
            WatchRunningArcView(
                size: 13.5,
                lineWidth: 2.0,
                isAnimated: !store.isVerificationMode
            )
        case .done:
            Circle()
                .fill(session.hasUnread ? WatchTheme.accentPeriwinkle : WatchTheme.emerald)
                .frame(width: 8, height: 8)
        case .error:
            Circle()
                .fill(WatchTheme.coralRed)
                .frame(width: 8, height: 8)
        case .idle:
            Circle()
                .fill(WatchTheme.inkMuted)
                .frame(width: 7, height: 7)
        }
    }

    @ViewBuilder
    private func sessionSubtitleView(for session: WatchSessionSnapshot) -> some View {
        switch session.status {
        case .waitingApproval:
            Text(session.statusSubtitle.isEmpty ? "Approve command" : session.statusSubtitle)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(WatchTheme.amber)
        case .running:
            Text(session.statusSubtitle.isEmpty ? "Running" : session.statusSubtitle)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(WatchTheme.accentPeriwinkle)
        case .done:
            if session.additions > 0 || session.deletions > 0 {
                (
                    Text("Done · ")
                        .foregroundStyle(WatchTheme.inkSecondary)
                    + Text("+\(session.additions)")
                        .foregroundStyle(WatchTheme.emerald)
                    + Text(" ")
                        .foregroundStyle(WatchTheme.inkSecondary)
                    + Text("\u{2212}\(session.deletions)")
                        .foregroundStyle(WatchTheme.coralRed)
                )
                .font(.system(size: 12.5, weight: .regular))
            } else {
                Text("Done")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(WatchTheme.inkSecondary)
            }
        case .error:
            Text(session.statusSubtitle.isEmpty ? "Needs attention" : session.statusSubtitle)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(WatchTheme.coralRed)
        case .idle:
            Text(session.statusSubtitle.isEmpty ? "Ready" : session.statusSubtitle)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(WatchTheme.inkSecondary)
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No active agents")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WatchTheme.inkPrimary)
            Text("Open AG Pocket on iPhone to sync hosts and sessions.")
                .font(.system(size: 12))
                .foregroundStyle(WatchTheme.inkSecondary)
            Button {
                WatchHaptics.click()
                store.requestRefreshFromPhone()
            } label: {
                Text("Sync now")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(WatchTheme.inkOnPeriwinkle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(WatchTheme.accentPeriwinkle))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: WatchTheme.cardCornerRadius, style: .continuous)
                .fill(WatchTheme.card)
        )
    }
}
