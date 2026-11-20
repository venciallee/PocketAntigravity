import SwiftUI
import AntigravityData

/// Native Matte Obsidian / Liquid Glass Composer (`ChatComposerView`) pinned at the bottom of `UE07_CHAT_AND_COMPOSER`.
/// - Live Antigravity 2.x toolbar matches PC layout: `+`, `[<Active Model> ⌄]` -> `ModelAndModeSheetView`,
///   circular Permissions shield button (`composer-btn-permissions` -> `PermissionsSheetView`), `mic`, and `#8EB4FF` Send button.
/// - ESDD verification mode (`UE07`) preserves the `[Planning ⌄]` pill (`composer-pill-mode`) alongside `[Gemini 3.1 Pro ⌄]`.
public struct ChatComposerView: View {
    @Bindable public var store: AntigravitySessionStore
    @FocusState private var isInputFocused: Bool

    @State private var attachedChipLabels: [String]
    @State private var draftMessageText: String
    @State private var isShowingAddContextSheet: Bool = false
    @State private var isShowingModelAndModeSheet: Bool = false
    @State private var isShowingPermissionsSheet: Bool = false

    private static let periwinkle = Color(red: 0x8E / 255.0, green: 0xB4 / 255.0, blue: 0xFF / 255.0) // #8EB4FF
    private static let warmAmber = AntigravityTheme.statusWaiting // #EBB365
    private static let inkOnCTA = Color(red: 0x0A / 255.0, green: 0x0E / 255.0, blue: 0x17 / 255.0) // #0A0E17
    private static let composerCardBg = Color(red: 0x14 / 255.0, green: 0x15 / 255.0, blue: 0x19 / 255.0) // #141519
    private static let controlPillBg = Color(red: 0x20 / 255.0, green: 0x22 / 255.0, blue: 0x2A / 255.0)

    public init(store: AntigravitySessionStore) {
        self.store = store
        if !store.isVerificationMode || store.hasPairedBackend || store.isLiveBackendConnected {
            self._attachedChipLabels = State(initialValue: store.composerAttachments.map(\.label))
            self._draftMessageText = State(initialValue: store.composerDraftText)
        } else {
            self._attachedChipLabels = State(initialValue: ["@ratelimit.go"])
            self._draftMessageText = State(initialValue: "Use 1000/s instead — staging is smaller than prod.")
        }
    }

    private var isLiveAntigravity2Mode: Bool {
        !store.isVerificationMode || store.hasPairedBackend || store.isLiveBackendConnected
    }

    private var compactModelPillLabel: String {
        var name = store.selectedModelConfig.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(" (thinking)") {
            name = String(name.dropLast(" (thinking)".count))
        }
        let suffixReplacements: [(String, String)] = [
            (" (XHigh)", " · XHigh"),
            (" (X-High)", " · XHigh"),
            (" (Extra High)", " · XHigh"),
            (" (High)", " · High"),
            (" (Medium)", " · Med"),
            (" (Low)", " · Low")
        ]
        for (suffix, replacement) in suffixReplacements where name.lowercased().hasSuffix(suffix.lowercased()) {
            name = String(name.dropLast(suffix.count)) + replacement
            break
        }
        return name
    }

    private var permissionButtonForeground: Color {
        switch store.activePermissionPreset {
        case .turbo:
            return Self.warmAmber
        case .auto:
            return Self.periwinkle
        case .defaultPolicy, .requestReview:
            return AntigravityTheme.inkLabel
        }
    }

    private var permissionButtonBackground: Color {
        switch store.activePermissionPreset {
        case .turbo:
            return Self.warmAmber.opacity(0.14)
        case .auto:
            return Self.periwinkle.opacity(0.14)
        case .defaultPolicy, .requestReview:
            return Self.controlPillBg
        }
    }

