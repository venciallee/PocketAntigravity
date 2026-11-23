import SwiftUI
import AntigravityData
#if os(watchOS)
import UserNotifications
import WatchKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
#endif

/// Screen `W08_APPROVAL_NOTIFICATION`: Watch · 通知（待批准）
/// Used both as the in-app pending command approval sheet and as the watchOS custom Long-Look Notification view.
public struct WatchApprovalNotificationView: View {
    public let approval: WatchPendingApproval
    public var onAllow: () -> Void
    public var onDeny: () -> Void
    public var onReplyByVoice: () -> Void

    public init(
        approval: WatchPendingApproval,
        onAllow: @escaping () -> Void,
        onDeny: @escaping () -> Void,
        onReplyByVoice: @escaping () -> Void
    ) {
        self.approval = approval
        self.onAllow = onAllow
        self.onDeny = onDeny
        self.onReplyByVoice = onReplyByVoice
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    WatchBrandGlyphView()
                    Text("Agents · \(approval.relativeTimeLabel)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(WatchTheme.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)

                Text(approval.promptTitle)
                    .font(.system(size: 16.5, weight: .bold))
                    .foregroundStyle(WatchTheme.amber)
                    .padding(.top, 8)
                    .accessibilityIdentifier("watch.approval.title")

                Text(approval.contextSubtitle)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(WatchTheme.inkSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)

                Text(approval.commandLine)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(WatchTheme.inkBody)
                    .lineSpacing(1.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(WatchTheme.card)
                    )
                    .padding(.top, 7)
                    .accessibilityIdentifier("watch.approval.command")

                VStack(spacing: 7) {
                    Button {
                        onAllow()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Allow")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(WatchTheme.inkOnAmber)
                        .frame(maxWidth: .infinity)
                        .frame(height: 39)
                        .background(Capsule().fill(WatchTheme.amber))
                    }
                    .buttonStyle(.plain)
                    .watchPrimaryDoubleTap()
                    .accessibilityIdentifier("watch.approval.allow")

                    Button {
                        onDeny()
                    } label: {
                        Text("Deny")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WatchTheme.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 39)
                            .background(Capsule().fill(WatchTheme.elevatedButton))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watch.approval.deny")

                    Button {
                        onReplyByVoice()
                    } label: {
                        Text("Reply by voice")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WatchTheme.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 39)
                            .background(Capsule().fill(WatchTheme.elevatedButton))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watch.approval.replyByVoice")
                }
                .padding(.top, 9)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 12)
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

#if os(watchOS)
/// watchOS custom Long-Look Notification controller for `AGPOCKET_APPROVAL_REQUEST`.
public final class WatchApprovalNotificationController: WKUserNotificationHostingController<WatchApprovalNotificationView> {
    public override class var isInteractive: Bool { true }

    private var approval: WatchPendingApproval = WatchVerificationFixtures.makePendingApproval()

    public override var body: WatchApprovalNotificationView {
        WatchApprovalNotificationView(
            approval: approval,
            onAllow: { [approval] in
                WatchHaptics.success()
                Self.dispatchNotificationCommand(
                    WatchRemoteCommand(
                        kind: .approveCommand,
                        cascadeId: approval.cascadeId,
                        stepIndex: approval.stepIndex
                    )
                )
            },
            onDeny: { [approval] in
                WatchHaptics.click()
                Self.dispatchNotificationCommand(
                    WatchRemoteCommand(
                        kind: .denyCommand,
                        cascadeId: approval.cascadeId,
                        stepIndex: approval.stepIndex
                    )
                )
            },
            onReplyByVoice: {
                WatchHaptics.click()
            }
        )
    }

    public override func didReceive(_ notification: UNNotification) {
        let userInfo = notification.request.content.userInfo
        if let parsed = WatchConnectivityCodec.pendingApproval(fromNotificationUserInfo: userInfo) {
            self.approval = parsed
        }
    }

    private static func dispatchNotificationCommand(_ command: WatchRemoteCommand) {
        #if canImport(WatchConnectivity)
        if WCSession.isSupported() {
            let session = WCSession.default
            if session.activationState != .activated {
                session.activate()
            }
            if let data = WatchConnectivityCodec.encodeCommand(command) {
                let payload: [String: Any] = [WatchConnectivityCodec.commandKey: data]
                if session.isReachable {
                    session.sendMessage(payload, replyHandler: nil) { _ in
                        WCSession.default.transferUserInfo([WatchConnectivityCodec.commandKey: data])
                    }
                } else {
                    session.transferUserInfo(payload)
                }
            }
        }
        #endif
    }
}
#endif
