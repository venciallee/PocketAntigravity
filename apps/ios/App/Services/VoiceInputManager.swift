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
/// Key engineering guarantees:
/// - **Zero-manual-switch automatic bilingual detection**: Resolves initial locale from conversation/draft
///   context, in-app `AppLanguage`, OS `Locale.preferredLanguages`, active & installed keyboards
///   (`UITextInputMode.activeInputModes`), and last auto-detected locale. Buffers up to 12s of PCM audio
///   so if the active recognizer produces silence/no-match or low-confidence/mismatched output, it
///   automatically switches/probes the alternate language (`zh-CN` <-> `en-US`) and replays the exact
///   buffered audio seamlessly.
/// - **First-tap cold-start reliability**: Strongly retains the active `SFSpeechRecognizer`, creates
///   `recognitionTask` before starting `AVAudioEngine`, installs audio observers *after* engine start,
///   recovers automatically from transient `.AVAudioEngineConfigurationChange` startup glitches instead
///   of silently stopping, settles briefly after first-time TCC permission dialogs, and retries once on
///   cold XPC cancellation (`203` / `301`).
/// - **Swift 6 strict concurrency safety**: Bridges every Objective-C callback (`SFSpeechRecognizer`,
///   `AVAudioInputNode.installTap`, `NotificationCenter`) through `nonisolated static` helpers and
///   lock-protected `@unchecked Sendable` containers so Swift 6 never asserts `@MainActor` on
///   Speech/CoreAudio realtime threads.
@MainActor
@Observable
public final class VoiceInputManager {
    private static let preferredLanguageDefaultsKey = "antigravity.voice.dictationLanguage"
    private static let lastDetectedLocaleDefaultsKey = "antigravity.voice.lastDetectedLocale"

    public var isRecording: Bool = false
    public var isStarting: Bool = false
    public var isRefining: Bool = false
    public var liveTranscript: String = ""
    public var errorMessage: String? = nil
    public var authorizationGranted: Bool = false
    public var preferredLanguage: VoiceDictationLanguage
    public var activeLocaleIdentifier: String? = nil
    public var lastDetectedLocaleIdentifier: String? = nil

    #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
    private var speechRecognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var hasInstalledTap: Bool = false
    private var activeRequestBox: AudioRequestBox?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioCaptureStore: AudioCaptureBuffer?
    private let observerBag = ObserverBag()
    private var isAudioSessionActive: Bool = false
    private var alternateLocaleIdentifier: String? = nil
    private var sessionStartedAt: Date? = nil
    private var hasSwitchedLiveToAlternate: Bool = false
    private var hasRetriedColdStart: Bool = false
    private var hasRecoveredAudioConfigChange: Bool = false
    private var latestConfidenceAvg: Double = 0.0
    private var latestHasPopulatedConfidence: Bool = false
    private var isFinalizingGracefully: Bool = false
    private var didReceiveFinalForGracefulStop: Bool = false
    private var activeRecognitionTaskToken: UUID = UUID()
    private var finalWaitContinuation: CheckedContinuation<Void, Never>? = nil
    private var watchdogTask: Task<Void, Never>? = nil
    private var refineTask: Task<Void, Never>? = nil
    #endif

    private var activeAppLanguage: AppLanguage = .english
    private var activeContextTextHint: String? = nil
    private var activeTranscriptCallback: (@MainActor (String) -> Void)? = nil
    private var startTask: Task<Void, Never>?
    private var recordingSessionToken: UUID = UUID()

    public init() {
        let savedRaw = UserDefaults.standard.string(forKey: Self.preferredLanguageDefaultsKey)
        self.preferredLanguage = VoiceDictationLanguage.fromTag(savedRaw)
        let savedDetected = UserDefaults.standard.string(forKey: Self.lastDetectedLocaleDefaultsKey)
        self.lastDetectedLocaleIdentifier = savedDetected?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? savedDetected
            : nil
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

    public func activeLanguageBadgeLabel(
        for appLanguage: AppLanguage,
        contextTextHint: String? = nil
    ) -> String {
        if preferredLanguage != .auto {
            return preferredLanguage.shortBadgeLabel(for: appLanguage)
        }
        let resolvedTag: String?
        if (isRecording || isStarting || isRefining), let activeLocaleIdentifier {
            resolvedTag = activeLocaleIdentifier
        } else {
            let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
                preference: preferredLanguage,
                appLanguage: appLanguage,
                systemPreferredLanguages: Locale.preferredLanguages,
                activeKeyboardLanguage: activeKeyboardPrimaryLanguage(),
                installedKeyboardLanguages: installedKeyboardLanguages(),
                contextTextHint: contextTextHint ?? activeContextTextHint,
                lastDetectedLocaleTag: lastDetectedLocaleIdentifier,
                fallbackLocaleTag: Locale.current.identifier
            )
            resolvedTag = candidates.first
        }
        let shortLang = VoiceLocaleResolver.shortDisplayLabel(forLocaleTag: resolvedTag)
        let autoPrefix = appLanguage.t("Auto", "自动")
        if shortLang == "Auto" {
            return autoPrefix
        }
        return "\(autoPrefix) · \(shortLang)"
    }

