import Foundation
import Observation
#if canImport(os)
import os
#endif
#if canImport(Speech)
import Speech
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Native iOS live speech-to-text manager powered by `SFSpeechRecognizer` and `AVAudioEngine`.
/// Bridges real microphone dictation into `ChatComposerView`, `VoiceModeSheetView`, and `StructuredQuestionCardView`.
///
/// All Objective-C callback APIs (`SFSpeechRecognizer.requestAuthorization`, `recognitionTask`,
/// `AVAudioInputNode.installTap`, and audio session notifications) are bridged through explicit
/// `nonisolated static` helpers so Swift 6 strict concurrency never synthesizes a `@MainActor`
/// runtime assertion on Speech/CoreAudio background threads.
@MainActor
@Observable
public final class VoiceInputManager {
    public var isRecording: Bool = false
    public var isStarting: Bool = false
    public var liveTranscript: String = ""
    public var errorMessage: String? = nil
    public var authorizationGranted: Bool = false

    #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
    private var audioEngine: AVAudioEngine?
    private var hasInstalledTap: Bool = false
    private var activeRequestBox: AudioRequestBox?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let observerBag = ObserverBag()
    private var isAudioSessionActive: Bool = false
    #endif

    private var startTask: Task<Void, Never>?
    private var recordingSessionToken: UUID = UUID()

    public init() {}

