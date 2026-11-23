import SwiftUI
import UniformTypeIdentifiers
import AntigravityData

/// Native Matte Obsidian Composer (`ChatComposerView`) pinned at the bottom of `UE01` (New Conversation Home)
/// and `UE07_CHAT_AND_COMPOSER` (`docs/ue/ios/Main.png` & `docs/ue/ios/ios-chat.png`).
/// Unified toolbar across Live and ESDD verification modes:
/// - Clean multi-line `TextField` on top (contextual `/` slash popup, `@` mention popup, attached chips,
///   workflow pill, and queued follow-ups appear only when active)
/// - Single bottom toolbar: `+` (`AddContextSheetView`), two-line `[Gemini 4 Neon / Extra High ⌄]`
///   (`ModelAndModeSheetView`), `[🛡 Default ⌄]` (`PermissionsSheetView`), `mic` dictation button,
///   and adaptive primary action circle (`→` send / `■` stop / dimmed `→` when empty).
public struct ChatComposerView: View {
    private enum PrimaryActionMode: Equatable {
        case disabledSend
        case send
        case stop
    }

    @Bindable public var store: AntigravitySessionStore
    public var placeholderOverride: String?
    public var isHomeComposer: Bool
    public var onSubmitDraft: ((String) -> Void)?
    @FocusState private var isInputFocused: Bool

    @State private var attachedChipLabels: [String]
    @State private var draftMessageText: String
    @State private var isShowingAddContextSheet: Bool = false
    @State private var isShowingModelAndModeSheet: Bool = false
    @State private var isShowingPermissionsSheet: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var voiceManager = VoiceInputManager()

    public init(
        store: AntigravitySessionStore,
        placeholderOverride: String? = nil,
        isHomeComposer: Bool = false,
        onSubmitDraft: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.placeholderOverride = placeholderOverride
        self.isHomeComposer = isHomeComposer
        self.onSubmitDraft = onSubmitDraft
        if isHomeComposer || !store.isVerificationMode || store.hasPairedBackend || store.isLiveBackendConnected {
            self._attachedChipLabels = State(initialValue: isHomeComposer ? [] : store.composerAttachments.map(\.label))
            self._draftMessageText = State(initialValue: isHomeComposer ? "" : store.composerDraftText)
        } else {
            self._attachedChipLabels = State(initialValue: ["@ratelimit.go"])
            self._draftMessageText = State(initialValue: "Use 1000/s instead — staging is smaller than prod.")
        }
    }

    private var activeMentionQuery: String? {
        guard let lastToken = draftMessageText.split(whereSeparator: \.isWhitespace).last,
              lastToken.hasPrefix("@"),
              lastToken.count >= 2 else {
            return nil
        }
        return String(lastToken.dropFirst())
    }

    private var activeSlashCommands: [SlashCommandItem] {
        guard !store.isSlashPopupDismissedManually else { return [] }
        return store.filteredSlashCommands(for: draftMessageText)
    }

    private var activeQueuedMessages: [QueuedMessageItem] {
        store.queuedMessages.filter { $0.cascadeId == store.activeCascadeId }
    }

    private var canSendDraft: Bool {
        let hasText = !draftMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !attachedChipLabels.isEmpty
        let hasWorkflow = !(store.composerWorkflowCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasText || hasAttachments || hasWorkflow
    }

    private var primaryActionMode: PrimaryActionMode {
        if canSendDraft {
            return .send
        }
        if store.isCascadeStreaming && !isHomeComposer {
            return .stop
        }
        return .disabledSend
    }

    private var modelPillComponents: (name: String, effort: String?) {
        let config = store.selectedModelConfig
        var name = config.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedEffort: String? = nil

        let effortSuffixes: [(String, String)] = [
            (" (XHigh)", "Extra High"),
            (" (X-High)", "Extra High"),
            (" (Extra High)", "Extra High"),
            (" (Extra)", "Extra High"),
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
                case .extra: return "Extra High"
                }
            }
            return nil
        }()