    public func selectLanguage(
        _ language: VoiceDictationLanguage,
        appLanguage: AppLanguage = .english,
        contextTextHint: String? = nil,
        restartOnTranscriptUpdate: (@MainActor (String) -> Void)? = nil
    ) {
        preferredLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.preferredLanguageDefaultsKey)
        activeLocaleIdentifier = language.bcp47Tag
        if (isRecording || isStarting || isRefining), let restartOnTranscriptUpdate {
            stopRecording()
            toggleRecording(
                appLanguage: appLanguage,
                contextTextHint: contextTextHint ?? activeContextTextHint,
                onTranscriptUpdate: restartOnTranscriptUpdate
            )
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    public func toggleRecording(
        appLanguage: AppLanguage = .english,
        contextTextHint: String? = nil,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void
    ) {
        if isRecording {
            #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
            finishRecordingGracefully()
            #else
            stopRecording()
            #endif
        } else if isStarting || isRefining {
            stopRecording()
        } else {
            let sessionToken = UUID()
            recordingSessionToken = sessionToken
            isStarting = true
            isRefining = false
            errorMessage = nil
            liveTranscript = ""
            activeAppLanguage = appLanguage
            activeContextTextHint = contextTextHint
            activeTranscriptCallback = onTranscriptUpdate
            startTask?.cancel()
            startTask = Task { @MainActor [weak self] in
                await self?.startRecordingInternal(
                    sessionToken: sessionToken,
                    appLanguage: appLanguage,
                    contextTextHint: contextTextHint,
                    onTranscriptUpdate: onTranscriptUpdate
                )
            }
        }
    }

    public func startRecording(
        appLanguage: AppLanguage = .english,
        contextTextHint: String? = nil,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void
    ) async {
        let sessionToken = UUID()
        recordingSessionToken = sessionToken
        isStarting = true
        isRefining = false
        errorMessage = nil
        liveTranscript = ""
        activeAppLanguage = appLanguage
        activeContextTextHint = contextTextHint
        activeTranscriptCallback = onTranscriptUpdate
        startTask?.cancel()
        startTask = nil
        await startRecordingInternal(
            sessionToken: sessionToken,
            appLanguage: appLanguage,
            contextTextHint: contextTextHint,
            onTranscriptUpdate: onTranscriptUpdate
        )
    }

    private func startRecordingInternal(
        sessionToken: UUID,
        appLanguage: AppLanguage,
        contextTextHint: String?,
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

        let speechWasUndetermined = SFSpeechRecognizer.authorizationStatus() == .notDetermined
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

        let micWasUndetermined = AVAudioApplication.shared.recordPermission == .undetermined
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

        // Allow SpringBoard ~180ms to settle foreground audio focus immediately after first-time TCC
        // permission dialogs dismiss so AVAudioSession.setActive(true) never races with dismissal.
        if speechWasUndetermined || micWasUndetermined {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, recordingSessionToken == sessionToken else {
                return
            }
        }

        tearDownActiveAudio()

        let keyboardLang = activeKeyboardPrimaryLanguage()
        let installedKeyboards = installedKeyboardLanguages()
        let resolution = Self.resolveSpeechRecognizerPair(
            preference: preferredLanguage,
            appLanguage: appLanguage,
            activeKeyboardLanguage: keyboardLang,
            installedKeyboardLanguages: installedKeyboards,
            contextTextHint: contextTextHint,
            lastDetectedLocaleTag: lastDetectedLocaleIdentifier
        )
        guard let recognizer = resolution.primary, recognizer.isAvailable else {
            errorMessage = appLanguage.t(
                "Speech recognizer is temporarily unavailable on this device.",
                "当前设备的语音识别服务暂不可用。"
            )
            return
        }

        self.speechRecognizer = recognizer
        self.activeLocaleIdentifier = recognizer.locale.identifier
        self.alternateLocaleIdentifier = (preferredLanguage == .auto) ? resolution.alternateLocaleIdentifier : nil
        self.hasSwitchedLiveToAlternate = false
        self.hasRetriedColdStart = false
        self.hasRecoveredAudioConfigChange = false
        self.latestConfidenceAvg = 0.0
        self.latestHasPopulatedConfidence = false
        self.isFinalizingGracefully = false

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
            let captureStore = AudioCaptureBuffer(initialRequestBox: requestBox)

            self.audioEngine = engine
            self.activeRequestBox = requestBox
            self.audioCaptureStore = captureStore
            self.sessionStartedAt = Date()

            // Start recognition task BEFORE engine.prepare()/start() (Apple SpokenWord order)
            // so cold assistantd XPC connections are warm before the first PCM buffers arrive.
            startRecognitionTaskLocked(
                recognizer: recognizer,
                request: request,
                sessionToken: sessionToken,
                appLanguage: appLanguage,
                onTranscriptUpdate: onTranscriptUpdate
            )

            Self.installRealtimeAudioTap(
                on: inputNode,
                captureStore: captureStore
            )
            self.hasInstalledTap = true

            engine.prepare()
            try engine.start()

            guard !Task.isCancelled, recordingSessionToken == sessionToken else {
                tearDownActiveAudio()
                return
            }

            // Install audio session & engine observers AFTER engine.start() succeeds so cold-start
            // audio hardware bring-up never triggers a spurious self-cancellation on tap #1.
            observerBag.installAudioObservers(
                engine: engine,
                onInterruptionBegan: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, self.recordingSessionToken == sessionToken else { return }
                        self.stopRecording()
                    }
                },
                onConfigurationChanged: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, self.recordingSessionToken == sessionToken else { return }
                        self.handleAudioEngineConfigurationChange(sessionToken: sessionToken)
                    }
                }
            )

            isRecording = true

            if preferredLanguage == .auto, alternateLocaleIdentifier != nil {
                startAutoDetectWatchdog(
                    sessionToken: sessionToken,
                    appLanguage: appLanguage,
                    onTranscriptUpdate: onTranscriptUpdate
                )
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
        isRefining = false
        activeTranscriptCallback = nil
        tearDownActiveAudio()
        isRecording = false
    }

    #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
    private func startRecognitionTaskLocked(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        sessionToken: UUID,
        appLanguage: AppLanguage,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void
    ) {
        let taskToken = UUID()
        activeRecognitionTaskToken = taskToken
        recognitionTask = Self.startRecognitionTask(
            recognizer: recognizer,
            request: request
        ) { [weak self] text, isFinal, avgConfidence, hasPopulatedConfidence, errorCode, errDesc in
            Task { @MainActor [weak self] in
                guard let self,
                      self.recordingSessionToken == sessionToken,
                      self.activeRecognitionTaskToken == taskToken else {
                    return
                }

                if let text, !text.isEmpty {
                    self.liveTranscript = text
                    if hasPopulatedConfidence {
                        self.latestConfidenceAvg = avgConfidence
                        self.latestHasPopulatedConfidence = true
                    }
                    onTranscriptUpdate(text)
                }

                if isFinal {
                    if self.isFinalizingGracefully {
                        self.didReceiveFinalForGracefulStop = true
                        self.resumeFinalWaitContinuationIfNeeded()
                        return
                    }
                    // Natural end-of-utterance finalization while user is still recording
                    self.finishRecordingGracefully(alreadyReceivedFinal: true)
                    return
                }

                if let errDesc {
                    if self.isFinalizingGracefully {
                        self.didReceiveFinalForGracefulStop = true
                        self.resumeFinalWaitContinuationIfNeeded()
                        return
                    }

                    let activeSpeechMs = self.audioCaptureStore?.currentActiveSpeechMs() ?? 0
                    let elapsedSinceStart = Date().timeIntervalSince(self.sessionStartedAt ?? Date())

                    // 1. Cold-start transient XPC error (203/301) before speech settles -> retry once seamlessly.
                    if (errorCode == 203 || errorCode == 301),
                       elapsedSinceStart < 1.2,
                       self.liveTranscript.isEmpty,
                       activeSpeechMs < 400,
                       !self.hasRetriedColdStart,
                       self.isRecording {
                        self.hasRetriedColdStart = true
                        self.retryRecognitionTaskOnRunningEngine(
                            sessionToken: sessionToken,
                            appLanguage: appLanguage,
                            onTranscriptUpdate: onTranscriptUpdate
                        )
                        return
                    }

                    // 2. Premature no-match/retry error while user actually spoke -> switch live to alternate language!
                    if (errorCode == 1110 || errorCode == 203),
                       self.preferredLanguage == .auto,
                       !self.hasSwitchedLiveToAlternate,
                       self.alternateLocaleIdentifier != nil,
                       self.liveTranscript.isEmpty,
                       activeSpeechMs >= 450,
                       self.isRecording {
                        let switched = self.switchLiveSessionToAlternate(
                            sessionToken: sessionToken,
                            appLanguage: appLanguage,
                            onTranscriptUpdate: onTranscriptUpdate
                        )
                        if switched {
                            return
                        }
                    }

                    let hadTranscript = !self.liveTranscript.isEmpty
                    if hadTranscript {
                        self.finishRecordingGracefully(alreadyReceivedFinal: true)
                    } else {
                        self.stopRecording()
                        if !Self.isBenignCancellationError(code: errorCode) {
                            self.errorMessage = appLanguage.t(
                                "Voice recognition stopped: \(errDesc)",
                                "语音识别已停止：\(errDesc)"
                            )
                        }
                    }
                }
            }
        }
    }

    private func retryRecognitionTaskOnRunningEngine(
        sessionToken: UUID,
        appLanguage: AppLanguage,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void
    ) {
        guard recordingSessionToken == sessionToken,
              let recognizer = speechRecognizer,
              recognizer.isAvailable,
              let captureStore = audioCaptureStore else {
            return
        }
        recognitionTask?.cancel()
        recognitionTask = nil

        let retryRequest = SFSpeechAudioBufferRecognitionRequest()
        retryRequest.shouldReportPartialResults = true
        retryRequest.taskHint = .dictation
        retryRequest.addsPunctuation = true
        let retryBox = AudioRequestBox(retryRequest)
        activeRequestBox = retryBox

        startRecognitionTaskLocked(
            recognizer: recognizer,
            request: retryRequest,
            sessionToken: sessionToken,
            appLanguage: appLanguage,
            onTranscriptUpdate: onTranscriptUpdate
        )
        captureStore.swapLiveRequestAndReplay(retryBox)
    }

    private func handleAudioEngineConfigurationChange(sessionToken: UUID) {
        guard recordingSessionToken == sessionToken,
              isRecording,
              !isFinalizingGracefully,
              let engine = audioEngine,
              let captureStore = audioCaptureStore else {
            return
        }
        // Ignore harmless configuration change notifications when the engine is still capturing cleanly.
        if engine.isRunning {
            return
        }
        guard !hasRecoveredAudioConfigChange else {
            finishRecordingGracefully()
            return
        }
        hasRecoveredAudioConfigChange = true

        let inputNode = engine.inputNode
        if hasInstalledTap {
            inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        let outputFormat = inputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0,
              hardwareFormat.channelCount > 0,
              outputFormat.sampleRate > 0,
              outputFormat.channelCount > 0 else {
            finishRecordingGracefully()
            return
        }

        Self.installRealtimeAudioTap(on: inputNode, captureStore: captureStore)
        hasInstalledTap = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            finishRecordingGracefully()
        }
    }

    private func startAutoDetectWatchdog(
        sessionToken: UUID,
        appLanguage: AppLanguage,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void
    ) {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled,
                      let self,
                      self.recordingSessionToken == sessionToken,
                      self.isRecording,
                      !self.isFinalizingGracefully,
                      !self.hasSwitchedLiveToAlternate,
                      let altLocale = self.alternateLocaleIdentifier else {
                    return
                }
                let activeSpeechMs = self.audioCaptureStore?.currentActiveSpeechMs() ?? 0
                let currentLocale = self.activeLocaleIdentifier ?? "en-US"
                let primaryCandidate = VoiceTranscriptCandidate(
                    localeTag: currentLocale,
                    text: self.liveTranscript,
                    averageConfidence: self.latestConfidenceAvg,
                    hasPopulatedConfidence: self.latestHasPopulatedConfidence
                )
                if VoiceLocaleResolver.shouldProbeAlternateLocale(
                    primary: primaryCandidate,
                    alternateLocaleTag: altLocale,
                    activeSpeechDurationMs: activeSpeechMs,
                    isFinal: false
                ) {
                    _ = self.switchLiveSessionToAlternate(
                        sessionToken: sessionToken,
                        appLanguage: appLanguage,
                        onTranscriptUpdate: onTranscriptUpdate
                    )
                    return
                }
            }
        }
    }

    @discardableResult
    private func switchLiveSessionToAlternate(
        sessionToken: UUID,
        appLanguage: AppLanguage,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void
    ) -> Bool {
        guard recordingSessionToken == sessionToken,
              !hasSwitchedLiveToAlternate,
              let altLocale = alternateLocaleIdentifier,
              let altRecognizer = SFSpeechRecognizer(locale: Locale(identifier: altLocale)),
              altRecognizer.isAvailable,
              let captureStore = audioCaptureStore else {
            return false
        }

        hasSwitchedLiveToAlternate = true
        watchdogTask?.cancel()
        watchdogTask = nil

        let oldTask = recognitionTask
        recognitionTask = nil

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.taskHint = .dictation
        newRequest.addsPunctuation = true
        let newBox = AudioRequestBox(newRequest)

        self.speechRecognizer = altRecognizer
        self.activeLocaleIdentifier = altRecognizer.locale.identifier
        self.activeRequestBox = newBox
        self.liveTranscript = ""
        self.latestConfidenceAvg = 0.0
        self.latestHasPopulatedConfidence = false

        startRecognitionTaskLocked(
            recognizer: altRecognizer,
            request: newRequest,
            sessionToken: sessionToken,
            appLanguage: appLanguage,
            onTranscriptUpdate: onTranscriptUpdate
        )
        captureStore.swapLiveRequestAndReplay(newBox)
        oldTask?.cancel()
        rememberDetectedLocale(altRecognizer.locale.identifier)
        return true
    }

    /// Stops microphone capture immediately while letting `SFSpeechRecognizer` flush final words
    /// and (in `.auto` mode) verifying against the alternate language using buffered PCM if needed.
    private func finishRecordingGracefully(alreadyReceivedFinal: Bool = false) {
        let sessionToken = recordingSessionToken
        guard !isFinalizingGracefully else { return }
        isFinalizingGracefully = true
        didReceiveFinalForGracefulStop = alreadyReceivedFinal
        isRecording = false
        isStarting = false
        watchdogTask?.cancel()
        watchdogTask = nil

        // Stop mic hardware immediately so the iOS orange mic dot turns off right away.
        stopAudioCaptureEngineOnly()

        let capturedLocale = activeLocaleIdentifier ?? "en-US"
        let altLocale = alternateLocaleIdentifier
        let allowAutoProbe = (preferredLanguage == .auto && !hasSwitchedLiveToAlternate && altLocale != nil)
        let callback = activeTranscriptCallback
        let captureSnapshot: (buffers: [AVAudioPCMBuffer], activeSpeechMs: Int) =
            audioCaptureStore?.snapshotBuffersForOfflineProbe() ?? (buffers: [], activeSpeechMs: 0)

        activeRequestBox?.finish()
        activeRequestBox = nil

        refineTask?.cancel()
        refineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.recordingSessionToken == sessionToken {
                    self.isRefining = false
                    self.isFinalizingGracefully = false
                    self.didReceiveFinalForGracefulStop = false
                    self.cleanUpRecognitionObjectsOnly()
                }
            }

            if !self.didReceiveFinalForGracefulStop, self.recognitionTask != nil {
                let waitTimeout = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    self?.resumeFinalWaitContinuationIfNeeded()
                }
                await withCheckedContinuation { continuation in
                    if self.didReceiveFinalForGracefulStop {
                        continuation.resume()
                    } else {
                        self.finalWaitContinuation = continuation
                    }
                }
                waitTimeout.cancel()
            }

            guard !Task.isCancelled, self.recordingSessionToken == sessionToken else { return }

            self.recognitionTask?.cancel()
            self.recognitionTask = nil

            let primaryCandidate = VoiceTranscriptCandidate(
                localeTag: capturedLocale,
                text: self.liveTranscript,
                averageConfidence: self.latestConfidenceAvg,
                hasPopulatedConfidence: self.latestHasPopulatedConfidence
            )

            if allowAutoProbe,
               let altLocale,
               !captureSnapshot.buffers.isEmpty,
               VoiceLocaleResolver.shouldProbeAlternateLocale(
                   primary: primaryCandidate,
                   alternateLocaleTag: altLocale,
                   activeSpeechDurationMs: captureSnapshot.activeSpeechMs,
                   isFinal: true
               ) {
                self.isRefining = true
                let alternateCandidate = await self.runOfflineAlternateProbe(
                    localeIdentifier: altLocale,
                    buffers: captureSnapshot.buffers
                )
                guard !Task.isCancelled, self.recordingSessionToken == sessionToken else { return }
                self.isRefining = false

                if let alternateCandidate {
                    let winner = VoiceLocaleResolver.chooseBetterAutoDetectTranscript(
                        primary: primaryCandidate,
                        alternate: alternateCandidate
                    )
                    let trimmedWinner = winner.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedWinner.isEmpty {
                        self.rememberDetectedLocale(
                            fromTranscript: trimmedWinner,
                            activeLocale: winner.localeTag
                        )
                        if winner.localeTag == alternateCandidate.localeTag {
                            self.liveTranscript = trimmedWinner
                            self.activeLocaleIdentifier = winner.localeTag
                            callback?(trimmedWinner)
                        }
                    }
                    return
                }
            }

            let finalText = primaryCandidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalText.isEmpty {
                self.rememberDetectedLocale(fromTranscript: finalText, activeLocale: capturedLocale)
            }
        }
    }

    private func runOfflineAlternateProbe(
        localeIdentifier: String,
        buffers: [AVAudioPCMBuffer]
    ) async -> VoiceTranscriptCandidate? {
        guard !buffers.isEmpty,
              let probeRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              probeRecognizer.isAvailable else {
            return nil
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.addsPunctuation = true
        for buffer in buffers {
            request.append(buffer)
        }
        request.endAudio()

        let taskBox = ProbeTaskBox()
        let resolved = OSAllocatedUnfairLock(initialState: false)
        defer {
            taskBox.cancel()
            _ = probeRecognizer
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let finishOnce: @Sendable (VoiceTranscriptCandidate?) -> Void = { candidate in
                    let shouldResume = resolved.withLock { already -> Bool in
                        if already { return false }
                        already = true
                        return true
                    }
                    if shouldResume {
                        continuation.resume(returning: candidate)
                    }
                }

                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    taskBox.cancel()
                    finishOnce(nil)
                }

                let task = Self.startRecognitionTask(
                    recognizer: probeRecognizer,
                    request: request
                ) { text, isFinal, avgConfidence, hasPopulatedConfidence, _, errDesc in
                    if isFinal {
                        timeoutTask.cancel()
                        finishOnce(
                            VoiceTranscriptCandidate(
                                localeTag: localeIdentifier,
                                text: text ?? "",
                                averageConfidence: avgConfidence,
                                hasPopulatedConfidence: hasPopulatedConfidence
                            )
                        )
                    } else if errDesc != nil {
                        timeoutTask.cancel()
                        finishOnce(nil)
                    }
                }
                taskBox.set(task)
            }
        } onCancel: {
            taskBox.cancel()
        }
    }

    private func resumeFinalWaitContinuationIfNeeded() {
        if let continuation = finalWaitContinuation {
            finalWaitContinuation = nil
            continuation.resume()
        }
    }

    private func stopAudioCaptureEngineOnly() {
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
        if isAudioSessionActive {
            isAudioSessionActive = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func cleanUpRecognitionObjectsOnly() {
        resumeFinalWaitContinuationIfNeeded()
        activeRequestBox?.finish()
        activeRequestBox = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        audioCaptureStore?.clear()
        audioCaptureStore = nil
        speechRecognizer = nil
        alternateLocaleIdentifier = nil
        sessionStartedAt = nil
    }
    #endif

    private func tearDownActiveAudio() {
        #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
        watchdogTask?.cancel()
        watchdogTask = nil
        refineTask?.cancel()
        refineTask = nil
        isFinalizingGracefully = false
        stopAudioCaptureEngineOnly()
        cleanUpRecognitionObjectsOnly()
        #endif
    }

    private func rememberDetectedLocale(_ localeTag: String) {
        let trimmed = localeTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastDetectedLocaleIdentifier = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.lastDetectedLocaleDefaultsKey)
    }

    private func rememberDetectedLocale(fromTranscript text: String, activeLocale: String) {
        if let inferred = VoiceLocaleResolver.inferLocaleTag(fromText: text) {
            // Preserve regional Chinese variant (e.g. zh-TW/zh-HK) when active locale is already Chinese
            let activeNorm = activeLocale.replacingOccurrences(of: "_", with: "-").lowercased()
            if inferred.hasPrefix("zh") && (activeNorm.hasPrefix("zh") || activeNorm.hasPrefix("yue")) {
                rememberDetectedLocale(activeLocale)
            } else {
                rememberDetectedLocale(inferred)
            }
        } else {
            rememberDetectedLocale(activeLocale)
        }
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

    private func installedKeyboardLanguages() -> [String] {
        #if canImport(UIKit) && os(iOS)
        return UITextInputMode.activeInputModes
            .compactMap(\.primaryLanguage)
            .filter { lang in
                let lower = lang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !lower.isEmpty && lower != "dictation" && lower != "emoji"
            }
        #else
        return []
        #endif
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

    private final class ProbeTaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: SFSpeechRecognitionTask?
        private var isCancelled = false

        func set(_ newTask: SFSpeechRecognitionTask) {
            lock.lock()
            let alreadyCancelled = isCancelled
            task = alreadyCancelled ? nil : newTask
            lock.unlock()
            if alreadyCancelled {
                newTask.cancel()
            }
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            let current = task
            task = nil
            lock.unlock()
            current?.cancel()
        }
    }

    private final class AudioCaptureBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var currentRequestBox: AudioRequestBox?
        private var buffers: [AVAudioPCMBuffer] = []
        private var bufferedDurationSeconds: Double = 0.0
        private var activeSpeechDurationSeconds: Double = 0.0
        private let maxBufferedSeconds: Double = 12.0
        private let speechRmsThreshold: Double = 0.015

        init(initialRequestBox: AudioRequestBox) {
            self.currentRequestBox = initialRequestBox
        }

        func appendFromAudioTap(_ buffer: AVAudioPCMBuffer) {
            let sampleRate = buffer.format.sampleRate
            let frameDuration = sampleRate > 0 ? Double(buffer.frameLength) / sampleRate : 0.0
            let rms = Self.computeBufferRMS(buffer)

            lock.lock()
            let targetBox = currentRequestBox
            if rms >= speechRmsThreshold && frameDuration > 0 {
                activeSpeechDurationSeconds += frameDuration
            }
            if bufferedDurationSeconds < maxBufferedSeconds && frameDuration > 0,
               let copied = Self.copyPCMBuffer(buffer) {
                buffers.append(copied)
                bufferedDurationSeconds += frameDuration
            }
            lock.unlock()

            targetBox?.append(buffer)
        }

        func currentActiveSpeechMs() -> Int {
            lock.lock()
            let seconds = activeSpeechDurationSeconds
            lock.unlock()
            return Int(seconds * 1000.0)
        }

        func swapLiveRequestAndReplay(_ newRequestBox: AudioRequestBox) {
            lock.lock()
            let oldBox = currentRequestBox
            currentRequestBox = newRequestBox
            let snapshot = buffers
            lock.unlock()

            oldBox?.finish()
            for buf in snapshot {
                newRequestBox.append(buf)
            }
        }

        func snapshotBuffersForOfflineProbe() -> (buffers: [AVAudioPCMBuffer], activeSpeechMs: Int) {
            lock.lock()
            let snapshot = buffers
            let speechMs = Int(activeSpeechDurationSeconds * 1000.0)
            lock.unlock()
            return (snapshot, speechMs)
        }

        func clear() {
            lock.lock()
            currentRequestBox = nil
            buffers.removeAll()
            bufferedDurationSeconds = 0.0
            activeSpeechDurationSeconds = 0.0
            lock.unlock()
        }

        private static func computeBufferRMS(_ buffer: AVAudioPCMBuffer) -> Double {
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return 0.0 }
            let step = max(1, frameCount / 256)
            var sumSquares: Double = 0.0
            var count = 0
            if let floatData = buffer.floatChannelData {
                let channel = floatData[0]
                var i = 0
                while i < frameCount {
                    let s = Double(channel[i])
                    sumSquares += s * s
                    count += 1
                    i += step
                }
            } else if let int16Data = buffer.int16ChannelData {
                let channel = int16Data[0]
                var i = 0
                while i < frameCount {
                    let s = Double(channel[i]) / 32768.0
                    sumSquares += s * s
                    count += 1
                    i += step
                }
            }
            guard count > 0 else { return 0.0 }
            return sqrt(sumSquares / Double(count))
        }

        private static func copyPCMBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            let frameLength = source.frameLength
            guard frameLength > 0,
                  let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: frameLength) else {
                return nil
            }
            copy.frameLength = frameLength
            let channelCount = Int(source.format.channelCount)
            let frameCount = Int(frameLength)
            if let srcFloat = source.floatChannelData, let dstFloat = copy.floatChannelData {
                let byteCount = frameCount * MemoryLayout<Float>.size
                for ch in 0..<channelCount {
                    memcpy(dstFloat[ch], srcFloat[ch], byteCount)
                }
                return copy
            }
            if let srcInt16 = source.int16ChannelData, let dstInt16 = copy.int16ChannelData {
                let byteCount = frameCount * MemoryLayout<Int16>.size
                for ch in 0..<channelCount {
                    memcpy(dstInt16[ch], srcInt16[ch], byteCount)
                }
                return copy
            }
            if let srcInt32 = source.int32ChannelData, let dstInt32 = copy.int32ChannelData {
                let byteCount = frameCount * MemoryLayout<Int32>.size
                for ch in 0..<channelCount {
                    memcpy(dstInt32[ch], srcInt32[ch], byteCount)
                }
                return copy
            }
            return nil
        }
    }

    private final class ObserverBag: @unchecked Sendable {
        private let lock = NSLock()
        private var tokens: [NSObjectProtocol] = []

        func installAudioObservers(
            engine: AVAudioEngine,
            onInterruptionBegan: @escaping @Sendable () -> Void,
            onConfigurationChanged: @escaping @Sendable () -> Void
        ) {
            let interruption = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if rawType == AVAudioSession.InterruptionType.began.rawValue {
                    onInterruptionBegan()
                }
            }
            let configChange = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { _ in
                onConfigurationChanged()
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

    private nonisolated static func resolveSpeechRecognizerPair(
        preference: VoiceDictationLanguage,
        appLanguage: AppLanguage,
        activeKeyboardLanguage: String?,
        installedKeyboardLanguages: [String],
        contextTextHint: String?,
        lastDetectedLocaleTag: String?
    ) -> (primary: SFSpeechRecognizer?, alternateLocaleIdentifier: String?) {
        let candidates = VoiceLocaleResolver.buildCandidateLocaleTags(
            preference: preference,
            appLanguage: appLanguage,
            systemPreferredLanguages: Locale.preferredLanguages,
            activeKeyboardLanguage: activeKeyboardLanguage,
            installedKeyboardLanguages: installedKeyboardLanguages,
            contextTextHint: contextTextHint,
            lastDetectedLocaleTag: lastDetectedLocaleTag,
            fallbackLocaleTag: Locale.current.identifier
        )
        let supportedTags = Set(SFSpeechRecognizer.supportedLocales().map(\.identifier))

        var primaryRecognizer: SFSpeechRecognizer? = nil
        if let bestSupported = VoiceLocaleResolver.resolveBestLocaleTag(
            candidates: candidates,
            supportedLocaleTags: supportedTags
        ), let recognizer = SFSpeechRecognizer(locale: Locale(identifier: bestSupported)), recognizer.isAvailable {
            primaryRecognizer = recognizer
        }

        if primaryRecognizer == nil {
            for candidate in candidates {
                if let matchedTag = VoiceLocaleResolver.resolveBestLocaleTag(
                    candidates: [candidate],
                    supportedLocaleTags: supportedTags
                ), let recognizer = SFSpeechRecognizer(locale: Locale(identifier: matchedTag)), recognizer.isAvailable {
                    primaryRecognizer = recognizer
                    break
                }
                if let direct = SFSpeechRecognizer(locale: Locale(identifier: candidate)), direct.isAvailable {
                    primaryRecognizer = direct
                    break
                }
            }
        }

        if primaryRecognizer == nil,
           let defaultRecognizer = SFSpeechRecognizer(),
           defaultRecognizer.isAvailable {
            primaryRecognizer = defaultRecognizer
        }

        guard let primary = primaryRecognizer else {
            return (nil, nil)
        }

        let allowedAutoLocales = VoiceLocaleResolver.buildAutoDetectionAllowedLocales(
            candidates: candidates,
            includeBilingualFallback: true,
            maxCount: 3
        )
        let primaryLangPrefix = primary.locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map { String($0).lowercased() } ?? ""

        var alternateLocaleId: String? = nil
        for altCandidate in allowedAutoLocales {
            let altLangPrefix = altCandidate
                .replacingOccurrences(of: "_", with: "-")
                .split(separator: "-")
                .first
                .map { String($0).lowercased() } ?? ""
            guard !altLangPrefix.isEmpty, altLangPrefix != primaryLangPrefix else { continue }
            if let matchedSupported = VoiceLocaleResolver.resolveBestLocaleTag(
                candidates: [altCandidate],
                supportedLocaleTags: supportedTags
            ), let probe = SFSpeechRecognizer(locale: Locale(identifier: matchedSupported)), probe.isAvailable {
                alternateLocaleId = probe.locale.identifier
                break
            }
        }

        return (primary, alternateLocaleId)
    }

    private nonisolated static func installRealtimeAudioTap(
        on inputNode: AVAudioInputNode,
        captureStore: AudioCaptureBuffer
    ) {
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            captureStore.appendFromAudioTap(buffer)
        }
    }

    private nonisolated static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onEvent: @escaping @Sendable (
            _ transcript: String?,
            _ isFinal: Bool,
            _ averageConfidence: Double,
            _ hasPopulatedConfidence: Bool,
            _ errorCode: Int?,
            _ errorDescription: String?
        ) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let segments = result?.bestTranscription.segments ?? []
            let positiveConfidences = segments.map(\.confidence).filter { $0 > 0 }
            let hasPopulatedConfidence = !positiveConfidences.isEmpty
            let avgConfidence: Double = hasPopulatedConfidence
                ? Double(positiveConfidences.reduce(0, +)) / Double(positiveConfidences.count)
                : 0.0
            let nsError = error as NSError?
            onEvent(text, isFinal, avgConfidence, hasPopulatedConfidence, nsError?.code, nsError?.localizedDescription)
        }
    }

    private nonisolated static func isBenignCancellationError(code: Int?) -> Bool {
        guard let code else { return false }
        // 203: retry/cancel, 216: request canceled, 301: recognition request canceled, 1110: no speech detected
        return code == 203 || code == 216 || code == 301 || code == 1110
    }
    #endif
}
