import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum DecisionSource: String, Codable { case foundationModels, heuristic, glossary }
enum LLMAction: String { case answer, askClarify }
struct LLMDecision { var action: LLMAction; var response: String; var unclearTerms: [String]; var source: DecisionSource }
struct GlossaryContext {
    var displayTerm: String
    var utterance: String
    var explanation: String
    var score: Double
}

enum QuebecFrenchHeuristics {
    static func directDecision(for userText: String) -> LLMDecision? {
        let lower = userText.lowercased()

        if mentionsDebarrer(lower), lower.contains("clé"), mentionsVehicle(lower) {
            return .init(
                action: .answer,
                response: "Tu veux dire : « J’ai oublié mes clés dans mon char, donc je ne peux pas le déverrouiller / l’ouvrir. » Ici, « débarrer » veut dire déverrouiller.",
                unclearTerms: [],
                source: .heuristic
            )
        }

        if mentionsDebarrer(lower), mentionsVehicle(lower) || lower.contains("porte") {
            return .init(
                action: .answer,
                response: "Ici, « débarrer », en québécois, veut dire déverrouiller. Donc ta phrase parle d’ouvrir ou de déverrouiller le char/la porte, pas d’enlever une barre.",
                unclearTerms: [],
                source: .heuristic
            )
        }

        if containsQuestionParticleTu(userText) {
            let standard = standardQuestionForTuParticle(userText)
            if !standard.isEmpty {
                return .init(
                    action: .answer,
                    response: "« \(userText) », en français standard, c’est : « \(standard) ». En québécois oral, le deuxième « tu » sert de particule interrogative; il ne veut pas dire « toi ».",
                    unclearTerms: [],
                    source: .heuristic
                )
            }
            return .init(
                action: .answer,
                response: "Dans cette phrase, le « -tu » sert de particule interrogative québécoise. Il transforme l’énoncé en question, un peu comme « est-ce que » en français standard.",
                unclearTerms: [],
                source: .heuristic
            )
        }

        return nil
    }

    static func isGrounded(_ decision: LLMDecision, in userText: String) -> Bool {
        let lowerInput = userText.lowercased()
        let lowerResponse = decision.response.lowercased()

        if lowerResponse.contains("déverrouill") || lowerResponse.contains("débarr") || lowerResponse.contains("debarr") {
            guard mentionsDebarrer(lowerInput) || lowerInput.contains("barr") || lowerInput.contains("clé") || lowerInput.contains("porte") || mentionsVehicle(lowerInput) else {
                return false
            }
        }

        guard decision.action == .askClarify else { return true }

        let terms = decision.unclearTerms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if terms.contains(where: { !term($0, appearsIn: lowerInput) }) {
            return false
        }

        let quoted = quotedTerms(in: decision.response)
        if quoted.contains(where: { !term($0, appearsIn: lowerInput) }) {
            return false
        }

        return true
    }

    private static func mentionsDebarrer(_ lower: String) -> Bool {
        lower.contains("débarrer") || lower.contains("debarrer") || lower.contains("débarr") || lower.contains("debarr")
    }

    private static func mentionsVehicle(_ lower: String) -> Bool {
        lower.contains("char") || lower.contains("auto") || lower.contains("véhicule") || lower.contains("vehicule") || lower.contains("voiture")
    }

