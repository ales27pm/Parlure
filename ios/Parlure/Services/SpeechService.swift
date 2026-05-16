import Foundation
import Observation
import Speech
import AVFoundation

enum SpeechPermissionState: String { case unknown, granted, denied }
enum SpeechServiceError: LocalizedError { case busy, unavailable, denied(String), engine(String)
    var errorDescription: String? { switch self { case .busy: return "Enregistrement déjà actif."; case .unavailable: return "Reconnaissance indisponible."; case .denied(let s): return s; case .engine(let e): return e } }
}

@MainActor @Observable final class SpeechService: NSObject {
    private(set) var transcript = ""
    private(set) var finalTranscript = ""
    private(set) var isRecording = false
    private(set) var usesOnDeviceRecognition = false
    private(set) var recognizerLocale = "fr-CA"
    private(set) var audioLevel: Float = 0
    private(set) var micPermission: SpeechPermissionState = .unknown
    private(set) var speechPermission: SpeechPermissionState = .unknown

    private let audioEngine = AVAudioEngine(); private var request: SFSpeechAudioBufferRecognitionRequest?; private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?; private var maxTimer: Timer?; private var didAutoStop = false; private var lastVoiceAt = Date()

    private var recognizer: SFSpeechRecognizer? {
        if let r = SFSpeechRecognizer(locale: Locale(identifier: "fr-CA")) { recognizerLocale = "fr-CA"; return r }
        recognizerLocale = "fr-FR"; return SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    }

    func requestPermissions() async throws {
        let ss: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        speechPermission = ss == .authorized ? .granted : .denied
        let mic = await withCheckedContinuation { c in AVAudioApplication.requestRecordPermission { c.resume(returning: $0) } }
        micPermission = mic ? .granted : .denied
        guard ss == .authorized else { throw SpeechServiceError.denied("Permission reconnaissance vocale refusée") }
        guard mic else { throw SpeechServiceError.denied("Permission micro refusée") }
    }

    func start(silenceThresholdMs: Int = 1200, maxSeconds: Int = 30, onAutoStop: @escaping () -> Void) async throws {
        guard !isRecording else { throw SpeechServiceError.busy }
        try await requestPermissions(); cleanupRecognition()
        guard let recognizer, recognizer.isAvailable else { throw SpeechServiceError.unavailable }
        transcript = ""; finalTranscript = ""; didAutoStop = false
        let req = SFSpeechAudioBufferRecognitionRequest(); req.shouldReportPartialResults = true; req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition; usesOnDeviceRecognition = req.requiresOnDeviceRecognition; self.request = req
        try configureAudioSession()
        let input = audioEngine.inputNode; let format = input.outputFormat(forBus: 0); input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in self?.request?.append(buffer); self?.updateLevel(buffer) }
        audioEngine.prepare(); try audioEngine.start(); isRecording = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in Task { @MainActor in guard let self else { return }; if let t = result?.bestTranscription.formattedString { self.transcript = t; self.finalTranscript = t } } }
        maxTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(maxSeconds), repeats: false) { [weak self] _ in self?.handleAutoStop(onAutoStop) }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in guard let self, self.isRecording else { return }; if Date().timeIntervalSince(self.lastVoiceAt) * 1000 > Double(silenceThresholdMs) { self.handleAutoStop(onAutoStop) } }
    }
    func stop() { guard isRecording else { return }; isRecording = false; cleanupRecognition(); try? AVAudioSession.sharedInstance().setActive(false) }
    private func handleAutoStop(_ onAutoStop: @escaping () -> Void) { guard !didAutoStop else { return }; didAutoStop = true; stop(); onAutoStop() }
    private func cleanupRecognition() { silenceTimer?.invalidate(); maxTimer?.invalidate(); silenceTimer=nil; maxTimer=nil; task?.cancel(); task=nil; request?.endAudio(); request=nil; if audioEngine.isRunning { audioEngine.stop() }; audioEngine.inputNode.removeTap(onBus: 0) }
    private func updateLevel(_ buffer: AVAudioPCMBuffer) { guard let ch = buffer.floatChannelData?[0] else { return }; let f = Int(buffer.frameLength); guard f > 0 else { return }; var s: Float = 0; for i in 0..<f { s += ch[i]*ch[i] }; let rms = sqrt(s/Float(f)); audioLevel = (audioLevel * 0.7) + min(1,max(0,rms*10))*0.3; if audioLevel > 0.05 { lastVoiceAt = Date() } }
    private func configureAudioSession() throws { let sess = AVAudioSession.sharedInstance(); try sess.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers,.defaultToSpeaker]); try sess.setActive(true, options: .notifyOthersOnDeactivation) }
}
