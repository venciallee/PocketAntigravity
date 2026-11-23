import SwiftUI
import AntigravityData

@main
public struct AGPocketWatchApp: App {
    @State private var store = WatchAppStore()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            WatchRootContainerView(store: store)
                .preferredColorScheme(.dark)
        }

        #if os(watchOS)
        WKNotificationScene(
            controller: WatchApprovalNotificationController.self,
            category: WatchConnectivityCodec.approvalNotificationCategory
        )
        #endif
    }
}

/// Root navigation & sheet router hosting all 8 Apple Watch companion screens (`W01`..`W08`).
public struct WatchRootContainerView: View {
    @Bindable public var store: WatchAppStore

    public init(store: WatchAppStore) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if let approval = store.activeApprovalSheet {
                WatchApprovalNotificationView(
                    approval: approval,
                    onAllow: { store.approveCommand(approval) },
                    onDeny: { store.denyCommand(approval) },
                    onReplyByVoice: { store.replyByVoice(for: approval) }
                )
            } else if store.isVoiceSheetPresented {
                WatchVoiceInputView(store: store) {
                    store.isVoiceSheetPresented = false
                }
            } else {
                NavigationStack(path: $store.navigationPath) {
                    WatchSessionsListView(store: store)
                        .navigationDestination(for: WatchNavigationDestination.self) { destination in
                            switch destination {
                            case .devices:
                                WatchDevicesView(store: store) {
                                    popNavigation()
                                }
                            case .chat(let cascadeId):
                                WatchChatStreamView(store: store, cascadeId: cascadeId) {
                                    popNavigation()
                                }
                            case .artifact(let cascadeId):
                                WatchArtifactSummaryView(store: store, cascadeId: cascadeId) {
                                    popNavigation()
                                }
                            case .changes(let cascadeId):
                                WatchChangedFilesView(store: store, cascadeId: cascadeId) {
                                    popNavigation()
                                }
                            }
                        }
                }
            }

            if let toast = store.statusToastMessage {
                Text(toast)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(WatchTheme.inkPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(WatchTheme.elevatedButton.opacity(0.95))
                    )
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: store.statusToastMessage)
    }

    private func popNavigation() {
        if !store.navigationPath.isEmpty {
            store.navigationPath.removeLast()
        }
    }
}
