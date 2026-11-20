import Foundation
import Observation
#if canImport(Speech)
import Speech
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Native iOS live speech-to-text manager powered by `SFSpeechRecognizer` and `AVAudioEngine`.
/// Bridges real microphone dictation into `ChatComposerView` and `VoiceModeSheetView`.
@MainActor
@Observable
public final class VoiceInputManager {
    public var isRecording: Bool = false
    public var liveTranscript: String = ""
    public var errorMessage: String? = nil
    public var authorizationGranted: Bool = false

    #if canImport(Speech) && canImport(AVFoundation)
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    #endif

    public init() {}

    public func toggleRecording(onTranscriptUpdate: @escaping @MainActor (String) -> Void) {
        if isRecording {
            stopRecording()
        } else {
            Task {
                await startRecording(onTranscriptUpdate: onTranscriptUpdate)
            }
        }
    }

    public func startRecording(onTranscriptUpdate: @escaping @MainActor (String) -> Void) async {
        errorMessage = nil
        #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            authorizationGranted = false
            errorMessage = "Enable Speech Recognition in Settings to dictate prompts."
            return
        }

        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard micAllowed else {
            authorizationGranted = false
            errorMessage = "Enable Microphone access in Settings to dictate prompts."
            return
        }
        authorizationGranted = true

        stopRecording()

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            errorMessage = "Speech recognizer is temporarily unavailable on this device."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            Self.installRealtimeAudioTap(
                on: inputNode,
                format: recordingFormat,
                requestBox: AudioRequestBox(request)
            )

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let errDesc = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let text, !text.isEmpty {
                        self.liveTranscript = text
                        onTranscriptUpdate(text)
                    }
                    if isFinal || errDesc != nil {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            errorMessage = "Unable to start microphone capture: \(error.localizedDescription)"
            stopRecording()
        }
        #else
        errorMessage = "Speech dictation requires an iOS device with microphone access."
        #endif
    }

    public func stopRecording() {
        #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        isRecording = false
    }

    #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
    private final class AudioRequestBox: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        init(_ request: SFSpeechAudioBufferRecognitionRequest) {
            self.request = request
        }
    }

    private nonisolated static func installRealtimeAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        requestBox: AudioRequestBox
    ) {
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            requestBox.request.append(buffer)
        }
    }
    #endif
}
