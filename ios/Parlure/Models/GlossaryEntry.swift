import Foundation
import SwiftData

enum GlossarySource: String, Codable, CaseIterable { case userClarification = "user_clarification", manual }

@Model
final class GlossaryEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var utterance: String
    var unclearTerms: [String]
    var explanation: String
    var region: String
    var sourceRaw: String
    var reviewStatusRaw: String
    var containsPersonalData: Bool
    var consentForTraining: Bool
    var notes: String?

    var source: GlossarySource { get { GlossarySource(rawValue: sourceRaw) ?? .userClarification } set { sourceRaw = newValue.rawValue } }
    var reviewStatus: ReviewStatus { get { ReviewStatus(rawValue: reviewStatusRaw) ?? .pendingReview } set { reviewStatusRaw = newValue.rawValue } }

    init(id: UUID = UUID(), timestamp: Date = Date(), utterance: String, unclearTerms: [String], explanation: String, region: String = "Québec", source: GlossarySource = .userClarification, reviewStatus: ReviewStatus = .pendingReview, containsPersonalData: Bool = true, consentForTraining: Bool = false, notes: String? = nil) {
        self.id = id; self.timestamp = timestamp; self.utterance = utterance; self.unclearTerms = unclearTerms; self.explanation = explanation; self.region = region
        self.sourceRaw = source.rawValue; self.reviewStatusRaw = reviewStatus.rawValue
        self.containsPersonalData = containsPersonalData; self.consentForTraining = consentForTraining; self.notes = notes
    }
}
