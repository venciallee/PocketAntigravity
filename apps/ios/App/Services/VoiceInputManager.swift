import Foundation
import Observation
import AntigravityData
#if canImport(os)
import os
#endif
#if canImport(Speech)
import Speech
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Native iOS live speech-to-text manager powered by `SFSpeechRecognizer` and `AVAudioEngine`.
/// Bridges real microphone dictation into `ChatComposerView`, `VoiceModeSheetView`, and `StructuredQuestionCardView`.
///
/// - Resolves the speech recognizer locale via `VoiceLocaleResolver` (explicit user override ->
///   in-app `AppLanguage` -> OS `Locale.preferredLanguages` -> active keyboard) so Chinese speech
///   never mis-defaults to `Locale.current` (`en_CN`/`en_US`) when the bundle has no `.lproj`.
/// - Bridges every Objective-C callback API (`SFSpeechRecognizer.requestAuthorization`,
///   `recognitionTask`, `AVAudioInputNode.installTap`, and audio session notifications) through
///   `nonisolated static` helpers so Swift 6 never asserts `@MainActor` on Speech/CoreAudio threads.
@MainActor
@Observable
public final class VoiceInputManager {
    private static let preferredLanguageDefaultsKey = "antigravity.voice.dictationLanguage"

    public var isRecording: Bool = false
    public var isStarting: Bool = false
    public var liveTranscript: String = ""
    public var errorMessage: String? = nil
    public var authorizationGranted: Bool = false
    public var preferredLanguage: VoiceDictationLanguage
    public var activeLocaleIdentifier: String? = nil

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

    public init() {
        let savedRaw = UserDefaults.standard.string(forKey: Self.preferredLanguageDefaultsKey)
        self.preferredLanguage = VoiceDictationLanguage.fromTag(savedRaw)
    }

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