    private var permissionButtonStroke: Color {
        switch store.activePermissionPreset {
        case .turbo:
            return Self.warmAmber.opacity(0.32)
        case .auto:
            return Self.periwinkle.opacity(0.32)
        case .defaultPolicy, .requestReview:
            return Color.white.opacity(0.06)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Context Chips Strip
            if !attachedChipLabels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedChipLabels, id: \.self) { label in
                            Button {
                                attachedChipLabels.removeAll { $0 == label }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(label)
                                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(AntigravityTheme.inkReading)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AntigravityTheme.inkSecondary)
                                }
                                .padding(.horizontal, 11)
                                .frame(height: 30)
                                .background(Self.controlPillBg)
                                .clipShape(Capsule())
                                .frame(minHeight: 36)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                label.contains("ratelimit")
                                    ? "composer-chip-ratelimit"
                                    : "composer-chip-\(label)"
                            )
                        }
                    }
                }
            }

            // Multi-line Draft Input
            TextField(
                "Reply to agent or @mention files...",
                text: $draftMessageText,
                axis: .vertical
            )
            .lineLimit(1...4)
            .font(.system(size: 15.5))
            .foregroundStyle(AntigravityTheme.inkReading)
            .focused($isInputFocused)
            .onSubmit {
                submitMessage()
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .accessibilityIdentifier("composer-text-input")

            // Bottom Toolbar: `+`, [Legacy Mode Pill in UE07], `<Active Model> ⌄`, `(🛡!)` Permissions, `mic`, `↑` Send
            HStack(spacing: 6) {
                // 1. Circular `+` Add Context Button
                Button {
                    isShowingAddContextSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .frame(width: 34, height: 34)
                        .background(Self.controlPillBg)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                        .clipShape(Circle())
                        .frame(width: 38, height: AntigravityTheme.minTouchTargetPt)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer-btn-add-context")

                // 2. Legacy `[Planning / Fast ⌄]` Mode Pill (ESDD UE07 verification mode only; Antigravity 2.x uses `/plan`)
                if !isLiveAntigravity2Mode {
                    Button {
                        isShowingModelAndModeSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: store.selectedModelConfig.mode == .planning ? "doc.text" : "bolt.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Self.periwinkle)
                            Text(store.selectedModelConfig.mode.rawValue)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkReading)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(Self.controlPillBg)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                        .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1)
                    .accessibilityIdentifier("composer-pill-mode")
                }

                // 3. `[<Active Model> ⌄]` Model Pill
                Button {
                    isShowingModelAndModeSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text(compactModelPillLabel)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.inkLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(Self.controlPillBg)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer-pill-model")

                Spacer(minLength: 0)

                // 4. Circular Permissions Button (`Remote Permissions` / `Permissions` matching Antigravity 2.x PC)
                if isLiveAntigravity2Mode {
                    Button {
                        isShowingPermissionsSheet = true
                    } label: {
                        Image(systemName: store.activePermissionPreset.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(permissionButtonForeground)
                            .frame(width: 34, height: 34)
                            .background(permissionButtonBackground)
                            .overlay(
                                Circle()
                                    .strokeBorder(permissionButtonStroke, lineWidth: 1)
                            )
                            .clipShape(Circle())
                            .frame(width: 38, height: AntigravityTheme.minTouchTargetPt)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Permissions: \(store.activePermissionPreset.displayTitle)")
                    .accessibilityIdentifier("composer-btn-permissions")
                }

                // 5. Voice Dictation Mic Button
                Button {
                    isInputFocused = true
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .frame(width: 34, height: AntigravityTheme.minTouchTargetPt)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer-btn-mic")

                // 6. Circular `#8EB4FF` Periwinkle Send Button
                Button {
                    submitMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(Self.inkOnCTA)
                        .frame(width: 34, height: 34)
                        .background(Self.periwinkle)
                        .clipShape(Circle())
                        .frame(width: 38, height: AntigravityTheme.minTouchTargetPt)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer-btn-send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Self.composerCardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            if !store.composerDraftText.isEmpty {
                draftMessageText = store.composerDraftText
            }
        }
        .sheet(isPresented: $isShowingAddContextSheet) {
            AddContextSheetView(
                store: store,
                onAddLabels: { added in
                    for item in added where !attachedChipLabels.contains(item) {
                        attachedChipLabels.append(item)
                    }
                },
                onDismiss: {
                    isShowingAddContextSheet = false
                }
            )
        }
        .sheet(isPresented: $isShowingModelAndModeSheet) {
            ModelAndModeSheetView(
                store: store,
                isPresentedAsNativeSheet: true,
                onDismiss: {
                    isShowingModelAndModeSheet = false
                }
            )
            .presentationDetents([.fraction(0.78), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(ModelAndModeSheetView.sheetSurfaceColor)
        }
        .sheet(isPresented: $isShowingPermissionsSheet) {
            PermissionsSheetView(
                store: store,
                onDismiss: {
                    isShowingPermissionsSheet = false
                }
            )
            .presentationDetents([.height(store.isActiveSessionCloud ? 356 : 428), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(PermissionsSheetView.sheetSurfaceColor)
        }
    }

    private func submitMessage() {
        let trimmed = draftMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachedChipLabels.isEmpty else { return }
        store.composerAttachments = attachedChipLabels.map { label in
            let cleanFile = label.replacingOccurrences(of: "@", with: "")
            let targetUri: String
            if store.selectedWorkspaceUri.hasPrefix("cloud://") || store.selectedWorkspaceUri.isEmpty {
                targetUri = store.isVerificationMode
                    ? "file:///Users/wl/code/ledger-svc/\(cleanFile)"
                    : "antigravity://file/\(cleanFile)"
            } else {
                let rawPath = store.selectedWorkspaceUri
                    .replacingOccurrences(of: "file://", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                targetUri = "file:///\(rawPath)/\(cleanFile)"
            }
            return ComposerAttachmentChip(
                kind: .fileMention,
                label: label,
                targetUri: targetUri
            )
        }
        store.composerDraftText = trimmed
        store.sendCurrentDraft()
        draftMessageText = ""
        attachedChipLabels.removeAll()
    }
}
