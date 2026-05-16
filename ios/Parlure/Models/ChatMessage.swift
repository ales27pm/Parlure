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
}

enum ConversationMode: Equatable {
    case idle
    case recording
    case processing
    case clarifying
    case clarificationRecording
}
