import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum DecisionSource: String, Codable { case foundationModels, heuristic, glossary }
enum LLMAction: String { case answer, askClarify }
struct LLMDecision { var action: LLMAction; var response: String; var unclearTerms: [String]; var source: DecisionSource }

@MainActor
final class LLMService {
    static let shared = LLMService()

    func decide(history: [ChatMessage], userText: String, glossaryHint: String?) async -> LLMDecision {
        if let glossaryHint, !glossaryHint.isEmpty {
            return .init(action: .answer, response: "Bonne note du glossaire: \(glossaryHint)", unclearTerms: [], source: .glossary)
        }
        if #available(iOS 26.0, *), let fm = await decideWithFM(history: history, userText: userText) { return fm }
        return heuristicDecision(userText: userText)
    }

    @available(iOS 26.0, *)
    private func decideWithFM(history: [ChatMessage], userText: String) async -> LLMDecision? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: { "Réponds en français québécois, court et naturel." })
        let prompt = "Utilisateur: \(userText)\nRetourne action/réponse/unclearTerms."
        do {
            let r = try await session.respond(to: prompt, generating: GeneratedDecision.self)
            let a: LLMAction = r.content.action.lowercased().contains("clar") ? .askClarify : .answer
            return .init(action: a, response: r.content.response, unclearTerms: r.content.unclearTerms, source: .foundationModels)
        } catch { return nil }
    }

    func heuristicDecision(userText: String) -> LLMDecision {
        let lower = userText.lowercased()
        let idiomSignals = ["ça a pas d'allure", "pantoute", "char", "magasiner", "c'est rough", "donne-moi une break"]
        if idiomSignals.contains(where: { lower.contains($0) }) {
            return .init(action: .askClarify, response: "Je veux bien capter le sens québécois exact—tu peux me l'expliquer en une phrase?", unclearTerms: idiomSignals.filter { lower.contains($0) }, source: .heuristic)
        }
        if userText.split(separator: " ").count <= 2 {
            return .init(action: .answer, response: "Parfait, continue. Je t'écoute.", unclearTerms: [], source: .heuristic)
        }
        return .init(action: .answer, response: "Merci! C'est noté en fr-CA. Continue quand tu veux.", unclearTerms: [], source: .heuristic)
    }
}
