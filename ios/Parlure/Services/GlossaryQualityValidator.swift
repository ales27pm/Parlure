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
    private static let weakExact = ["oui c'est ça", "je sais pas", "boire de l'alcool jusqu'à être sous"]
    private static let dangling = ["donc", "jusqu'à", "parce que", "pis"]

    static func validate(utterance: String, explanation: String, unclearTerms: [String], detectedTerms: [String]) -> GlossaryQualityValidationResult {
        let cleanUtterance = normalized(utterance)
        let cleanExplanation = normalized(explanation)
        let cleanTerms = unclearTerms.map(normalized).filter { !$0.isEmpty }

        guard !cleanUtterance.isEmpty, !cleanExplanation.isEmpty, !cleanTerms.isEmpty else {
            return .init(isValid: false, cleanedUtterance: cleanUtterance, cleanedExplanation: cleanExplanation, cleanedTerms: cleanTerms, weakExplanation: true, staleTermsDetected: true)
        }

        let lowerExp = cleanExplanation.lowercased()
        let meaningfulCount = FrenchTextHeuristics.meaningfulTokens(lowerExp).count
        let weak = meaningfulCount < 5 || weakExact.contains(lowerExp) || dangling.contains(where: { lowerExp.hasSuffix(" \($0)") || lowerExp == $0 })
        guard !weak else {
            return .init(isValid: false, cleanedUtterance: cleanUtterance, cleanedExplanation: cleanExplanation, cleanedTerms: cleanTerms, weakExplanation: true, staleTermsDetected: false)
        }

        let utteranceLower = cleanUtterance.lowercased()
        let detected = Set(detectedTerms.map { normalized($0).lowercased() }.filter { !$0.isEmpty })
        let stale = cleanTerms.contains { t in
            let lt = t.lowercased()
            return !utteranceLower.contains(lt) && !detected.contains(lt)
        }
        guard !stale else {
            return .init(isValid: false, cleanedUtterance: cleanUtterance, cleanedExplanation: cleanExplanation, cleanedTerms: cleanTerms, weakExplanation: false, staleTermsDetected: true)
        }

        return .init(isValid: true, cleanedUtterance: cleanUtterance, cleanedExplanation: cleanExplanation, cleanedTerms: cleanTerms, weakExplanation: false, staleTermsDetected: false)
    }

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
