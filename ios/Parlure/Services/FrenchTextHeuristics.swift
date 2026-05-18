import Foundation

enum FrenchTextHeuristics {
    nonisolated static let stopwords: Set<String> = [
        "je", "tu", "il", "elle", "on", "le", "la", "les", "un", "une", "des", "de", "du", "au", "aux",
        "à", "a", "est", "et", "ou", "pour", "avec", "dans", "sur", "en", "que", "qui",
        "c", "d", "j", "l", "m", "n", "qu", "s", "t",
        "c'est", "ça", "pis", "ben", "là", "oui", "non"
    ]

    nonisolated static func normalizedTokens(_ text: String, includeBigrams: Bool = false) -> [String] {
        let apostropheNormalized = text
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
        let cleaned = apostropheNormalized
            .replacingOccurrences(of: "[^\\p{L}\\p{N}\\s']", with: " ", options: .regularExpression)

        let rawTokens = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        var tokens: [String] = []
        for token in rawTokens {
            tokens.append(token)
            if token.contains("'") {
                let parts = token.split(separator: "'").map(String.init).filter { !$0.isEmpty }
                tokens.append(contentsOf: parts)
            }
        }

        if includeBigrams, rawTokens.count > 1 {
            for i in 0..<(rawTokens.count - 1) {
                tokens.append("\(rawTokens[i]) \(rawTokens[i + 1])")
            }
        }

        return tokens
    }

    nonisolated static func meaningfulTokens(_ text: String, includeBigrams: Bool = false) -> Set<String> {
        Set(
            normalizedTokens(text, includeBigrams: includeBigrams)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { token in
                    !token.isEmpty &&
                    !token.contains(" ") &&
                    !stopwords.contains(token)
                }
        )
    }
}
