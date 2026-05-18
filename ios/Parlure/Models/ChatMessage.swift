//
//  ChatMessage.swift
//  Parlure
//

import Foundation

struct ChatMessage: Identifiable, Hashable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date = Date()
}

struct PendingClarification: Equatable {
    let utterance: String
    let terms: [String]
    let recordingID: UUID

    static func resolvedTerms(utterance: String, detectedTerms: [String]) -> [String] {
        let clean = detectedTerms.map { GlossaryQualityValidator.normalized($0) }.filter { !$0.isEmpty }
        if !clean.isEmpty { return clean }
        let whole = GlossaryQualityValidator.normalized(utterance)
        return whole.isEmpty ? [] : [whole]
    }
}

enum ConversationMode: Equatable {
    case idle
    case recording
    case processing
    case clarifying
    case clarificationRecording
}
