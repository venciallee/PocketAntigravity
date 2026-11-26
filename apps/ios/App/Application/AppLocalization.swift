import SwiftUI
import AntigravityData

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .english
}

public extension EnvironmentValues {
    /// Active in-app UI language propagated from `AntigravitySessionStore.appearancePreferences.language`
    /// so every SwiftUI view, sheet, and popover updates immediately without restarting the app.
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}
