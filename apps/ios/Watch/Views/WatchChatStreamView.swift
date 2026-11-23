import SwiftUI
import AntigravityData

/// Screen `W03_CHAT_STREAM`: Watch · 对话流 (status header, voice/agent messages, Walkthrough card, diff pill & floating voice FAB).
public struct WatchChatStreamView: View {
    @Bindable public var store: WatchAppStore
    public let cascadeId: String
    public var onBack: () -> Void

    public init(store: WatchAppStore, cascadeId: String, onBack: @escaping () -> Void) {
        self.store = store
        self.cascadeId = cascadeId
        self.onBack = onBack
    }

    private var session: WatchSessionSnapshot {
        store.session(for: cascadeId)
            ?? store.snapshot.sessions.first
            ?? WatchVerificationFixtures.makeSnapshot(for: .chatStream).sessions[0]
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    WatchNavigationHeader(title: session.title, onBack: onBack)

                    VStack(alignment: .leading, spacing: 9) {
                        statusLine

                        if let approval = session.pendingApproval, session.status == .waitingApproval {
                            pendingApprovalBanner(approval)
                        }

                        ForEach(session.recentMessages) { message in
                            messageRow(message)
                        }

                        if let artifact = session.artifactSummary {
                            artifactCard(artifact)
                        }

                        if let changes = session.changes, changes.totalFiles > 0 {
                            diffSummaryPill(changes)
                        }
                    }
                    .padding(.horizontal, WatchTheme.horizontalInset)
                    .padding(.bottom, 44)
                }
            }
            .background(WatchTheme.canvas.ignoresSafeArea())

            // Floating Voice Reply FAB (`#8DB8FF` bottom-right)
            WatchCircleChromeButton(
                systemName: "mic",
                foreground: WatchTheme.inkOnPeriwinkle,
                background: WatchTheme.accentPeriwinkle,
                diameter: 38,
                iconSize: 16,
                accessibilityId: "watch.chat.voiceFab"
            ) {
                store.openVoiceInput(for: session.cascadeId)
            }
            .padding(.trailing, 10)
            .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            store.advertiseHandoff(cascadeId: session.cascadeId, target: .chat)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            switch session.status {
            case .running:
                WatchRunningArcView(
                    size: 11.5,
                    lineWidth: 1.8,
                    isAnimated: !store.isVerificationMode
                )
            case .waitingApproval:
                WatchAmberHaloDot()
                    .scaleEffect(0.82)
            case .done:
                Circle()
                    .fill(WatchTheme.emerald)
                    .frame(width: 7, height: 7)
            case .error:
                Circle()
                    .fill(WatchTheme.coralRed)
                    .frame(width: 7, height: 7)
            case .idle:
                Circle()
                    .fill(WatchTheme.inkMuted)
                    .frame(width: 7, height: 7)
            }

            Text(session.chatHeaderStatusText)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(session.status == .waitingApproval ? WatchTheme.amber : WatchTheme.accentPeriwinkle)
                .lineLimit(1)
        }
        .padding(.horizontal, 3)
    }

    private func pendingApprovalBanner(_ approval: WatchPendingApproval) -> some View {
        Button {
            WatchHaptics.notification()
            store.activeApprovalSheet = approval
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WatchTheme.inkOnAmber)
                Text("Approve command")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(WatchTheme.inkOnAmber)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WatchTheme.inkOnAmber.opacity(0.75))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WatchTheme.amber)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watch.chat.pendingApprovalBanner")
    }

    @ViewBuilder
    private func messageRow(_ message: WatchChatBubbleItem) -> some View {
        if message.isUser {
            HStack {
                Spacer(minLength: 12)
                HStack(spacing: 5) {
                    if message.isVoiceInput {
                        Image(systemName: "mic")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WatchTheme.inkSecondary)
                    }
                    Text(message.text)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(WatchTheme.inkPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(WatchTheme.elevatedButton)
                )
            }
        } else {
            Text(message.text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(WatchTheme.inkPrimary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }

    private func artifactCard(_ artifact: WatchArtifactSummarySnapshot) -> some View {
        Button {
            WatchHaptics.click()
            store.navigationPath.append(.artifact(cascadeId: session.cascadeId))
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WatchTheme.iconTileBlue)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(WatchTheme.accentPeriwinkle)
                    )

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(artifact.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(WatchTheme.inkPrimary)
                        .lineLimit(1)
                    Text(artifact.pointsCountLabel)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(WatchTheme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(WatchTheme.inkMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WatchTheme.cardCornerRadius, style: .continuous)
                    .fill(WatchTheme.card)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watch.chat.artifactCard")
    }

    private func diffSummaryPill(_ changes: WatchChangesSnapshot) -> some View {
        Button {
            WatchHaptics.click()
            store.navigationPath.append(.changes(cascadeId: session.cascadeId))
        } label: {
            (
                Text("+\(changes.totalAdditions)")
                    .foregroundStyle(WatchTheme.emerald)
                + Text("  -\(changes.totalDeletions)")
                    .foregroundStyle(WatchTheme.coralRed)
                + Text(" · \(changes.totalFiles) \(changes.totalFiles == 1 ? "file" : "files")")
                    .foregroundStyle(WatchTheme.inkSecondary)
            )
            .font(.system(size: 12.5, weight: .regular))
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(WatchTheme.card)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watch.chat.diffPill")
    }
}
