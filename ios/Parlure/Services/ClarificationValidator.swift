import Foundation

struct ClarificationValidationResult {
    let isValid: Bool
    let cleanedExplanation: String
}

enum ClarificationValidator {
    private static let fillerPhrases = ["oui", "c'est ça", "je sais pas", "comme"]
    private static let stopwords: Set<String> = ["je", "tu", "il", "elle", "on", "le", "la", "les", "un", "une", "des", "de", "du", "à", "a", "est", "c'est", "ça", "pis", "ben", "non", "oui", "pour", "avec", "que", "qui", "dans", "sur", "en", "d", "l"]

    static func validate(utterance: String, explanation: String) -> ClarificationValidationResult {
        let cleaned = explanation.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !cleaned.isEmpty else { return .init(isValid: false, cleanedExplanation: cleaned) }

        let lower = cleaned.lowercased()
        if fillerPhrases.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) {
            return .init(isValid: false, cleanedExplanation: cleaned)
        }

        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        let meaningful = words.filter { !stopwords.contains($0) && $0.count > 1 }
        guard meaningful.count >= 5 else { return .init(isValid: false, cleanedExplanation: cleaned) }

        let uniqueRatio = Double(Set(meaningful).count) / Double(max(meaningful.count, 1))
        guard uniqueRatio >= 0.55 else { return .init(isValid: false, cleanedExplanation: cleaned) }

        let utteranceTokens = Set(utterance.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init).filter { !stopwords.contains($0) })
        let explanationTokens = Set(meaningful)
        let novelty = explanationTokens.subtracting(utteranceTokens)
        guard novelty.count >= 2 else { return .init(isValid: false, cleanedExplanation: cleaned) }

        return .init(isValid: true, cleanedExplanation: cleaned)
    }
}
