//
//  SpeechService.swift
//  Parlure
//
//  Live on-device speech recognition for Quebec French (fr-CA).
//

import Foundation
import Speech
import AVFoundation

enum SpeechServiceError: LocalizedError {
    case microphoneDenied
    case recognitionDenied
    case recognizerUnavailable
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access denied. Enable it in Settings."
        case .recognitionDenied: return "Speech recognition denied. Enable it in Settings."
        case .recognizerUnavailable: return "Quebec French recognizer is unavailable on this device."
        case .engineFailed(let msg): return "Audio engine failed: \(msg)"
        }
    }
}

@MainActor
@Observable
final class SpeechService: NSObject {
    private(set) var transcript: String = ""
    private(set) var isRecording: Bool = false
    private(set) var audioLevel: Float = 0 // 0...1 normalized
    private(set) var hasDetectedSpeech: Bool = false

    private let recognizer: SFSpeechRecognizer? = {
        // Prefer Quebec French; fall back to generic French
        SFSpeechRecognizer(locale: Locale(identifier: "fr-CA"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    }()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var silenceTimer: Timer?
    private var maxDurationTimer: Timer?
    private var lastSpeechAt: Date?
    private var onAutoStop: (() -> Void)?

    func requestPermissions() async throws {
        // Speech
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
        guard speechStatus == .authorized else { throw SpeechServiceError.recognitionDenied }

        // Microphone
        let mic: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { ok in cont.resume(returning: ok) }
        }
        guard mic else { throw SpeechServiceError.microphoneDenied }
    }

    func start(silenceThresholdMs: Int = 1200, maxSeconds: Int = 30, onAutoStop: @escaping () -> Void) async throws {
        guard !isRecording else { return }
        try await requestPermissions()
        guard let recognizer, recognizer.isAvailable else { throw SpeechServiceError.recognizerUnavailable }

        transcript = ""
        hasDetectedSpeech = false
        lastSpeechAt = nil
        self.onAutoStop = onAutoStop

        // Configure session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechServiceError.engineFailed(error.localizedDescription)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.process(buffer: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechServiceError.engineFailed(error.localizedDescription)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    // Recognition ended; engine cleanup happens on stop
                }
            }
        }

        isRecording = true

        // Max duration safeguard
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(maxSeconds), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.autoStop() }
        }

        // Silence checker
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording, let last = self.lastSpeechAt else { return }
                let elapsed = Date().timeIntervalSince(last) * 1000
                if self.hasDetectedSpeech && elapsed >= Double(silenceThresholdMs) {
                    self.autoStop()
                }
            }
        }
    }

    private func autoStop() {
        let cb = onAutoStop
        stop()
        cb?()
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        silenceTimer?.invalidate(); silenceTimer = nil
        maxDurationTimer?.invalidate(); maxDurationTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        audioLevel = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        for i in 0..<frames { let v = channelData[i]; sum += v * v }
        let rms = sqrt(sum / Float(frames))
        // Map RMS to 0...1 (rough)
        let normalized = min(1, max(0, rms * 8))
        Task { @MainActor in
            self.audioLevel = self.audioLevel * 0.6 + normalized * 0.4
            if normalized > 0.06 {
                self.hasDetectedSpeech = true
                self.lastSpeechAt = Date()
            } else if self.hasDetectedSpeech, self.lastSpeechAt == nil {
                self.lastSpeechAt = Date()
            } else if !self.hasDetectedSpeech {
                self.lastSpeechAt = Date() // start counting after first chunk
            }
        }
    }
}
