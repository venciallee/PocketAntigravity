import SwiftUI
import UniformTypeIdentifiers
import AntigravityData

/// Native Matte Obsidian / Liquid Glass Composer (`ChatComposerView`) pinned at the bottom of `UE07_CHAT_AND_COMPOSER`.
/// Features:
/// - Removable `[@ratelimit.go ×]` context chip (`composer-chip-ratelimit`)
/// - Multi-line `TextField`, `/` 15-command popup, typo-tolerant `@` mention popup, Queued Messages strip
/// - Bottom toolbar with circular `+` (`composer-btn-add-context` -> `AddContextSheetView` / File Importer),
///   `[Planning ⌄]` pill (`composer-pill-mode`), `[<Model> ⌄]` pill (`composer-pill-model`),
///   real `SFSpeechRecognizer` `mic` button (`composer-btn-mic`), and circular `#8EB4FF` Send button (`composer-btn-send`).
public struct ChatComposerView: View {
    @Bindable public var store: AntigravitySessionStore
    @FocusState private var isInputFocused: Bool

    @State private var attachedChipLabels: [String]
    @State private var draftMessageText: String
    @State private var isShowingAddContextSheet: Bool = false
    @State private var isShowingModelAndModeSheet: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var voiceManager = VoiceInputManager()

    private static let periwinkle = Color(red: 0x8E / 255.0, green: 0xB4 / 255.0, blue: 0xFF / 255.0) // #8EB4FF
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
                                    Image(systemName: cmd.iconName)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Self.periwinkle)
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
                                .background(Self.controlPillBg.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 200)
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
                                            .foregroundStyle(Self.periwinkle)
                                        Text("@\(candidate.title)")
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(AntigravityTheme.inkReading)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Self.controlPillBg, in: Capsule())
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
                        .background(Self.controlPillBg.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
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
                            .background(Self.controlPillBg.opacity(0.7), in: Capsule())
                        }
                        .accessibilityIdentifier("composer-permission-preset")

                        Button {
                            store.openSideQuestion()
                        } label: {
                            Label("/btw", systemImage: "questionmark.bubble")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Self.periwinkle)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Self.periwinkle.opacity(0.12), in: Capsule())
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
                                .background(Self.controlPillBg.opacity(0.7), in: Capsule())
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
                                .background(Self.controlPillBg.opacity(0.7), in: Capsule())
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
                                .padding(.horizontal, 12)
                                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                                .background(Self.controlPillBg)
                                .clipShape(Capsule())
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
            .padding(.horizontal, 2)
            .accessibilityIdentifier("composer-text-input")

            // Bottom Toolbar: `+`, `Planning ⌄`, `<Active Model> ⌄`, `mic`, `↑` Send
            HStack(spacing: 5) {
                // 1. Circular `+` Add Context Button
                Button {
                    isShowingAddContextSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                        .background(Self.controlPillBg)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer-btn-add-context")

                // 2. `[Planning / Fast ⌄]` Mode Pill
                Button {
                    isShowingModelAndModeSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text(store.selectedModelConfig.mode.rawValue)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(minWidth: AntigravityTheme.minTouchTargetPt, minHeight: AntigravityTheme.minTouchTargetPt)
                    .background(Self.controlPillBg)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer-pill-mode")

                // 3. `[<Active Model> ⌄]` Model Pill
                Button {
                    isShowingModelAndModeSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text(store.selectedModelConfig.displayName)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.inkLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.88)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                    }
                    .padding(.horizontal, 9)
                    .frame(minWidth: AntigravityTheme.minTouchTargetPt, minHeight: AntigravityTheme.minTouchTargetPt)
                    .background(Self.controlPillBg)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer-pill-model")

                Spacer(minLength: 0)

                // 4. Real Live Speech-to-Text Mic Button (`SFSpeechRecognizer` + `AVAudioEngine`)
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
                        .font(.system(size: voiceManager.isRecording ? 20 : 16, weight: .medium))
                        .foregroundStyle(voiceManager.isRecording ? AntigravityTheme.statusError : AntigravityTheme.inkSecondary)
                        .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer-btn-mic")

                // 5. Circular `#8EB4FF` Periwinkle Send Button
                Button {
                    submitMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Self.inkOnCTA)
                        .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
                        .background(Self.periwinkle)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer-btn-send")
            }
        }
        .padding(10)
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
        .onChange(of: store.composerDraftText) { _, updated in
            if !updated.isEmpty && updated != draftMessageText {
                draftMessageText = updated
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
                onDismiss: {
                    isShowingModelAndModeSheet = false
                }
            )
        }
    }

    private func submitMessage() {
        voiceManager.stopRecording()
        let trimmed = draftMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachedChipLabels.isEmpty else { return }
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
