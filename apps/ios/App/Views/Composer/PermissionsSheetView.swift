import SwiftUI
import AntigravityData

/// Reusable Antigravity 2.x Local & Remote Permissions preset card (`Request Review`, `Default`, `Auto`, `Turbo`).
/// Mirrors Antigravity Desktop's `Remote Permissions` / `Permissions` selector in Matte Obsidian + Liquid Glass.
public struct PermissionsPresetListCard: View {
    @Bindable public var store: AntigravitySessionStore
    public var isRemoteOverride: Bool?
    public var accessibilityIdPrefix: String
    public var footerTextOverride: String?
    public var onSelectPreset: ((AgentPermissionPreset) -> Void)?

    public init(
        store: AntigravitySessionStore,
        isRemoteOverride: Bool? = nil,
        accessibilityIdPrefix: String = "permission-row",
        footerTextOverride: String? = nil,
        onSelectPreset: ((AgentPermissionPreset) -> Void)? = nil
    ) {
        self.store = store
        self.isRemoteOverride = isRemoteOverride
        self.accessibilityIdPrefix = accessibilityIdPrefix
        self.footerTextOverride = footerTextOverride
        self.onSelectPreset = onSelectPreset
    }

    private var isRemote: Bool {
        isRemoteOverride ?? store.isActiveSessionCloud
    }

    private var selectedPreset: AgentPermissionPreset {
        isRemote ? store.remotePermissionPreset : store.localPermissionPreset
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
                            .overlay(AntigravityTheme.subtleDivider)
                            .padding(.leading, 56)
                    }
                }
            }
            .background(AntigravityTheme.surfaceSheetGroup)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )

            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.top, 1.5)
                Text(
                    footerTextOverride ?? (
                        isRemote
                            ? "Remote sessions default to Turbo inside an isolated Cloud VM."
                            : "Controls terminal commands and tool approvals on the next turn."
                    )
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
        let isSelected = (selectedPreset == preset)
        let isDefault = preset == defaultPreset
        let accentColor: Color = (preset == .turbo) ? AntigravityTheme.statusWaiting : AntigravityTheme.accentPeriwinkle

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                store.setActivePermissionPreset(preset, isRemoteOverride: isRemote)
            }
            onSelectPreset?(preset)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? accentColor.opacity(0.16) : AntigravityTheme.surfaceSubtleBox)
                        .frame(width: 30, height: 30)
                    Image(systemName: preset.semanticIcon.sfSymbolName)
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
                            .background(AntigravityTheme.inkSecondary.opacity(0.14))
                            .clipShape(Capsule())
                        }
                    }

                    Text(preset.summaryDescription)
                        .font(.system(size: 12.5))
                        .foregroundStyle(isSelected ? AntigravityTheme.inkLabel : AntigravityTheme.inkSecondary)
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
        .accessibilityIdentifier("\(accessibilityIdPrefix)-\(preset.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityValue(isSelected ? "selected" : "unselected")
    }
}

/// Compact native iOS sheet for selecting `Remote Permissions` / `Permissions` directly from the composer shield button.
public struct PermissionsSheetView: View {
    @Bindable public var store: AntigravitySessionStore
    public var onDismiss: (() -> Void)?

    public static let sheetSurfaceColor = AntigravityTheme.surfaceSheet

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
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(AntigravityTheme.accentPeriwinkle.opacity(0.14))
                            .overlay(
                                Capsule()
                                    .strokeBorder(AntigravityTheme.accentPeriwinkle.opacity(0.28), lineWidth: 1)
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
                .overlay(AntigravityTheme.subtleDivider)

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