    /// Appends live dictation text onto any existing user draft cleanly without wiping typed content.
    public nonisolated static func mergeTranscript(prefix: String, transcript: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return prefix }
        if prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return trimmedTranscript
        }
        if let last = prefix.last, last.isWhitespace || last.isNewline {
            return prefix + trimmedTranscript
        }
        return prefix + " " + trimmedTranscript
    }

    public func clearError() {
        errorMessage = nil
    }

    public func toggleRecording(onTranscriptUpdate: @escaping @MainActor (String) -> Void) {
        if isRecording || isStarting {
            stopRecording()
        } else {
            let sessionToken = UUID()
            recordingSessionToken = sessionToken
            isStarting = true
            errorMessage = nil
            liveTranscript = ""
            startTask?.cancel()
            startTask = Task { @MainActor [weak self] in
                await self?.startRecordingInternal(
                    sessionToken: sessionToken,
                    onTranscriptUpdate: onTranscriptUpdate
                )
            }
        }
    }

    public func startRecording(onTranscriptUpdate: @escaping @MainActor (String) -> Void) async {
        let sessionToken = UUID()
        recordingSessionToken = sessionToken
        isStarting = true
        errorMessage = nil
        liveTranscript = ""
        startTask?.cancel()
        startTask = nil
        await startRecordingInternal(
            sessionToken: sessionToken,
            onTranscriptUpdate: onTranscriptUpdate
        )
    }

    private func startRecordingInternal(
        sessionToken: UUID,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void
    ) async {
        defer {
            if recordingSessionToken == sessionToken {
                isStarting = false
            }
        }

        #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
        guard Self.hasRequiredPrivacyDescriptions() else {
            authorizationGranted = false
            errorMessage = "Voice dictation requires Microphone & Speech Recognition permissions in app configuration."
            return
        }

        let speechStatus = await Self.requestSpeechAuthorization()
        guard !Task.isCancelled, recordingSessionToken == sessionToken else {
            return
        }
        guard speechStatus == .authorized else {
            authorizationGranted = false
            errorMessage = "Enable Speech Recognition in Settings to dictate prompts."
            return
        }

        let micAllowed = await Self.requestMicrophonePermission()
        guard !Task.isCancelled, recordingSessionToken == sessionToken else {
            return
        }
        guard micAllowed else {
            authorizationGranted = false
            errorMessage = "Enable Microphone access in Settings to dictate prompts."
            return
        }
        authorizationGranted = true

        tearDownActiveAudio()

        guard let recognizer = Self.resolveSpeechRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognizer is temporarily unavailable on this device."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            isAudioSessionActive = true

            let hasInputPort = !session.currentRoute.inputs.isEmpty
                || !(session.availableInputs?.isEmpty ?? true)
            guard session.isInputAvailable, hasInputPort else {
                errorMessage = "No microphone input is available on this device."
                tearDownActiveAudio()
                return
            }

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let hardwareFormat = inputNode.inputFormat(forBus: 0)
            let outputFormat = inputNode.outputFormat(forBus: 0)
            guard hardwareFormat.sampleRate > 0,
                  hardwareFormat.channelCount > 0,
                  outputFormat.sampleRate > 0,
                  outputFormat.channelCount > 0 else {
                engine.stop()
                engine.reset()
                errorMessage = "Microphone audio input is temporarily unavailable. Please try again."
                tearDownActiveAudio()
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            let requestBox = AudioRequestBox(request)

            Self.installRealtimeAudioTap(
                on: inputNode,
                requestBox: requestBox
            )

            self.audioEngine = engine
            self.hasInstalledTap = true
            self.activeRequestBox = requestBox

            observerBag.installAudioObservers(engine: engine) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.recordingSessionToken == sessionToken else { return }
                    self.stopRecording()
                }
            }

            engine.prepare()
            try engine.start()

            guard !Task.isCancelled, recordingSessionToken == sessionToken else {
                tearDownActiveAudio()
                return
            }

            isRecording = true

            recognitionTask = Self.startRecognitionTask(
                recognizer: recognizer,
                request: request
            ) { [weak self] text, isFinal, errorCode, errDesc in
                Task { @MainActor [weak self] in
                    guard let self, self.recordingSessionToken == sessionToken else { return }
                    if let text, !text.isEmpty {
                        self.liveTranscript = text
                        onTranscriptUpdate(text)
                    }
                    if isFinal || errDesc != nil {
                        let hadTranscript = !self.liveTranscript.isEmpty
                        self.stopRecording()
                        if let errDesc,
                           !isFinal,
                           !hadTranscript,
                           !Self.isBenignCancellationError(code: errorCode) {
                            self.errorMessage = "Voice recognition stopped: \(errDesc)"
                        }
                    }
                }
            }
        } catch {
            errorMessage = "Unable to start microphone capture: \(error.localizedDescription)"
            tearDownActiveAudio()
            isRecording = false
        }
        #else
        errorMessage = "Speech dictation requires an iOS device with microphone access."
        #endif
    }

    public func stopRecording() {
        recordingSessionToken = UUID()
        startTask?.cancel()
        startTask = nil
        isStarting = false
        tearDownActiveAudio()
        isRecording = false
    }

    private func tearDownActiveAudio() {
        #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
        observerBag.clear()
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            if hasInstalledTap {
                engine.inputNode.removeTap(onBus: 0)
                hasInstalledTap = false
            }
            engine.reset()
            audioEngine = nil
        } else {
            hasInstalledTap = false
        }
        activeRequestBox?.finish()
        activeRequestBox = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if isAudioSessionActive {
            isAudioSessionActive = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }

    #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
    private final class AudioRequestBox: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        private let isEnded = OSAllocatedUnfairLock(initialState: false)

        init(_ request: SFSpeechAudioBufferRecognitionRequest) {
            self.request = request
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            let ended = isEnded.withLock { $0 }
            guard !ended else { return }
            request.append(buffer)
        }

        func finish() {
            let shouldEnd = isEnded.withLock { ended -> Bool in
                if ended { return false }
                ended = true
                return true
            }
            if shouldEnd {
                request.endAudio()
            }
        }
    }

    private final class ObserverBag: @unchecked Sendable {
        private let lock = NSLock()
        private var tokens: [NSObjectProtocol] = []

        func installAudioObservers(
            engine: AVAudioEngine,
            onStopRequested: @escaping @Sendable () -> Void
        ) {
            let interruption = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if rawType == AVAudioSession.InterruptionType.began.rawValue {
                    onStopRequested()
                }
            }
            let configChange = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { _ in
                onStopRequested()
            }
            replace(with: [interruption, configChange])
        }

        private func replace(with newTokens: [NSObjectProtocol]) {
            lock.lock()
            let oldTokens = tokens
            tokens = newTokens
            lock.unlock()
            for token in oldTokens {
                NotificationCenter.default.removeObserver(token)
            }
        }

        func clear() {
            replace(with: [])
        }

        deinit {
            clear()
        }
    }

    private nonisolated static func hasRequiredPrivacyDescriptions() -> Bool {
        let mic = (Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let speech = (Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !mic.isEmpty && !speech.isEmpty
    }

    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined {
            return current
        }
        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            SFSpeechRecognizer.requestAuthorization { status in
                let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                    if alreadyResumed { return false }
                    alreadyResumed = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private nonisolated static func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return await AVAudioApplication.requestRecordPermission()
        }
    }

    private nonisolated static func resolveSpeechRecognizer() -> SFSpeechRecognizer? {
        if let current = SFSpeechRecognizer(locale: Locale.current), current.isAvailable {
            return current
        }
        for identifier in Locale.preferredLanguages {
            if let candidate = SFSpeechRecognizer(locale: Locale(identifier: identifier)), candidate.isAvailable {
                return candidate
            }
        }
        if let defaultRecognizer = SFSpeechRecognizer(), defaultRecognizer.isAvailable {
            return defaultRecognizer
        }
        if let enUS = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), enUS.isAvailable {
            return enUS
        }
        return nil
    }

    private nonisolated static func installRealtimeAudioTap(
        on inputNode: AVAudioInputNode,
        requestBox: AudioRequestBox
    ) {
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            requestBox.append(buffer)
        }
    }

    private nonisolated static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onEvent: @escaping @Sendable (_ transcript: String?, _ isFinal: Bool, _ errorCode: Int?, _ errorDescription: String?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let nsError = error as NSError?
            onEvent(text, isFinal, nsError?.code, nsError?.localizedDescription)
        }
    }

    private nonisolated static func isBenignCancellationError(code: Int?) -> Bool {
        guard let code else { return false }
        // 203: retry/cancel, 216: request canceled, 301: recognition request canceled, 1110: no speech detected
        return code == 203 || code == 216 || code == 301 || code == 1110
    }
    #endif
}
