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
                .padding(.horizontal, 10)
                .padding(.top, 6)

                Text("Devices")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(WatchTheme.inkPrimary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 8)

                VStack(spacing: 7) {
                    ForEach(store.snapshot.devices) { device in
                        deviceCard(device)
                    }
                }
                .padding(.horizontal, WatchTheme.horizontalInset)
                .padding(.bottom, 12)
            }
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
            HStack(spacing: 10) {
                Image(systemName: device.kind.sfSymbolName)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(device.isOnline ? WatchTheme.inkPrimary : WatchTheme.inkMuted)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(device.isOnline ? WatchTheme.inkPrimary : WatchTheme.inkSecondary)
                        .lineLimit(1)

                    Text(device.subtitleText)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(device.isOnline ? WatchTheme.emerald : WatchTheme.inkMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if device.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WatchTheme.accentPeriwinkle)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
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