        return (name, effortLabel)
    }

    private var permissionShortLabel: String {
        switch store.activePermissionPreset {
        case .requestReview: return "Ask"
        case .defaultPolicy: return "Default"
        case .auto: return "Auto"
        case .turbo: return "Turbo"
        case .inheritGlobal: return "Default"
        }
    }

    private var primaryActionIconName: String {
        switch primaryActionMode {
        case .disabledSend, .send:
            return "arrow.right"
        case .stop:
            return "stop.fill"
        }
    }

    private var primaryActionIconSize: CGFloat {
        switch primaryActionMode {
        case .disabledSend, .send:
            return 15.5
        case .stop:
            return 12.5
        }
    }

    private var primaryActionForeground: Color {
        switch primaryActionMode {
        case .send:
            return AntigravityTheme.inkOnPrimaryCTA
        case .disabledSend:
            return AntigravityTheme.inkSecondary
        case .stop:
            return AntigravityTheme.pillActiveForeground
        }
    }

    private var primaryActionBackground: Color {
        switch primaryActionMode {
        case .send:
            return AntigravityTheme.accentPeriwinkle
        case .disabledSend:
            return AntigravityTheme.surfacePopover
        case .stop:
            return AntigravityTheme.pillActiveBackground
        }
    }

    private var primaryActionAccessibilityId: String {
        switch primaryActionMode {
        case .disabledSend, .send:
            return "composer-btn-send"
        case .stop:
            return "composer-btn-stop"
        }
    }

    private var primaryActionAccessibilityLabel: String {
        switch primaryActionMode {
        case .disabledSend, .send:
            return "Send message"
        case .stop:
            return "Stop response"
        }
    }

    private var resolvedPlaceholder: String {
        if let placeholderOverride {
            return placeholderOverride
        }
        return store.isCascadeStreaming ? "Ask a follow-up..." : "Ask anything, @ to mention, / for actions"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Contextual Slash Command Popup (`/plan`, `/compact`, `/new`, `/swarm`, `/run-workflow`, etc.)
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
                                            .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(AntigravityTheme.inkReading)
                                        Text(cmd.summary)
                                            .font(.system(size: 12))
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

            // Typo-Tolerant @Mention Autocomplete Popup
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
            if !activeQueuedMessages.isEmpty {
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
            VStack(alignment: .leading, spacing: 10) {
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
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                            .foregroundStyle(AntigravityTheme.inkReading)
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(AntigravityTheme.inkSecondary)
                                    }
                                    .padding(.horizontal, 11)
                                    .frame(height: 30)
                                    .background(AntigravityTheme.surfaceElevated)
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
                    resolvedPlaceholder,
                    text: $draftMessageText,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .font(.system(size: 16))
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

                // Unified Bottom Toolbar (`+`, `Gemini 4 Neon / Extra High ⌄`, `🛡 Default ⌄`, `mic`, `→`)
                unifiedComposerToolbar
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(isHomeComposer ? AntigravityTheme.surfaceElevated.opacity(0.65) : AntigravityTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AntigravityTheme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .onAppear {
            if !isHomeComposer && !store.composerDraftText.isEmpty {
                draftMessageText = store.composerDraftText
            }
        }
        .onChange(of: store.composerDraftText) { _, newValue in
            if !isHomeComposer && draftMessageText != newValue {
                draftMessageText = newValue
            }
        }
        .onChange(of: store.composerAttachments.count) { _, _ in
            guard !isHomeComposer else { return }
            if !store.composerAttachments.isEmpty || !store.isVerificationMode {
                attachedChipLabels = store.composerAttachments.map(\.label)
            }
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
                startExpanded: true,
                showHomeBackdrop: false,
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
            .presentationDetents([.fraction(0.82), .large])
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

    // MARK: - Unified Toolbar (`Main.png` & `ios-chat.png`)

    private var unifiedComposerToolbar: some View {
        let modelPill = modelPillComponents
        return HStack(spacing: 8) {
            // 1. `+` Add Context Button
            Button {
                isShowingAddContextSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .frame(width: 34, height: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add context")
            .accessibilityIdentifier("composer-btn-add-context")

            // 2. Two-line `[Gemini 4 Neon / Extra High ⌄]` Model & Effort Picker
            Button {
                isShowingModelAndModeSheet = true
            } label: {
                HStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(modelPill.name)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let effort = modelPill.effort {
                            Text(effort)
                                .font(.system(size: 11.5, weight: .regular))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                .padding(.horizontal, 4)
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                modelPill.effort.map { "\(modelPill.name), \($0) effort" } ?? modelPill.name
            )
            .accessibilityIdentifier("composer-pill-model")

            Spacer(minLength: 4)

            // 3. Permission Preset Pill (`🛡 Default ⌄`)
            Button {
                isShowingPermissionsSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "shield")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Text(permissionShortLabel)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                .padding(.horizontal, 6)
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Permissions \(store.activePermissionPreset.displayTitle)")
            .accessibilityIdentifier("composer-pill-permissions")

            // 4. Speech-to-Text Dictation Button (`mic`)
            Button {
                voiceManager.toggleRecording { transcript in
                    draftMessageText = transcript
                }
            } label: {
                Image(systemName: voiceManager.isRecording ? "stop.fill" : "mic")
                    .font(.system(size: voiceManager.isRecording ? 12.5 : 16, weight: .regular))
                    .foregroundStyle(voiceManager.isRecording ? AntigravityTheme.statusError : AntigravityTheme.inkReading)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voiceManager.isRecording ? "Stop dictation" : "Dictate message")
            .accessibilityIdentifier("composer-btn-mic")

            // 5. Adaptive Primary Action Circle (`→` Send / `■` Stop / Dimmed `→` when empty)
            Button {
                handlePrimaryAction()
            } label: {
                Image(systemName: primaryActionIconName)
                    .font(.system(size: primaryActionIconSize, weight: .bold))
                    .foregroundStyle(primaryActionForeground)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .background(primaryActionBackground, in: Circle())
                    .frame(width: 38, height: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(primaryActionMode == .disabledSend)
            .animation(.snappy(duration: 0.2), value: primaryActionMode)
            .accessibilityLabel(primaryActionAccessibilityLabel)
            .accessibilityIdentifier(primaryActionAccessibilityId)
        }
    }

    // MARK: - Actions

    private func handlePrimaryAction() {
        switch primaryActionMode {
        case .disabledSend:
            break
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
        if let onSubmitDraft {
            onSubmitDraft(trimmed)
        } else {
            store.composerDraftText = trimmed
            store.sendCurrentDraft()
        }
        draftMessageText = ""
        attachedChipLabels.removeAll()
    }
}
