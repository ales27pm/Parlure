import Foundation
import Observation
import Speech
import AVFoundation

enum SpeechPermissionState: String { case unknown, granted, denied }

enum SpeechServiceError: LocalizedError {
    case busy, unavailable, denied(String), engine(String)
    var errorDescription: String? {
        switch self {
        case .busy: return "Enregistrement déjà actif."
        case .unavailable: return "Reconnaissance vocale indisponible."
        case .denied(let msg): return msg
        case .engine(let msg): return "Erreur audio: \(msg)"
        }
    }
}

@MainActor
@Observable
final class SpeechService: NSObject {
    private(set) var transcript = ""
    private(set) var finalTranscript = ""
    private(set) var isRecording = false
    private(set) var usesOnDeviceRecognition = false
    private(set) var recognizerLocale = "fr-CA"
    private(set) var audioLevel: Float = 0
    private(set) var micPermission: SpeechPermissionState = .unknown
    private(set) var speechPermission: SpeechPermissionState = .unknown
    private(set) var hasDetectedSpeech = false

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var maxDurationTimer: Timer?
    private var lastVoiceAt: Date?
    private var recordingSessionID: UUID?
    private var isProcessingStop = false

    func requestPermissions() async throws {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        speechPermission = speechStatus == .authorized ? .granted : .denied

        let micAllowed = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        micPermission = micAllowed ? .granted : .denied

        guard speechStatus == .authorized else { throw SpeechServiceError.denied("Permission reconnaissance refusée") }
        guard micAllowed else { throw SpeechServiceError.denied("Permission micro refusée") }
    }

    func start(silenceThresholdMs: Int = 1200, maxSeconds: Int = 30, onAutoStop: @escaping (String) -> Void) async throws {
        guard !isRecording else { throw SpeechServiceError.busy }
        try await requestPermissions()
        let sessionID = UUID()
        recordingSessionID = sessionID
        isProcessingStop = false
        transcript = ""
        finalTranscript = ""
        hasDetectedSpeech = false
        lastVoiceAt = nil
        audioLevel = 0

        guard let recognizer = makeRecognizer(), recognizer.isAvailable else { throw SpeechServiceError.unavailable }

        try configureAudioSession()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        usesOnDeviceRecognition = request.requiresOnDeviceRecognition
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, request] buffer, _ in
            request.append(buffer)
            guard let self else { return }
            let level = Self.computeLevel(from: buffer)
            Task { @MainActor in
                self.applyAudioLevel(level, sessionID: sessionID)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            cleanupAudioAndRecognition()
            isRecording = false
            isProcessingStop = false
            throw SpeechServiceError.engine(error.localizedDescription)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.recordingSessionID == sessionID else { return }
                if let text = result?.bestTranscription.formattedString {
                    self.transcript = text
                    self.finalTranscript = text
                }
            }
        }

        isRecording = true
        scheduleTimers(sessionID: sessionID, silenceThresholdMs: silenceThresholdMs, maxSeconds: maxSeconds, onAutoStop: onAutoStop)
    }

    func stop() {
        _ = stopAndReturnTranscript()
    }

    func stopAndReturnTranscript() -> String {
        guard isRecording else { return finalLockedTranscript() }
        guard !isProcessingStop else { return finalLockedTranscript() }

        isProcessingStop = true
        let text = finalLockedTranscript()
        cleanupAudioAndRecognition()
        isRecording = false
        isProcessingStop = false
        return text
    }

    private func finalLockedTranscript() -> String {
        let candidate = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty { return candidate }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleTimers(sessionID: UUID, silenceThresholdMs: Int, maxSeconds: Int, onAutoStop: @escaping (String) -> Void) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleSilenceTick(sessionID: sessionID, silenceThresholdMs: silenceThresholdMs, onAutoStop: onAutoStop)
            }
        }

        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(maxSeconds), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleMaxDuration(sessionID: sessionID, onAutoStop: onAutoStop)
            }
        }
    }

    private func handleSilenceTick(sessionID: UUID, silenceThresholdMs: Int, onAutoStop: (String) -> Void) {
        guard recordingSessionID == sessionID, isRecording, !isProcessingStop else { return }
        guard hasDetectedSpeech, let lastVoiceAt else { return }
        let elapsedMs = Date().timeIntervalSince(lastVoiceAt) * 1000
        if elapsedMs >= Double(silenceThresholdMs) {
            let text = stopAndReturnTranscript()
            onAutoStop(text)
        }
    }

    private func handleMaxDuration(sessionID: UUID, onAutoStop: (String) -> Void) {
        guard recordingSessionID == sessionID, isRecording, !isProcessingStop else { return }
        let text = stopAndReturnTranscript()
        onAutoStop(text)
    }

    private func applyAudioLevel(_ level: Float, sessionID: UUID) {
        guard recordingSessionID == sessionID, isRecording else { return }
        audioLevel = (audioLevel * 0.65) + (level * 0.35)
        if level > 0.06 {
            hasDetectedSpeech = true
            lastVoiceAt = Date()
        }
    }

    private func makeRecognizer() -> SFSpeechRecognizer? {
        if let frCA = SFSpeechRecognizer(locale: Locale(identifier: "fr-CA")) {
            recognizerLocale = "fr-CA"
            return frCA
        }
        recognizerLocale = "fr-FR"
        return SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    }

    private func cleanupAudioAndRecognition() {
        silenceTimer?.invalidate(); silenceTimer = nil
        maxDurationTimer?.invalidate(); maxDurationTimer = nil

        recognitionTask?.cancel(); recognitionTask = nil
        recognitionRequest?.endAudio(); recognitionRequest = nil

        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        recordingSessionID = nil
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func computeLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frames))
        return min(1, max(0, rms * 10))
    }
}