    public func activeLanguageBadgeLabel(for appLanguage: AppLanguage) -> String {
        if let activeLocaleIdentifier {
            return VoiceLocaleResolver.shortDisplayLabel(forLocaleTag: activeLocaleIdentifier)
        }
        if preferredLanguage != .auto {
            return preferredLanguage.shortBadgeLabel(for: appLanguage)
        }
        let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: preferredLanguage,
            appLanguage: appLanguage,
            systemPreferredLanguages: Locale.preferredLanguages,
            activeKeyboardLanguage: activeKeyboardPrimaryLanguage(),
            fallbackLocaleTag: Locale.current.identifier
        )
        return VoiceLocaleResolver.shortDisplayLabel(forLocaleTag: candidates.first)
    }

    public func selectLanguage(
        _ language: VoiceDictationLanguage,
        appLanguage: AppLanguage = .english,
        restartOnTranscriptUpdate: (@MainActor (String) -> Void)? = nil
    ) {
        preferredLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.preferredLanguageDefaultsKey)
        activeLocaleIdentifier = language.bcp47Tag
        if (isRecording || isStarting), let restartOnTranscriptUpdate {
            stopRecording()
            toggleRecording(appLanguage: appLanguage, onTranscriptUpdate: restartOnTranscriptUpdate)
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    public func toggleRecording(
        appLanguage: AppLanguage = .english,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void
    ) {
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
                    appLanguage: appLanguage,
                    onTranscriptUpdate: onTranscriptUpdate
                )
            }
        }
    }

    public func startRecording(
        appLanguage: AppLanguage = .english,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void
    ) async {
        let sessionToken = UUID()
        recordingSessionToken = sessionToken
        isStarting = true
        errorMessage = nil
        liveTranscript = ""
        startTask?.cancel()
        startTask = nil
        await startRecordingInternal(
            sessionToken: sessionToken,
            appLanguage: appLanguage,
            onTranscriptUpdate: onTranscriptUpdate
        )
    }

    private func startRecordingInternal(
        sessionToken: UUID,
        appLanguage: AppLanguage,
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
            errorMessage = appLanguage.t(
                "Voice dictation requires Microphone & Speech Recognition permissions in app configuration.",
                "语音输入需要在应用配置中声明麦克风与语音识别权限。"
            )
            return
        }

        let speechStatus = await Self.requestSpeechAuthorization()
        guard !Task.isCancelled, recordingSessionToken == sessionToken else {
            return
        }
        guard speechStatus == .authorized else {
            authorizationGranted = false
            errorMessage = appLanguage.t(
                "Enable Speech Recognition in Settings to dictate prompts.",
                "请在系统设置中开启语音识别权限以使用语音输入。"
            )
            return
        }

        let micAllowed = await Self.requestMicrophonePermission()
        guard !Task.isCancelled, recordingSessionToken == sessionToken else {
            return
        }
        guard micAllowed else {
            authorizationGranted = false
            errorMessage = appLanguage.t(
                "Enable Microphone access in Settings to dictate prompts.",
                "请在系统设置中开启麦克风权限以使用语音输入。"
            )
            return
        }
        authorizationGranted = true

        tearDownActiveAudio()

        let keyboardLang = activeKeyboardPrimaryLanguage()
        guard let recognizer = Self.resolveSpeechRecognizer(
            preference: preferredLanguage,
            appLanguage: appLanguage,
            activeKeyboardLanguage: keyboardLang
        ), recognizer.isAvailable else {
            errorMessage = appLanguage.t(
                "Speech recognizer is temporarily unavailable on this device.",
                "当前设备的语音识别服务暂不可用。"
            )
            return
        }
        activeLocaleIdentifier = recognizer.locale.identifier

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            isAudioSessionActive = true

            let hasInputPort = !session.currentRoute.inputs.isEmpty
                || !(session.availableInputs?.isEmpty ?? true)
            guard session.isInputAvailable, hasInputPort else {
                errorMessage = appLanguage.t(
                    "No microphone input is available on this device.",
                    "当前设备没有可用的麦克风输入。"
                )
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
                errorMessage = appLanguage.t(
                    "Microphone audio input is temporarily unavailable. Please try again.",
                    "麦克风音频输入暂不可用，请重试。"
                )
                tearDownActiveAudio()
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.addsPunctuation = true
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
                            self.errorMessage = appLanguage.t(
                                "Voice recognition stopped: \(errDesc)",
                                "语音识别已停止：\(errDesc)"
                            )
                        }
                    }
                }
            }
        } catch {
            errorMessage = appLanguage.t(
                "Unable to start microphone capture: \(error.localizedDescription)",
                "无法启动麦克风采集：\(error.localizedDescription)"
            )
            tearDownActiveAudio()
            isRecording = false
        }
        #else
        errorMessage = appLanguage.t(
            "Speech dictation requires an iOS device with microphone access.",
            "语音输入需要在支持麦克风的 iOS 设备上使用。"
        )
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

    private func activeKeyboardPrimaryLanguage() -> String? {
        #if canImport(UIKit) && os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows where window.isKeyWindow {
                if let responder = Self.findFirstResponder(in: window),
                   let primary = responder.textInputMode?.primaryLanguage,
                   !primary.isEmpty,
                   primary.lowercased() != "dictation",
                   primary.lowercased() != "emoji" {
                    return primary
                }
            }
        }
        #endif
        return nil
    }

    #if canImport(UIKit) && os(iOS)
    private static func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder {
            return view
        }
        for subview in view.subviews {
            if let found = findFirstResponder(in: subview) {
                return found
            }
        }
        return nil
    }
    #endif

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

    private nonisolated static func resolveSpeechRecognizer(
        preference: VoiceDictationLanguage,
        appLanguage: AppLanguage,
        activeKeyboardLanguage: String?
    ) -> SFSpeechRecognizer? {
        let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: preference,
            appLanguage: appLanguage,
            systemPreferredLanguages: Locale.preferredLanguages,
            activeKeyboardLanguage: activeKeyboardLanguage,
            fallbackLocaleTag: Locale.current.identifier
        )
        let supportedTags = Set(SFSpeechRecognizer.supportedLocales().map(\.identifier))

        if let bestSupported = VoiceLocaleResolver.resolveBestLocaleTag(
            candidates: candidates,
            supportedLocaleTags: supportedTags
        ), let recognizer = SFSpeechRecognizer(locale: Locale(identifier: bestSupported)), recognizer.isAvailable {
            return recognizer
        }

        for candidate in candidates {
            if let matchedTag = VoiceLocaleResolver.resolveBestLocaleTag(
                candidates: [candidate],
                supportedLocaleTags: supportedTags
            ), let recognizer = SFSpeechRecognizer(locale: Locale(identifier: matchedTag)), recognizer.isAvailable {
                return recognizer
            }
            if let direct = SFSpeechRecognizer(locale: Locale(identifier: candidate)), direct.isAvailable {
                return direct
            }
        }

        if let defaultRecognizer = SFSpeechRecognizer(), defaultRecognizer.isAvailable {
            return defaultRecognizer
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
