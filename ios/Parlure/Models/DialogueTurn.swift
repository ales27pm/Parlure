import Foundation
import SwiftData

enum OutputSource: String, Codable, CaseIterable {
    case foundationModels, heuristic, glossary, manual
}

enum ReviewStatus: String, Codable, CaseIterable {
    case pendingReview = "pending_review"
    case accepted
    case rejected
    case redacted
}

@Model
final class DialogueTurn {
    @Attribute(.unique) var id: UUID = UUID()
    var timestamp: Date = Date()
    var input: String = ""
    var output: String = ""
    var inputLocale: String = "fr-CA"
    var recognizerLocale: String = "fr-CA"
    var outputSourceRaw: String = OutputSource.heuristic.rawValue
    var glossaryHintUsed: Bool = false
    var audioFilename: String?
    var reviewStatusRaw: String = ReviewStatus.pendingReview.rawValue
    var containsPersonalData: Bool = true
    var consentForTraining: Bool = false
    var notes: String?

    var outputSource: OutputSource {
        get { OutputSource(rawValue: outputSourceRaw) ?? .heuristic }
        set { outputSourceRaw = newValue.rawValue }
    }

    var reviewStatus: ReviewStatus {
        get { ReviewStatus(rawValue: reviewStatusRaw) ?? .pendingReview }
        set { reviewStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        input: String,
        output: String,
        inputLocale: String = "fr-CA",
        recognizerLocale: String = "fr-CA",
        outputSource: OutputSource = .heuristic,
        glossaryHintUsed: Bool = false,
        audioFilename: String? = nil,
        reviewStatus: ReviewStatus = .pendingReview,
        containsPersonalData: Bool = true,
        consentForTraining: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.input = input
        self.output = output
        self.inputLocale = inputLocale
        self.recognizerLocale = recognizerLocale
        self.outputSourceRaw = outputSource.rawValue
        self.glossaryHintUsed = glossaryHintUsed
        self.audioFilename = audioFilename
        self.reviewStatusRaw = reviewStatus.rawValue
        self.containsPersonalData = containsPersonalData
        self.consentForTraining = consentForTraining
        self.notes = notes
    }
}
