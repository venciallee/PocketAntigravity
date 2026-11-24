import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AntigravityData
#if canImport(UIKit)
import UIKit
#endif

/// Native Matte Obsidian Composer (`ChatComposerView`) pinned at the bottom of `UE01` (New Conversation Home)
/// and `UE07_CHAT_AND_COMPOSER` (`docs/ue/ios/Main.png` & `docs/ue/ios/ios-chat.png`).
/// Unified toolbar across Live and ESDD verification modes:
/// - Clean multi-line `TextField` on top (contextual `/` slash popup, `@` mention popup, attached image
///   thumbnails & file chips, workflow pill, and queued follow-ups appear only when active)
/// - Single-line bottom toolbar: `+` (`AddContextSheetView` with Photos & Files), single-line `[Gemini 4 Neon ⌄]`
///   (`ModelAndModeSheetView` displaying 4-level thinking effort when opened), `[🛡 Default ⌄]`
///   (`PermissionsSheetView`), `mic` dictation button, and adaptive primary action circle (`→` / `■`).
public struct ChatComposerView: View {
    private enum PrimaryActionMode: Equatable {
        case disabledSend
        case send
        case stop
    }

    private enum PendingDevicePicker: Equatable {
        case photos
        case files
    }

    private struct PreparedMediaPayload: Sendable {
        let base64: String
        let mimeType: String
        let byteSize: Int
        let fileExtension: String
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
    @State private var isShowingPhotoPicker: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var pendingDevicePicker: PendingDevicePicker? = nil
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isImportingMedia: Bool = false
    @State private var mediaErrorMessage: String? = nil
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
        let hasAttachments = !attachedChipLabels.isEmpty || !store.composerAttachments.isEmpty
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
                // Context & Image Preview Chips Strip (only rendered when attachments or media import active)
                if !attachedChipLabels.isEmpty || isImportingMedia {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(attachedChipLabels, id: \.self) { label in
                                attachmentChipView(for: label)
                            }
                            if isImportingMedia {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("Adding photo…")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(AntigravityTheme.inkSecondary)
                                }
                                .padding(.horizontal, 11)
                                .frame(height: 30)
                                .background(AntigravityTheme.surfaceElevated)
                                .clipShape(Capsule())
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

                if let mediaErr = mediaErrorMessage {
                    Text(mediaErr)
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

                // Unified Single-Line Bottom Toolbar (`+`, `Gemini 4 Neon ⌄`, `🛡 Default ⌄`, `mic`, `→`)
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
            if !store.composerAttachments.isEmpty {
                attachedChipLabels = store.composerAttachments.map(\.label)
            }
        }
        .onChange(of: store.composerDraftText) { _, newValue in
            if !isHomeComposer && draftMessageText != newValue {
                draftMessageText = newValue
            }
        }
        .onChange(of: store.composerAttachments.count) { _, _ in
            if !store.composerAttachments.isEmpty || !store.isVerificationMode {
                attachedChipLabels = store.composerAttachments.map(\.label)
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let picked = newItems
            selectedPhotoItems = []
            Task {
                await importSelectedPhotoItems(picked)
            }
        }
        .onDisappear {
            voiceManager.stopRecording()
        }
        .photosPicker(
            isPresented: $isShowingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 5,
            matching: .images
        )
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item, .pdf, .image, .audio, .movie, .zip],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    await importSelectedFileURLs(urls)
                }
            }
        }
        .sheet(isPresented: $isShowingAddContextSheet, onDismiss: {
            presentPendingDevicePickerIfNeeded()
        }) {
            AddContextSheetView(
                store: store,
                startExpanded: true,
                showHomeBackdrop: false,
                onAddLabels: { added in
                    for item in added where !attachedChipLabels.contains(item) {
                        attachedChipLabels.append(item)
                    }
                },
                onPickPhotos: {
                    pendingDevicePicker = .photos
                    isShowingAddContextSheet = false
                },
                onPickDeviceFile: {
                    pendingDevicePicker = .files
                    isShowingAddContextSheet = false
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

    // MARK: - Attachment Chip / Image Thumbnail Preview

    @ViewBuilder
    private func attachmentChipView(for label: String) -> some View {
        let chip = store.composerAttachments.first(where: { $0.label == label })
        #if canImport(UIKit)
        if let chip,
           chip.kind == .imageScreenshot,
           let b64 = chip.inlineBase64Data,
           let data = Data(base64Encoded: b64),
           let uiImage = UIImage(data: data) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
                    )

                Button {
                    attachedChipLabels.removeAll { $0 == label }
                    store.composerAttachments.removeAll { $0.label == label }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 20, height: 20)
                        .background(Color.black.opacity(0.72), in: Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .accessibilityLabel("Remove image \(label)")
            }
            .padding(.top, 4)
            .padding(.trailing, 4)
            .accessibilityIdentifier("composer-image-chip-\(label)")
        } else {
            textAttachmentChipButton(label: label, isMedia: chip?.inlineBase64Data != nil)
        }
        #else
        textAttachmentChipButton(label: label, isMedia: chip?.inlineBase64Data != nil)
        #endif
    }

    private func textAttachmentChipButton(label: String, isMedia: Bool) -> some View {
        Button {
            attachedChipLabels.removeAll { $0 == label }
            store.composerAttachments.removeAll { $0.label == label }
        } label: {
            HStack(spacing: 6) {
                if isMedia {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .lineLimit(1)
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

    // MARK: - Unified Single-Line Toolbar (`Main.png` & `ios-chat.png`)

    private var unifiedComposerToolbar: some View {
        let modelPill = modelPillComponents
        return HStack(spacing: 5) {
            // 1. `+` Add Context Button (Photos, Files, Workspace Mentions & Actions)
            Button {
                isShowingAddContextSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .frame(width: 30, height: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add context")
            .accessibilityIdentifier("composer-btn-add-context")

            // 2. Single-line `[Gemini 4 Neon ⌄]` Model Picker (Thinking Effort shown inside sheet when opened)
            Button {
                isShowingModelAndModeSheet = true
            } label: {
                HStack(spacing: 4) {
                    Text(modelPill.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                .padding(.horizontal, 2)
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel(
                modelPill.effort.map { "\(modelPill.name), \($0) effort" } ?? modelPill.name
            )
            .accessibilityIdentifier("composer-pill-model")

            Spacer(minLength: 2)

            // 3. Permission Preset Pill (`🛡 Default ⌄`)
            Button {
                isShowingPermissionsSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "shield")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Text(permissionShortLabel)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                .padding(.horizontal, 4)
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
                    .frame(width: 30, height: AntigravityTheme.minTouchTargetPt)
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
                    .frame(width: 36, height: AntigravityTheme.minTouchTargetPt)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(primaryActionMode == .disabledSend)
            .animation(.snappy(duration: 0.2), value: primaryActionMode)
            .accessibilityLabel(primaryActionAccessibilityLabel)
            .accessibilityIdentifier(primaryActionAccessibilityId)
        }
    }

    // MARK: - Media Import Helpers (PhotosPicker & Files)

    private func presentPendingDevicePickerIfNeeded() {
        guard let next = pendingDevicePicker else { return }
        pendingDevicePicker = nil
        switch next {
        case .photos:
            isShowingPhotoPicker = true
        case .files:
            isShowingFileImporter = true
        }
    }

    private func importSelectedPhotoItems(_ items: [PhotosPickerItem]) async {
        isImportingMedia = true
        mediaErrorMessage = nil
        defer { isImportingMedia = false }

        var failedCount = 0
        for item in items {
            let preferredMime = item.supportedContentTypes.first?.preferredMIMEType
            guard let rawData = try? await item.loadTransferable(type: Data.self), !rawData.isEmpty else {
                failedCount += 1
                continue
            }
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.prepareImagePayload(from: rawData, preferredMimeType: preferredMime)
            }.value
            guard let prepared else {
                failedCount += 1
                continue
            }
            let label = uniqueAttachmentLabel(base: "photo", ext: prepared.fileExtension)
            let chipId = UUID().uuidString
            let chip = ComposerAttachmentChip(
                id: chipId,
                kind: .imageScreenshot,
                label: label,
                targetUri: "attachment://photo/\(chipId)/\(label)",
                mimeType: prepared.mimeType,
                byteSize: prepared.byteSize,
                inlineBase64Data: prepared.base64
            )
            store.composerAttachments.append(chip)
            if !attachedChipLabels.contains(label) {
                attachedChipLabels.append(label)
            }
        }
        if failedCount > 0 {
            mediaErrorMessage = failedCount == 1
                ? "Could not load 1 selected photo."
                : "Could not load \(failedCount) selected photos."
        }
    }

    private func importSelectedFileURLs(_ urls: [URL]) async {
        isImportingMedia = true
        mediaErrorMessage = nil
        defer { isImportingMedia = false }

        var failedCount = 0
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let originalName = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
            let kind: ComposerAttachmentChip.Kind = {
                if ext == "pdf" { return .pdfDocument }
                if ext == "zip" { return .archiveZip }
                if ["png", "jpg", "jpeg", "webp", "heic", "heif", "gif"].contains(ext) { return .imageScreenshot }
                if ["m4a", "mp3", "wav", "aac", "flac"].contains(ext) { return .audioRecording }
                if ["mp4", "mov", "m4v"].contains(ext) { return .videoClip }
                return .genericFile
            }()
            let inferredMime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"

            let prepared: PreparedMediaPayload? = await Task.detached(priority: .userInitiated) {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                guard let rawData = try? Data(contentsOf: url), !rawData.isEmpty else {
                    return nil
                }
                if kind == .imageScreenshot {
                    return Self.prepareImagePayload(from: rawData, preferredMimeType: inferredMime)
                }
                let maxFileBytes = 8 * 1024 * 1024
                guard rawData.count <= maxFileBytes else { return nil }
                return PreparedMediaPayload(
                    base64: rawData.base64EncodedString(),
                    mimeType: inferredMime,
                    byteSize: rawData.count,
                    fileExtension: ext.isEmpty ? "bin" : ext
                )
            }.value

            guard let prepared else {
                failedCount += 1
                continue
            }

            let chipLabel: String = {
                if kind == .imageScreenshot && (ext == "heic" || ext == "heif") {
                    let stem = (originalName as NSString).deletingPathExtension
                    return "\(stem).\(prepared.fileExtension)"
                }
                return originalName
            }()
            let uniqueLabel = attachedChipLabels.contains(chipLabel)
                ? uniqueAttachmentLabel(base: (chipLabel as NSString).deletingPathExtension, ext: prepared.fileExtension)
                : chipLabel
            let chipId = UUID().uuidString
            let chip = ComposerAttachmentChip(
                id: chipId,
                kind: kind,
                label: uniqueLabel,
                targetUri: "attachment://file/\(chipId)/\(uniqueLabel)",
                mimeType: prepared.mimeType,
                byteSize: prepared.byteSize,
                inlineBase64Data: prepared.base64
            )
            store.composerAttachments.append(chip)
            if !attachedChipLabels.contains(uniqueLabel) {
                attachedChipLabels.append(uniqueLabel)
            }
        }
        if failedCount > 0 {
            mediaErrorMessage = "Some files could not be attached (exceeds 8 MB or unreadable)."
        }
    }

    private func uniqueAttachmentLabel(base: String, ext: String) -> String {
        let cleanBase = base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "photo" : base
        let cleanExt = ext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "jpg" : ext
        var counter = 1
        while true {
            let candidate = "\(cleanBase)-\(counter).\(cleanExt)"
            if !attachedChipLabels.contains(candidate)
                && !store.composerAttachments.contains(where: { $0.label == candidate }) {
                return candidate
            }
            counter += 1
        }
    }

    private nonisolated static func prepareImagePayload(
        from rawData: Data,
        preferredMimeType: String?
    ) -> PreparedMediaPayload? {
        #if canImport(UIKit)
        guard let image = UIImage(data: rawData) else { return nil }
        let maxDimension: CGFloat = 2048
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let largest = max(pixelWidth, pixelHeight)

        let lowerMime = (preferredMimeType ?? "").lowercased()
        let isStandardWebImage = lowerMime == "image/png" || lowerMime == "image/jpeg" || lowerMime == "image/jpg"
        let hasUpOrientation = image.imageOrientation == .up
        if isStandardWebImage && hasUpOrientation && largest <= maxDimension && rawData.count <= 2 * 1024 * 1024 {
            let normalizedMime = lowerMime == "image/png" ? "image/png" : "image/jpeg"
            let ext = normalizedMime == "image/png" ? "png" : "jpg"
            return PreparedMediaPayload(
                base64: rawData.base64EncodedString(),
                mimeType: normalizedMime,
                byteSize: rawData.count,
                fileExtension: ext
            )
        }

        let targetScale: CGFloat = largest > maxDimension && largest > 0 ? (maxDimension / largest) : 1.0
        let targetSize = CGSize(
            width: max(1, (pixelWidth * targetScale).rounded()),
            height: max(1, (pixelHeight * targetScale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        let qualities: [CGFloat] = [0.84, 0.72, 0.58]
        var encoded: Data? = nil
        for quality in qualities {
            if let jpeg = normalizedImage.jpegData(compressionQuality: quality) {
                encoded = jpeg
                if jpeg.count <= 2_500_000 {
                    break
                }
            }
        }
        guard let finalData = encoded ?? normalizedImage.pngData(), !finalData.isEmpty else {
            return nil
        }
        let mime = encoded != nil ? "image/jpeg" : "image/png"
        let ext = encoded != nil ? "jpg" : "png"
        return PreparedMediaPayload(
            base64: finalData.base64EncodedString(),
            mimeType: mime,
            byteSize: finalData.count,
            fileExtension: ext
        )
        #else
        let mime = preferredMimeType ?? "image/jpeg"
        let ext = mime.contains("png") ? "png" : "jpg"
        return PreparedMediaPayload(
            base64: rawData.base64EncodedString(),
            mimeType: mime,
            byteSize: rawData.count,
            fileExtension: ext
        )
        #endif
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
        mediaErrorMessage = nil
        let trimmed = draftMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasWorkflow = !(store.composerWorkflowCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard !trimmed.isEmpty || !attachedChipLabels.isEmpty || !store.composerAttachments.isEmpty || hasWorkflow else { return }

        let existingByLabel = Dictionary(
            store.composerAttachments.map { ($0.label, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let resolvedAttachments: [ComposerAttachmentChip] = attachedChipLabels.map { label in
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
        store.composerAttachments = resolvedAttachments
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