    private static func containsQuestionParticleTu(_ text: String) -> Bool {
        text.range(of: #"(?i)\b[\p{L}'’]+-tu\b"#, options: .regularExpression) != nil
    }

    private static func standardQuestionForTuParticle(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let withoutTerminalQuestionMark = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: " ?!.…"))
        let transformed = withoutTerminalQuestionMark
            .replacingOccurrences(of: #"(?i)^tu\s+veux-tu\b"#, with: "Veux-tu", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^vous\s+voulez-tu\b"#, with: "Voulez-vous", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^il\s+est-tu\b"#, with: "Est-il", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^elle\s+est-tu\b"#, with: "Est-elle", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^c['’]?est-tu\b"#, with: "Est-ce que c’est", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^ça\s+marche-tu\b"#, with: "Est-ce que ça marche", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^ca\s+marche-tu\b"#, with: "Est-ce que ça marche", options: .regularExpression)

        let normalized = transformed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if normalized == withoutTerminalQuestionMark {
            return "Est-ce que \(withoutTerminalQuestionMark.replacingOccurrences(of: "-tu", with: "", options: [.caseInsensitive])) ?"
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
        return normalized.hasSuffix("?") ? normalized : "\(normalized) ?"
    }

    private static func term(_ term: String, appearsIn lowerInput: String) -> Bool {
        let normalized = term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        if lowerInput.contains(normalized) { return true }

        let pieces = normalized
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
        guard !pieces.isEmpty else { return false }
        return pieces.allSatisfy { lowerInput.contains($0) }
    }

    private static func quotedTerms(in text: String) -> [String] {
        let pattern = #"[«\"]([^»\"]+)[»\"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

@MainActor
final class LLMService {
    static let shared = LLMService()

    func decide(history: [ChatMessage], userText: String, glossaryContext: GlossaryContext?) async -> LLMDecision {
        if let direct = QuebecFrenchHeuristics.directDecision(for: userText) {
            return direct
        }
        if let glossaryContext, !glossaryContext.explanation.isEmpty {
            return heuristicDecision(userText: userText, glossaryContext: glossaryContext)
        }
        if #available(iOS 26.0, *), let fm = await decideWithFM(history: history, userText: userText, glossaryContext: glossaryContext), QuebecFrenchHeuristics.isGrounded(fm, in: userText) {
            return fm
        }
        return heuristicDecision(userText: userText, glossaryContext: glossaryContext)
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func decideWithFM(history: [ChatMessage], userText: String, glossaryContext: GlossaryContext?) async -> LLMDecision? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: {
            """
            Réponds en français québécois, court et naturel.
            La phrase courante de l’utilisateur est prioritaire sur l’historique.
            N’utilise jamais un mot ou une expression de l’historique comme terme à clarifier s’il n’apparaît pas dans la phrase courante.
            Ne reste pas accroché à une ancienne clarification.
            Ne remplace pas débarrer par débarrasser. En contexte québécois, débarrer veut dire déverrouiller.
            Si la phrase contient une forme comme veux-tu, est-tu, marche-tu ou c’est-tu, explique que le deuxième tu / -tu est une particule interrogative québécoise.
            """
        })
        let currentNormalized = AssistantMessageDeduper.normalize(userText)
        let context = history
            .filter { AssistantMessageDeduper.normalize($0.content) != currentNormalized }
            .suffix(4)
            .map { "\($0.role == .user ? "U" : "A"): \($0.content)" }
            .joined(separator: "\n")
        let lexicalContext: String
        if let glossaryContext {
            lexicalContext = """

            Contexte lexical appris localement:
            Expression: \(glossaryContext.displayTerm)
            Sens: \(glossaryContext.explanation)
            Utilise ce contexte seulement s’il aide vraiment à répondre naturellement à la phrase courante.
            """
        } else {
            lexicalContext = ""
        }

        let prompt = """
        Historique récent, pour contexte seulement:
        \(context)

        Phrase courante à interpréter:
        \(userText)
        \(lexicalContext)

        Retourne action/réponse/unclearTerms pour la phrase courante seulement.
        """
        do {
            let r = try await session.respond(to: prompt, generating: GeneratedDecision.self)
            let action: LLMAction = r.content.action.lowercased().contains("clar") ? .askClarify : .answer
            return .init(action: action, response: r.content.response, unclearTerms: r.content.unclearTerms, source: .foundationModels)
        } catch {
            return nil
        }
    }
#else
    @available(iOS 26.0, *)
    private func decideWithFM(history: [ChatMessage], userText: String, glossaryContext: GlossaryContext?) async -> LLMDecision? {
        nil
    }
#endif

    func heuristicDecision(userText: String, glossaryContext: GlossaryContext? = nil) -> LLMDecision {
        if let direct = QuebecFrenchHeuristics.directDecision(for: userText) {
            return direct
        }

        if let glossaryContext, !glossaryContext.explanation.isEmpty {
            let response = "Ah ok, je te suis. Ici, « \(glossaryContext.displayTerm) », c’est \(glossaryContext.explanation)."
            return .init(action: .answer, response: response, unclearTerms: [], source: .glossary)
        }

        let lower = userText.lowercased()
        if lower.contains("clé") && (lower.contains("barr") || lower.contains("porte")) {
            return .init(action: .askClarify, response: "Ouin, ça sonne frustrant. Tu veux dire que t'as besoin de déverrouiller la porte?", unclearTerms: ["débarrer"], source: .heuristic)
        }

        let idiomSignals = ["ça a pas d'allure", "pantoute", "char", "magasiner", "c'est rough", "donne-moi une break", "kit"]
        let matched = idiomSignals.filter { lower.contains($0) }
        if let first = matched.first {
            let response = "Juste pour être sûr: dans ta phrase, « \(first) », ça veut dire quoi exactement?"
            return .init(action: .askClarify, response: response, unclearTerms: matched, source: .heuristic)
        }
        if userText.split(separator: " ").count <= 2 {
            return .init(action: .answer, response: "Parfait, continue. Je t'écoute.", unclearTerms: [], source: .heuristic)
        }
        return .init(action: .answer, response: "Merci! C'est noté en fr-CA. Continue quand tu veux.", unclearTerms: [], source: .heuristic)
    }
}
