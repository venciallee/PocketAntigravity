import SwiftUI
import AntigravityData

/// Lightweight session Permissions sheet presented when triggered via `store.presentedSheet = .customizationsSettings`
/// (e.g. from the chat overflow menu). Global Appearance, Default Permissions, and Notification preferences live
/// directly on 1st-level Settings (`RemotePairingViewController`) with zero nested Desktop-style sub-menus.
public struct CustomizationsSettingsView: View {
    @Bindable private var store: AntigravitySessionStore
    @Environment(\.dismiss) private var dismiss

    public init(store: AntigravitySessionStore) {
        self.store = store
    }

    public var body: some View {
        PermissionsSheetView(
            store: store,
            onDismiss: {
                store.presentedSheet = nil
                dismiss()
            }
        )
        .presentationDetents([.height(store.isActiveSessionCloud ? 356 : 428), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(PermissionsSheetView.sheetSurfaceColor)
        .accessibilityIdentifier("sheet_permissions_quick")
    }
}
