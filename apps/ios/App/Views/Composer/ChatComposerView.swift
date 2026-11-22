import SwiftUI
import UniformTypeIdentifiers
import AntigravityData

/// Native Matte Obsidian / Liquid Glass Composer (`ChatComposerView`) pinned at the bottom of `UE07_CHAT_AND_COMPOSER`.
/// Live Antigravity 2.x mode adopts a clean, Claude-inspired 4-control layout:
/// - Clean multi-line `TextField` on top (contextual `/` slash popup, `@` mention popup, attached chips, workflow pill, and queued follow-ups appear only when active)
/// - Single bottom toolbar: circular `+` Menu (`Add Context`, `Attach Files`, `Permissions`),
///   two-tone `[<Model>  <Effort>]` pill -> `ModelAndModeSheetView`, circular `mic` dictation button (`SFSpeechRecognizer`),
///   and an adaptive primary action circle (`Voice Mode` waveform when empty -> `Send ↑` when typing/attached -> `Stop ■` while streaming).
/// - ESDD verification mode (`UE07`) preserves the `[Planning ⌄]` pill (`composer-pill-mode`) alongside `[Gemini 3.1 Pro ⌄]`.
public struct ChatComposerView: View {
    private enum PrimaryActionMode: Equatable {
        case voiceMode
        case send
        case stop
    }

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
        return store.filteredSlashCommands(for: draftMessageText).filter { $0.command != "/btw" }
    }

    private var activeQueuedMessages: [QueuedMessageItem] {
        store.queuedMessages.filter { $0.cascadeId == store.activeCascadeId }
    }

    private var isLiveAntigravity2Mode: Bool {
        !store.isVerificationMode || store.hasPairedBackend || store.isLiveBackendConnected
    }

    private var canSendDraft: Bool {
        let hasText = !draftMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !attachedChipLabels.isEmpty
        let hasWorkflow = !(store.composerWorkflowCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasText || hasAttachments || hasWorkflow
    }

    private var primaryActionMode: PrimaryActionMode {
        guard isLiveAntigravity2Mode else { return .send }
        if canSendDraft {
            return .send
        }
        if store.isCascadeStreaming {
            return .stop
        }
        return .voiceMode
    }

    private var modelPillComponents: (name: String, effort: String?) {
        let config = store.selectedModelConfig
        var name = config.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedEffort: String? = nil

        let effortSuffixes: [(String, String)] = [
            (" (XHigh)", "XHigh"),
            (" (X-High)", "XHigh"),
            (" (Extra High)", "XHigh"),
            (" (Extra)", "XHigh"),
            (" (Max)", "Max"),
            (" (High)", "High"),
            (" (Medium)", "Medium"),
            (" (Med)", "Medium"),
            (" (Low)", "Low"),
            (" (Minimal)", "Minimal")
        ]
        for (suffix, label) in effortSuffixes where name.lowercased().hasSuffix(suffix.lowercased()) {
            name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            parsedEffort = label
            break
        }

        if name.lowercased().hasSuffix(" (thinking)") {
            name = String(name.dropLast(" (thinking)".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let effortLabel: String? = {
            if let parsedEffort { return parsedEffort }
            if config.supportsEffortAdjustment {
                switch config.effort {
                case .low: return "Low"
                case .medium: return "Medium"
                case .high: return "High"
                case .extra: return "XHigh"
                }
            }
            return nil
        }()

        return (name, effortLabel)
    }

    private var primaryActionIconName: String {
        switch primaryActionMode {
        case .voiceMode:
            return "waveform"
        case .send:
            return "arrow.up"
        case .stop:
            return "stop.fill"
        }
    }

    private var primaryActionIconSize: CGFloat {
        switch primaryActionMode {
        case .voiceMode:
            return 16
        case .send:
            return 15.5
        case .stop:
            return 12.5
        }
    }

    private var primaryActionForeground: Color {
        switch primaryActionMode {
        case .send:
            return AntigravityTheme.inkOnPrimaryCTA
        case .voiceMode, .stop:
            return AntigravityTheme.pillActiveForeground
        }
    }

    private var primaryActionBackground: Color {
        switch primaryActionMode {
        case .send:
            return AntigravityTheme.accentPeriwinkle
        case .voiceMode, .stop:
            return AntigravityTheme.pillActiveBackground
        }
    }

    private var primaryActionAccessibilityId: String {
        switch primaryActionMode {
        case .voiceMode:
            return "composer-btn-voice-mode"
        case .send:
            return "composer-btn-send"
        case .stop:
            return "composer-btn-stop"
        }
    }

    private var primaryActionAccessibilityLabel: String {
        switch primaryActionMode {
        case .voiceMode:
            return "Start Voice Mode"
        case .send:
            return "Send message"
        case .stop:
            return "Stop response"
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

            // Composer Card
            VStack(alignment: .leading, spacing: isLiveAntigravity2Mode ? 10 : 8) {
                // Context Chips Strip (only rendered when attachments are present)
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
                        .padding(.horizontal, 4)
                }

                // Multi-line Draft Input
                TextField(
                    isLiveAntigravity2Mode
                        ? (store.isCascadeStreaming ? "Ask a follow-up..." : "Chat with Antigravity")
                        : "Reply to agent or @mention files...",
                    text: $draftMessageText,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .font(.system(size: isLiveAntigravity2Mode ? 16 : 15.5))
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
                .padding(.horizontal, isLiveAntigravity2Mode ? 6 : 4)
                .padding(.top, 2)
                .accessibilityIdentifier("composer-text-input")

                // Bottom Toolbar
                if isLiveAntigravity2Mode {
                    liveClaudeStyleToolbar
                } else {
                    verificationModeToolbar
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, isLiveAntigravity2Mode ? 12 : 10)
            .padding(.bottom, isLiveAntigravity2Mode ? 8 : 10)
            .background(AntigravityTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: isLiveAntigravity2Mode ? 26 : 24, style: .continuous)
                    .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: isLiveAntigravity2Mode ? 26 : 24, style: .continuous))
            .shadow(
                color: isLiveAntigravity2Mode ? AntigravityTheme.glassShadow.opacity(0.32) : .clear,
                radius: 10,
                x: 0,
                y: 3
            )
        }
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
                onPickDeviceFile: {
                    isShowingAddContextSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        isShowingFileImporter = true
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

    // MARK: - Live Mode Toolbar (Claude-Inspired 4-Control Layout)

    private var liveClaudeStyleToolbar: some View {
        let modelPill = modelPillComponents
        return HStack(spacing: 8) {
            // 1. Circular `+` Menu (`Add Context`, `Attach Files`, `Permissions`)
            Menu {
                Button {
                    isShowingAddContextSheet = true
                } label: {
                    Label("Add Context", systemImage: "at")
                }

                Button {
                    isShowingFileImporter = true
                } label: {
                    Label("Attach Files", systemImage: "paperclip")
                }

                Divider()

                Button {
                    isShowingPermissionsSheet = true
                } label: {
                    Label(
                        "Permissions · \(store.activePermissionPreset.displayTitle)",
                        systemImage: store.activePermissionPreset.semanticIcon.sfSymbolName
                    )
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .frame(width: 36, height: 36)
                    .background(AntigravityTheme.surfaceElevated, in: Circle())
                    .frame(width: 40, height: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Add context or actions")
            .accessibilityIdentifier("composer-btn-add-context")

            // 2. Two-tone `[<Model>  <Effort>]` Pill -> `ModelAndModeSheetView`
            Button {
                isShowingModelAndModeSheet = true
            } label: {
                HStack(spacing: 5) {
                    Text(modelPill.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let effort = modelPill.effort {
                        Text(effort)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(AntigravityTheme.surfaceElevated, in: Capsule())
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                modelPill.effort.map { "\(modelPill.name), \($0) effort" } ?? modelPill.name
            )
            .accessibilityIdentifier("composer-pill-model")

            Spacer(minLength: 4)

            // 3. Circular Speech-to-Text Dictation Button (`SFSpeechRecognizer`)
            Button {
                voiceManager.toggleRecording { transcript in
                    draftMessageText = transcript
                }
            } label: {
                Image(systemName: voiceManager.isRecording ? "stop.fill" : "mic")
                    .font(.system(size: voiceManager.isRecording ? 12.5 : 15.5, weight: .medium))
                    .foregroundStyle(voiceManager.isRecording ? AntigravityTheme.statusError : AntigravityTheme.inkReading)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .background(
                        voiceManager.isRecording
                            ? AntigravityTheme.statusError.opacity(0.16)
                            : AntigravityTheme.surfaceElevated,
                        in: Circle()
                    )
                    .frame(width: 40, height: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voiceManager.isRecording ? "Stop dictation" : "Dictate message")
            .accessibilityIdentifier("composer-btn-mic")

            // 4. Adaptive Primary Action Circle (`Voice Mode` -> `Send ↑` -> `Stop ■`)
            Button {
                handlePrimaryAction()
            } label: {
                Image(systemName: primaryActionIconName)
                    .font(.system(size: primaryActionIconSize, weight: .bold))
                    .foregroundStyle(primaryActionForeground)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .background(primaryActionBackground, in: Circle())
                    .frame(width: 40, height: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.snappy(duration: 0.2), value: primaryActionMode)
            .accessibilityLabel(primaryActionAccessibilityLabel)
            .accessibilityIdentifier(primaryActionAccessibilityId)
        }
    }

    // MARK: - ESDD UE07 Verification Toolbar

    private var verificationModeToolbar: some View {
        let modelPill = modelPillComponents
        return HStack(spacing: 6) {
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

            Button {
                isShowingModelAndModeSheet = true
            } label: {
                HStack(spacing: 4) {
                    Text(modelPill.name)
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

    // MARK: - Actions

    private func handlePrimaryAction() {
        switch primaryActionMode {
        case .voiceMode:
            voiceManager.stopRecording()
            store.startVoiceMode()
        case .stop:
            voiceManager.stopRecording()
            store.stopActiveCascadeStreaming()
        case .send:
            submitMessage()
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
