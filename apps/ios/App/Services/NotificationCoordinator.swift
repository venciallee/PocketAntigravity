import Foundation
import AntigravityData
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Manages iOS & mirrored Apple Watch notifications for waiting approvals (`W08`), run completions, and errors
/// while respecting `AppAppearancePreferences` and routing Watch/iOS quick actions (`Allow`, `Deny`, `Reply by voice`)
/// directly back into `AntigravitySessionStore`.
@MainActor
public final class NotificationCoordinator: NSObject {
    public static let shared = NotificationCoordinator()

    private var deliveredEventIds: Set<String> = []
    private weak var attachedStore: AntigravitySessionStore?
    private var categoriesRegistered: Bool = false

    private override init() {
        super.init()
    }

    public func attach(store: AntigravitySessionStore) {
        self.attachedStore = store
        registerApprovalCategoryIfNeeded()
    }

    public func registerApprovalCategoryIfNeeded() {
        guard !categoriesRegistered else { return }
        categoriesRegistered = true
        #if canImport(UserNotifications) && os(iOS)
        let allowAction = UNNotificationAction(
            identifier: WatchConnectivityCodec.allowActionIdentifier,
            title: "Allow",
            options: [.authenticationRequired]
        )
        let denyAction = UNNotificationAction(
            identifier: WatchConnectivityCodec.denyActionIdentifier,
            title: "Deny",
            options: [.destructive]
        )
        let replyVoiceAction = UNTextInputNotificationAction(
            identifier: WatchConnectivityCodec.replyVoiceActionIdentifier,
            title: "Reply by voice",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Speak instruction…"
        )
        let approvalCategory = UNNotificationCategory(
            identifier: WatchConnectivityCodec.approvalNotificationCategory,
            actions: [allowAction, denyAction, replyVoiceAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([approvalCategory])
        #endif
    }

    public func requestAuthorizationIfNeeded(preferences: AppAppearancePreferences) {
        guard preferences.notificationsEnabled else { return }
        registerApprovalCategoryIfNeeded()
        #if canImport(UserNotifications) && os(iOS)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        #endif
    }

    public func deliverIfNeeded(
        event: (id: String, title: String, body: String, cascadeId: String)?,
        store: AntigravitySessionStore? = nil
    ) {
        guard let event, !deliveredEventIds.contains(event.id) else { return }
        deliveredEventIds.insert(event.id)
        registerApprovalCategoryIfNeeded()

        #if canImport(UserNotifications) && os(iOS)
        let activeStore = store ?? attachedStore
        let summary = activeStore?.summaries.first(where: { $0.cascadeId == event.cascadeId })
        let waitingStep = activeStore?.stepsByCascadeId[event.cascadeId]?.last(where: {
            $0.status == .waiting || $0.status == .blocked
        })
        let isApproval = (summary?.status == .waiting || summary?.status == .blocked)
            || event.title.localizedCaseInsensitiveContains("approv")
            || event.title.localizedCaseInsensitiveContains("command")

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default

        var info: [String: Any] = ["cascadeId": event.cascadeId]
        if isApproval {
            content.categoryIdentifier = WatchConnectivityCodec.approvalNotificationCategory
            info["cascadeTitle"] = summary?.title ?? "Agent task"
            info["stepIndex"] = waitingStep?.stepIndex ?? max(1, summary?.currentStepIndex ?? 1)
            info["totalSteps"] = max(summary?.totalSteps ?? 1, waitingStep?.stepIndex ?? 1)
            info["promptTitle"] = "Run this command?"
            info["commandLine"] = waitingStep?.runCommand?.proposedCommandLine
                ?? waitingStep?.runCommand?.commandLine
                ?? event.body
        }
        content.userInfo = info

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
        #endif
    }

    fileprivate func handleNotificationAction(
        actionIdentifier: String,
        cascadeId: String,
        stepIndex: Int?,
        userText: String?
    ) {
        guard let store = attachedStore else { return }
        if !cascadeId.isEmpty, store.activeCascadeId != cascadeId {
            store.selectCascade(cascadeId)
        }
        switch actionIdentifier {
        case WatchConnectivityCodec.allowActionIdentifier:
            store.approveWaitingCommandWithFaceID(stepIndex: stepIndex)
        case WatchConnectivityCodec.denyActionIdentifier:
            store.denyWaitingCommand(stepIndex: stepIndex)
        case WatchConnectivityCodec.replyVoiceActionIdentifier:
            if let text = userText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                store.composerDraftText = text
                store.sendCurrentDraft()
            }
        case UNNotificationDefaultActionIdentifier:
            if !cascadeId.isEmpty {
                store.activeRoute = .cascadeChat(cascadeId)
            }
        default:
            break
        }
        WatchConnectivityBridge.shared.sync(with: store, immediate: true)
    }
}

#if canImport(UserNotifications) && os(iOS)
extension NotificationCoordinator: UNUserNotificationCenterDelegate {
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionId = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let cascadeId = (userInfo["cascadeId"] as? String) ?? ""
        let stepIndex = userInfo["stepIndex"] as? Int
        let userText = (response as? UNTextInputNotificationResponse)?.userText
        Task { @MainActor in
            NotificationCoordinator.shared.handleNotificationAction(
                actionIdentifier: actionId,
                cascadeId: cascadeId,
                stepIndex: stepIndex,
                userText: userText
            )
        }
        completionHandler()
    }
}
#endif
