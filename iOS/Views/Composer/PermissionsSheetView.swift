import SwiftUI
import AntigravityData

/// Reusable Antigravity 2.x Local & Remote Permissions preset card (`Request Review`, `Default`, `Auto`, `Turbo`).
/// Mirrors Antigravity Desktop's `Remote Permissions` / `Permissions` selector in Matte Obsidian + Liquid Glass.
public struct PermissionsPresetListCard: View {
    @Bindable public var store: AntigravitySessionStore
    public var onSelectPreset: ((AgentPermissionPreset) -> Void)?

    private static let periwinkle = AntigravityTheme.accentPeriwinkle // #8EB4FF
    private static let warmAmber = AntigravityTheme.statusWaiting // #EBB365
    private static let cardSurface = Color(red: 0x1B / 255.0, green: 0x1D / 255.0, blue: 0x24 / 255.0)
    private static let selectedSubtitleColor = Color(red: 0xB0 / 255.0, green: 0xB8 / 255.0, blue: 0xC8 / 255.0)

    public init(
        store: AntigravitySessionStore,
        onSelectPreset: ((AgentPermissionPreset) -> Void)? = nil
    ) {
        self.store = store
        self.onSelectPreset = onSelectPreset
    }

    private var isRemote: Bool {
        store.isActiveSessionCloud
    }

    private var presets: [AgentPermissionPreset] {
        AgentPermissionPreset.availablePresets(isRemote: isRemote)
    }

    private var defaultPreset: AgentPermissionPreset {
        AgentPermissionPreset.defaultPreset(isRemote: isRemote)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                ForEach(Array(presets.enumerated()), id: \.element.id) { idx, preset in
                    presetRow(preset)
                    if idx < presets.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.06))
                            .padding(.leading, 56)
                    }
                }
            }
            .background(Self.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )

            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11.5, weight: .medium))
                Text(
                    isRemote
                        ? "Remote sessions default to Turbo inside an isolated Cloud VM."
                        : "Controls terminal commands and tool approvals on the next turn."
                )
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(AntigravityTheme.inkMuted)
            .padding(.leading, 4)
            .padding(.top, 2)
        }
    }

    private func presetRow(_ preset: AgentPermissionPreset) -> some View {
        let isSelected = store.activePermissionPreset == preset
        let isDefault = preset == defaultPreset
        let accentColor: Color = (preset == .turbo) ? Self.warmAmber : Self.periwinkle

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                store.setActivePermissionPreset(preset)
            }
            onSelectPreset?(preset)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? accentColor.opacity(0.18) : Color.white.opacity(0.06))
                        .frame(width: 30, height: 30)
                    Image(systemName: preset.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? accentColor : AntigravityTheme.inkSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(preset.displayTitle)
                            .font(.system(size: 15.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .lineLimit(1)

                        if isDefault && preset != .defaultPolicy {
                            HStack(spacing: 3) {
                                Text("Default")
                                Image(systemName: "info.circle")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }

                    Text(preset.summaryDescription)
                        .font(.system(size: 12.5))
                        .foregroundStyle(isSelected ? Self.selectedSubtitleColor : AntigravityTheme.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(isSelected ? accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("permission-row-\(preset.rawValue)")
    }
}

/// Compact native iOS sheet for selecting `Remote Permissions` / `Permissions` directly from the composer shield button.
public struct PermissionsSheetView: View {
    @Bindable public var store: AntigravitySessionStore
    public var onDismiss: (() -> Void)?

    public static let sheetSurfaceColor = Color(red: 0x13 / 255.0, green: 0x14 / 255.0, blue: 0x1A / 255.0)
    private static let periwinkle = AntigravityTheme.accentPeriwinkle

    public init(
        store: AntigravitySessionStore,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.onDismiss = onDismiss
    }

    private var headerTitle: String {
        store.isActiveSessionCloud ? "Remote Permissions" : "Permissions"
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(headerTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)

                HStack {
                    Spacer()
                    Button {
                        onDismiss?()
                    } label: {
                        Text("Done")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Self.periwinkle)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Self.periwinkle.opacity(0.14))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Self.periwinkle.opacity(0.28), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                            .frame(
                                minWidth: AntigravityTheme.minTouchTargetPt,
                                minHeight: AntigravityTheme.minTouchTargetPt,
                                alignment: .trailing
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-permissions-done")
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()
                .overlay(Color.white.opacity(0.06))

            ScrollView(.vertical, showsIndicators: false) {
                PermissionsPresetListCard(store: store)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Self.sheetSurfaceColor.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: store.activePermissionPreset)
    }
}
