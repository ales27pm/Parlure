import Foundation

struct GlossaryQualityValidationResult {
    let isValid: Bool
    let cleanedUtterance: String
    let cleanedExplanation: String
    let cleanedTerms: [String]
    let weakExplanation: Bool
    let staleTermsDetected: Bool
}

enum GlossaryQualityValidator {
    nonisolated private static let weakExact = ["oui c'est ça", "je sais pas", "boire de l'alcool jusqu'à être sous"]
    nonisolated private static let dangling = ["donc", "jusqu'à", "parce que", "pis"]

    nonisolated static func validate(utterance: String, explanation: String, unclearTerms: [String], detectedTerms: [String]) -> GlossaryQualityValidationResult {
        let cleanUtterance = normalized(utterance)
        let cleanExplanation = normalized(explanation)
        let cleanTerms = unclearTerms.map(normalized).filter { !$0.isEmpty }

        guard !cleanUtterance.isEmpty, !cleanExplanation.isEmpty, !cleanTerms.isEmpty else {
            return .init(isValid: false, cleanedUtterance: cleanUtterance, cleanedExplanation: cleanExplanation, cleanedTerms: cleanTerms, weakExplanation: true, staleTermsDetected: true)
        }

        let lowerExp = cleanExplanation.lowercased()
        let danglingComparable = lowerExp.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let meaningfulCount = FrenchTextHeuristics.meaningfulTokens(lowerExp).count
        let weak = meaningfulCount < 5 || weakExact.contains(lowerExp) || dangling.contains(where: { danglingComparable.hasSuffix(" \($0)") || danglingComparable == $0 })
        guard !weak else {
            return .init(isValid: false, cleanedUtterance: cleanUtterance, cleanedExplanation: cleanExplanation, cleanedTerms: cleanTerms, weakExplanation: true, staleTermsDetected: false)
        }

        let detected = Set(detectedTerms.map(canonicalTermText).filter { !$0.isEmpty })
        let stale = cleanTerms.contains { t in
            let lt = canonicalTermText(t)
            return !containsTerm(lt, in: cleanUtterance) && !detected.contains(lt)
        }
        guard !stale else {
            return .init(isValid: false, cleanedUtterance: cleanUtterance, cleanedExplanation: cleanExplanation, cleanedTerms: cleanTerms, weakExplanation: false, staleTermsDetected: true)
        }

        return .init(isValid: true, cleanedUtterance: cleanUtterance, cleanedExplanation: cleanExplanation, cleanedTerms: cleanTerms, weakExplanation: false, staleTermsDetected: false)
    }

    nonisolated static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    nonisolated private static func canonicalTermText(_ text: String) -> String {
        normalized(text).lowercased().replacingOccurrences(of: "’", with: "'")
    }

    nonisolated private static func containsTerm(_ term: String, in text: String) -> Bool {
        guard !term.isEmpty else { return false }
        let canonicalText = canonicalTermText(text)
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = "(?<![\\p{L}\\p{N}'])\(escaped)(?![\\p{L}\\p{N}'])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(canonicalText.startIndex..<canonicalText.endIndex, in: canonicalText)
        return regex.firstMatch(in: canonicalText, range: range) != nil
    }
}
