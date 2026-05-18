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

@MainActor
final class LLMService {
    static let shared = LLMService()

    func decide(history: [ChatMessage], userText: String, glossaryContext: GlossaryContext?) async -> LLMDecision {
        if let glossaryContext, !glossaryContext.explanation.isEmpty {
            return heuristicDecision(userText: userText, glossaryContext: glossaryContext)
        }
        if #available(iOS 26.0, *), let fm = await decideWithFM(history: history, userText: userText, glossaryContext: glossaryContext) {
            return fm
        }
        return heuristicDecision(userText: userText, glossaryContext: glossaryContext)
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func decideWithFM(history: [ChatMessage], userText: String, glossaryContext: GlossaryContext?) async -> LLMDecision? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: { "Réponds en français québécois, court et naturel. Ne remplace pas débarrer par débarrasser. En contexte québécois, débarrer veut dire déverrouiller." })
        let context = history.suffix(6).map {
            "\($0.role == .user ? "U" : "A"): \($0.content)"
        }.joined(separator: "\n")
        let lexicalContext: String
        if let glossaryContext {
            lexicalContext = """

            Contexte lexical appris localement:
            Expression: \(glossaryContext.displayTerm)
            Sens: \(glossaryContext.explanation)
            Utilise ce contexte seulement s’il aide vraiment à répondre naturellement.
            """
        } else {
            lexicalContext = ""
        }

        let prompt = """
        Conversation récente:
        \(context)

        Utilisateur: \(userText)
        \(lexicalContext)

        Retourne action/réponse/unclearTerms.
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
        if let glossaryContext, !glossaryContext.explanation.isEmpty {
            let response = "Ah ok, je te suis. Ici, « \(glossaryContext.displayTerm) », c’est \(glossaryContext.explanation)."
            return .init(action: .answer, response: response, unclearTerms: [], source: .glossary)
        }

        let lower = userText.lowercased()
        if lower.contains("débarrer") && (lower.contains("porte") || lower.contains("char")) {
            return .init(action: .answer, response: "Tu veux dire déverrouiller les portes du char?", unclearTerms: [], source: .heuristic)
        }
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
