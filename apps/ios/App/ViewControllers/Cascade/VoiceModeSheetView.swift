import SwiftUI
import AntigravityData

/// Native Gemini Live Voice Mode sheet (Antigravity v2.29 - v2.31).
/// Supports 9 voices, 0.75x–2.0x speed, live mic dictation via `VoiceInputManager`,
/// interrupt/mute controls, voice-driven approval banners, and Call Summary generation.
public struct VoiceModeSheetView: View {
    @Bindable private var store: AntigravitySessionStore
    @State private var voiceManager = VoiceInputManager()
    @State private var manualPromptText: String = ""
    @Environment(\.dismiss) private var dismiss

    public init(store: AntigravitySessionStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                headerWaveformCard
                if let waiting = store.pendingWaitingStep {
                    voiceApprovalBanner(step: waiting)
                }
                transcriptStream
                controlsPanel
            }
            .padding(16)
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
            .navigationTitle("Gemini Live Voice Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End Call") {
                        voiceManager.stopRecording()
                        store.endVoiceMode()
                        dismiss()
                    }
                    .foregroundStyle(AntigravityTheme.statusError)
                    .accessibilityIdentifier("btn_end_voice_mode")
                }
            }
        }
        .accessibilityIdentifier("sheet_voice_mode")
        .onDisappear {
            voiceManager.stopRecording()
        }
    }

    private var headerWaveformCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AntigravityTheme.accentPeriwinkle.opacity(voiceManager.isRecording ? 0.28 : 0.14))
                    .frame(width: 84, height: 84)
                Image(systemName: store.voiceModeState.isMuted ? "mic.slash.fill" : "waveform")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(store.voiceModeState.isMuted ? AntigravityTheme.statusError : AntigravityTheme.accentPeriwinkle)
            }
            Text(
                voiceManager.isRecording
                    ? "Listening..."
                    : (voiceManager.isStarting
                        ? "Starting microphone..."
                        : (store.voiceModeState.isMuted ? "Microphone Muted" : "Connected · \(store.voiceModeState.selectedVoiceId.capitalized)"))
            )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkReading)

            // 9 Voices Picker + Playback Speed
            HStack(spacing: 12) {
                Menu {
                    ForEach(GeminiLiveVoiceOption.allVoices) { option in
                        Button {
                            store.selectVoiceOption(option.id)
                        } label: {
                            Text("\(option.displayName) — \(option.toneSummary)")
                        }
                    }
                } label: {
                    Label(store.voiceModeState.selectedVoiceId.capitalized, systemImage: "person.wave.2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AntigravityTheme.surfaceElevated, in: Capsule())
                }
                .accessibilityIdentifier("menu_voice_picker")

                Menu {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button("\(String(format: "%.2gx", speed))") {
                            store.setVoicePlaybackSpeed(speed)
                        }
                    }
                } label: {
                    Label(String(format: "%.2gx", store.voiceModeState.playbackSpeed), systemImage: "gauge.medium")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AntigravityTheme.surfaceElevated, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }

    private func voiceApprovalBanner(step: CascadeStep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pending Approval · Voice Confirmation", systemImage: "faceid")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AntigravityTheme.statusWaiting)
            Text(step.runCommand?.proposedCommandLine ?? step.requestedInteraction?.permission?.target ?? "Pending action")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AntigravityTheme.inkReading)
                .lineLimit(2)
            HStack(spacing: 10) {
                Button("Approve") {
                    store.approveWaitingCommandWithFaceID(stepIndex: step.stepIndex)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkOnAmberCTA)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(AntigravityTheme.statusWaiting, in: RoundedRectangle(cornerRadius: 10))
                Button("Deny") {
                    store.denyWaitingCommand(stepIndex: step.stepIndex)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AntigravityTheme.statusError)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(AntigravityTheme.statusError.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AntigravityTheme.statusWaiting.opacity(0.45), lineWidth: 1))
    }

    private var transcriptStream: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(store.voiceModeState.activeTurns) { turn in
                    HStack {
                        if turn.isUser { Spacer(minLength: 36) }
                        Text(turn.transcript)
                            .font(.system(size: 14))
                            .foregroundStyle(turn.isUser ? AntigravityTheme.inkOnPrimaryCTA : AntigravityTheme.inkReading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                turn.isUser ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.surfaceCard,
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        if !turn.isUser { Spacer(minLength: 36) }
                    }
                }
            }
        }
    }

    private var controlsPanel: some View {
        VStack(spacing: 10) {
            if let err = voiceManager.errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.statusWaiting)
                    .accessibilityIdentifier("voice-mode-error")
            }
            HStack(spacing: 10) {
                TextField("Or type a live voice turn...", text: $manualPromptText)
                    .font(.system(size: 14))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AntigravityTheme.surfaceInput, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AntigravityTheme.cardBorder, lineWidth: 1))
                Button("Send") {
                    voiceManager.stopRecording()
                    let text = manualPromptText
                    manualPromptText = ""
                    store.appendVoiceTranscriptTurn(isUser: true, text: text)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(AntigravityTheme.accentPeriwinkle, in: RoundedRectangle(cornerRadius: 12))
                .disabled(manualPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 14) {
                Button {
                    store.toggleVoiceMute()
                    if store.voiceModeState.isMuted {
                        voiceManager.stopRecording()
                    }
                } label: {
                    Label(store.voiceModeState.isMuted ? "Unmute" : "Mute", systemImage: store.voiceModeState.isMuted ? "mic.slash" : "mic")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    if !voiceManager.isRecording && !voiceManager.isStarting && store.voiceModeState.isMuted {
                        store.toggleVoiceMute()
                    }
                    let prefix = manualPromptText
                    voiceManager.toggleRecording { spoken in
                        manualPromptText = VoiceInputManager.mergeTranscript(prefix: prefix, transcript: spoken)
                    }
                } label: {
                    Label(
                        voiceManager.isRecording
                            ? "Stop Mic"
                            : (voiceManager.isStarting ? "Starting..." : "Speak"),
                        systemImage: (voiceManager.isRecording || voiceManager.isStarting) ? "stop.circle.fill" : "waveform.circle.fill"
                    )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(voiceManager.isRecording ? AntigravityTheme.statusError : AntigravityTheme.accentPeriwinkle, in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("btn_voice_mode_speak")
            }
        }
    }
}
