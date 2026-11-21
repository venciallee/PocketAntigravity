import SwiftUI
import UniformTypeIdentifiers
import AntigravityData

/// Native Matte Obsidian / Liquid Glass Composer (`ChatComposerView`) pinned at the bottom of `UE07_CHAT_AND_COMPOSER`.
/// Features:
/// - Removable context chips (`composer-chip-ratelimit`), multi-line `TextField`, `/` slash popup, typo-tolerant `@` mention popup, Queued Messages strip
/// - Live Antigravity 2.x toolbar matches PC layout: `+`, `[<Active Model> ⌄]` -> `ModelAndModeSheetView`,
///   circular Permissions shield button (`composer-btn-permissions` -> `PermissionsSheetView`), real `SFSpeechRecognizer` `mic`, and `#8EB4FF` Send button.
/// - ESDD verification mode (`UE07`) preserves the `[Planning ⌄]` pill (`composer-pill-mode`) alongside `[Gemini 3.1 Pro ⌄]`.
public struct ChatComposerView: View {
    @Bindable public var store: AntigravitySessionStore
    @FocusState private var isInputFocused: Bool

    @State private var attachedChipLabels: [String]
    @State private var draftMessageText: String
    @State private var isShowingAddContextSheet: Bool = false
    @State private var isShowingModelAndModeSheet: Bool = false
    @State private var isShowingPermissionsSheet: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var voiceManager = VoiceInputManager()

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

    private var activeMentionQuery: String? {
        guard !store.isVerificationMode else { return nil }
        guard let lastToken = draftMessageText.split(whereSeparator: \.isWhitespace).last,
              lastToken.hasPrefix("@"),
              lastToken.count >= 2 else {
            return nil
        }
        return String(lastToken.dropFirst())
    }

    private var activeSlashCommands: [SlashCommandItem] {
        guard !store.isVerificationMode, !store.isSlashPopupDismissedManually else { return [] }
        return store.filteredSlashCommands(for: draftMessageText)
    }

