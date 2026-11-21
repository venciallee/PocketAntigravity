import Foundation
import AntigravityData
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Manages iOS local notifications for Antigravity waiting approvals, run completions, and errors
/// while respecting `AppAppearancePreferences` and suppressing user-initiated stop notifications.
@MainActor
public final class NotificationCoordinator {
    public static let shared = NotificationCoordinator()

    private var deliveredEventIds: Set<String> = []

    private init() {}

    public func requestAuthorizationIfNeeded(preferences: AppAppearancePreferences) {
        guard preferences.notificationsEnabled else { return }
        #if canImport(UserNotifications) && os(iOS)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        #endif
    }

    public func deliverIfNeeded(event: (id: String, title: String, body: String, cascadeId: String)?) {
        guard let event, !deliveredEventIds.contains(event.id) else { return }
        deliveredEventIds.insert(event.id)

        #if canImport(UserNotifications) && os(iOS)
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        content.userInfo = ["cascadeId": event.cascadeId]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
        #endif
    }
}
