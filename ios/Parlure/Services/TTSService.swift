//
//  TTSService.swift
//  Parlure
//

import Foundation
import AVFoundation

@MainActor
final class TTSService {
    static let shared = TTSService()
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String, locale: String = "fr-CA") {
        guard !text.isEmpty else { return }
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: locale) ?? AVSpeechSynthesisVoice(language: "fr-FR")
        utt.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utt.pitchMultiplier = 1.0
        synth.speak(utt)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }
}