    private var activeQueuedMessages: [QueuedMessageItem] {
        store.queuedMessages.filter { $0.cascadeId == store.activeCascadeId }
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
            return AntigravityTheme.statusWaiting
        case .auto:
            return AntigravityTheme.accentPeriwinkle
        case .defaultPolicy, .requestReview, .inheritGlobal:
            return AntigravityTheme.inkLabel
        }
    }

    private var permissionButtonBackground: Color {
        switch store.activePermissionPreset {
        case .turbo:
            return AntigravityTheme.statusWaiting.opacity(0.14)
        case .auto:
            return AntigravityTheme.accentPeriwinkle.opacity(0.14)
        case .defaultPolicy, .requestReview, .inheritGlobal:
            return AntigravityTheme.surfaceElevated
        }
    }

    private var permissionButtonStroke: Color {
        switch store.activePermissionPreset {
        case .turbo:
            return AntigravityTheme.statusWaiting.opacity(0.32)
        case .auto:
            return AntigravityTheme.accentPeriwinkle.opacity(0.32)
        case .defaultPolicy, .requestReview, .inheritGlobal:
            return AntigravityTheme.cardBorder
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Live-mode Slash Command Popup (`/plan`, `/btw`, `/swarm`, `/run-workflow`, etc.)
            if !activeSlashCommands.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(activeSlashCommands.prefix(6)) { cmd in
                            Button {
                                draftMessageText = "\(cmd.command) "
                                store.isSlashPopupDismissedManually = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: cmd.icon.sfSymbolName)
                                        .font(.system(size: 13))
                                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(cmd.command)
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .foregroundStyle(AntigravityTheme.inkReading)
                                        Text(cmd.summary)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(AntigravityTheme.inkSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(AntigravityTheme.surfaceSubtleBox, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .padding(6)
                .background(AntigravityTheme.surfacePopover, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                )
                .accessibilityIdentifier("composer-slash-popup")
            }

            // Live-mode Typo-Tolerant @Mention Autocomplete Popup
            if let mentionQuery = activeMentionQuery {
                let matches = store.filteredMentionCandidates(for: mentionQuery)
                if !matches.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(matches.prefix(5)) { candidate in
                                Button {
                                    let chipLabel = "@\(candidate.title)"
                                    if !attachedChipLabels.contains(chipLabel) {
                                        attachedChipLabels.append(chipLabel)
                                    }
                                    if let range = draftMessageText.range(of: "@[^\\s]*$", options: .regularExpression) {
                                        draftMessageText.removeSubrange(range)
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 11))
                                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                        Text("@\(candidate.title)")
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(AntigravityTheme.inkReading)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(AntigravityTheme.surfacePill, in: Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .accessibilityIdentifier("composer-mention-popup")
                }
            }

            // Queued Follow-Up Messages Strip (when messages were queued mid-stream)
            if !store.isVerificationMode && !activeQueuedMessages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(activeQueuedMessages) { queued in
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                                .foregroundStyle(AntigravityTheme.statusWaiting)
                            Text("Queued: \(queued.text)")
                                .font(.system(size: 12))
                                .foregroundStyle(AntigravityTheme.inkLabel)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                store.removeQueuedMessage(id: queued.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AntigravityTheme.inkMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AntigravityTheme.surfaceSubtleBox, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                        )
                    }
                }
            }

            // Live-mode Quick Controls Strip (Permission Preset + /btw + Voice Mode + Attach File)
            if !store.isVerificationMode {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(AgentPermissionPreset.allCases) { preset in
                                Button {
                                    store.setConversationPermissionPreset(preset)
                                } label: {
                                    Text(preset.rawValue)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.system(size: 10.5))
                                Text(store.effectivePermissionPreset().rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AntigravityTheme.surfacePill, in: Capsule())
                        }
                        .accessibilityIdentifier("composer-permission-preset")

                        Button {
                            store.openSideQuestion()
                        } label: {
                            Label("/btw", systemImage: "questionmark.bubble")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AntigravityTheme.accentPeriwinkle.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("composer-btn-btw")

                        Button {
                            store.startVoiceMode()
                        } label: {
                            Label("Voice", systemImage: "waveform")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkLabel)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AntigravityTheme.surfacePill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("composer-btn-voice-mode")

                        Button {
                            isShowingFileImporter = true
                        } label: {
                            Label("Attach", systemImage: "paperclip")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkLabel)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AntigravityTheme.surfacePill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("composer-btn-attach-file")
                    }
                }
            }

            // Context Chips Strip
            if !attachedChipLabels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedChipLabels, id: \.self) { label in
                            Button {
                                attachedChipLabels.removeAll { $0 == label }
                                store.composerAttachments.removeAll { $0.label == label }
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
                                .background(AntigravityTheme.surfacePill)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                                )
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

            // Workflow Command Pill (e.g. `⏱ automation` from Automations "Create with Prompt")
            if let rawWorkflow = store.composerWorkflowCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawWorkflow.isEmpty {
                let workflowName = rawWorkflow.hasPrefix("/") ? String(rawWorkflow.dropFirst()) : rawWorkflow
                let workflowIcon = workflowName.lowercased() == "automation" ? "clock" : "sparkles"
                HStack(spacing: 6) {
                    Button {
                        store.composerWorkflowCommand = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: workflowIcon)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                            Text(workflowName)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkReading)
                            Image(systemName: "xmark")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(AntigravityTheme.surfacePill)
                        .overlay(
                            Capsule()
                                .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Workflow \(workflowName). Tap to remove.")
                    .accessibilityIdentifier("composer-workflow-chip")

                    Spacer(minLength: 0)
                }
            }

            if let voiceErr = voiceManager.errorMessage {
                Text(voiceErr)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AntigravityTheme.statusWaiting)
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
            .onChange(of: draftMessageText) { _, newValue in
                if !newValue.hasPrefix("/") {
                    store.isSlashPopupDismissedManually = false
                }
            }
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
                        .background(AntigravityTheme.surfaceElevated)
                        .overlay(
                            Circle()
                                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
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
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
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
                        .background(AntigravityTheme.surfaceElevated)
                        .overlay(
                            Capsule()
                                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
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
                    .background(AntigravityTheme.surfaceElevated)
                    .overlay(
                        Capsule()
                            .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
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
                        Image(systemName: store.activePermissionPreset.semanticIcon.sfSymbolName)
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

                // 5. Real Live Speech-to-Text Mic Button (`SFSpeechRecognizer` + `AVAudioEngine`)
                Button {
                    if store.isVerificationMode {
                        isInputFocused = true
                    } else {
                        voiceManager.toggleRecording { transcript in
                            draftMessageText = transcript
                        }
                    }
                } label: {
                    Image(systemName: voiceManager.isRecording ? "waveform.circle.fill" : "mic")
                        .font(.system(size: voiceManager.isRecording ? 19 : 15.5, weight: .medium))
                        .foregroundStyle(voiceManager.isRecording ? AntigravityTheme.statusError : AntigravityTheme.inkSecondary)
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
                        .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                        .frame(width: 34, height: 34)
                        .background(AntigravityTheme.accentPeriwinkle)
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
        .background(AntigravityTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            if !store.composerDraftText.isEmpty {
                draftMessageText = store.composerDraftText
            }
        }
        .onChange(of: store.composerDraftText) { _, newValue in
            if draftMessageText != newValue {
                draftMessageText = newValue
            }
        }
        .onChange(of: store.composerAttachments.count) { _, _ in
            guard !store.isVerificationMode else { return }
            attachedChipLabels = store.composerAttachments.map(\.label)
        }
        .onDisappear {
            voiceManager.stopRecording()
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item, .pdf, .image, .audio, .movie, .zip],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    let name = url.lastPathComponent
                    let ext = url.pathExtension.lowercased()
                    let kind: ComposerAttachmentChip.Kind = {
                        if ext == "pdf" { return .pdfDocument }
                        if ext == "zip" { return .archiveZip }
                        if ["png", "jpg", "jpeg", "webp", "heic"].contains(ext) { return .imageScreenshot }
                        if ["m4a", "mp3", "wav"].contains(ext) { return .audioRecording }
                        if ["mp4", "mov"].contains(ext) { return .videoClip }
                        return .genericFile
                    }()
                    let chip = ComposerAttachmentChip(kind: kind, label: name, targetUri: url.absoluteString)
                    if !store.composerAttachments.contains(where: { $0.targetUri == chip.targetUri }) {
                        store.composerAttachments.append(chip)
                    }
                    if !attachedChipLabels.contains(name) {
                        attachedChipLabels.append(name)
                    }
                }
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
        voiceManager.stopRecording()
        let trimmed = draftMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasWorkflow = !(store.composerWorkflowCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard !trimmed.isEmpty || !attachedChipLabels.isEmpty || hasWorkflow else { return }
        let existingByLabel = Dictionary(uniqueKeysWithValues: store.composerAttachments.map { ($0.label, $0) })
        store.composerAttachments = attachedChipLabels.map { label in
            if let existing = existingByLabel[label] {
                return existing
            }
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
