import SwiftUI
import AntigravityData

/// Screen `W02_DEVICES`: Watch · 在线设备 (`Devices` host/cloud selector with online counts & offline timestamps).
public struct WatchDevicesView: View {
    @Bindable public var store: WatchAppStore
    public var onBack: () -> Void

    public init(store: WatchAppStore, onBack: @escaping () -> Void) {
        self.store = store
        self.onBack = onBack
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    WatchCircleChromeButton(
                        systemName: "chevron.left",
                        accessibilityId: "watch.devices.back",
                        action: onBack
                    )
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, WatchTheme.topSafeInsetCompact)

                Text("Devices")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WatchTheme.inkPrimary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                VStack(spacing: 5) {
                    ForEach(store.snapshot.devices) { device in
                        deviceCard(device)
                    }
                }
                .padding(.horizontal, WatchTheme.horizontalInset)
                .padding(.bottom, 16)
            }
        }
        .contentMargins(.vertical, 0, for: .scrollContent)
        .background(WatchTheme.canvas.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .automatic)
    }

    private func deviceCard(_ device: WatchDeviceSnapshot) -> some View {
        let cardFill: Color = {
            if device.isSelected {
                return WatchTheme.cardSelectedDevice
            }
            return device.isOnline ? WatchTheme.card : WatchTheme.cardOffline
        }()

        return Button {
            WatchHaptics.click()
            store.selectDevice(device)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: device.kind.sfSymbolName)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(device.isOnline ? WatchTheme.inkPrimary : WatchTheme.inkMuted)
                    .frame(width: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(device.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(device.isOnline ? WatchTheme.inkPrimary : WatchTheme.inkSecondary)
                        .lineLimit(1)

                    Text(device.subtitleText)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(device.isOnline ? WatchTheme.emerald : WatchTheme.inkMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                if device.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WatchTheme.accentPeriwinkle)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WatchTheme.cardCornerRadius, style: .continuous)
                    .fill(cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WatchTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        device.isSelected ? WatchTheme.accentPeriwinkle : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watch.devices.row.\(device.id)")
    }
}
