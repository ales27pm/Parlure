//
//  GlossaryEntry.swift
//  Parlure
//

import Foundation
import SwiftData

@Model
final class GlossaryEntry {
    var timestamp: Date
    var utterance: String
    var unclearTerms: [String]
    var explanation: String
    var region: String

    init(timestamp: Date = Date(), utterance: String, unclearTerms: [String], explanation: String, region: String = "Québec") {
        self.timestamp = timestamp
        self.utterance = utterance
        self.unclearTerms = unclearTerms
        self.explanation = explanation
        self.region = region
    }
}
