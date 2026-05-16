//
//  LLMService.swift
//  Parlure
//
//  Uses Foundation Models (iOS 26+) for on-device decisions.
//  Provides a heuristic fallback for older OS versions.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum LLMAction: String {
    case answer
    case askClarify
}

struct LLMDecision {
    var action: LLMAction
    var response: String
    var unclearTerms: [String]
}

@MainActor
final class LLMService {
    static let shared = LLMService()

    private let instructions = """
    Tu es un assistant bilingue spécialisé en français québécois et ses expressions idiomatiques.
    Si tu n'es pas certain d'une expression, demande gentiment des précisions.
    Sinon, réponds de façon courte, chaleureuse, et naturelle en français québécois.
    Identifie clairement tout terme ou expression que tu ne comprends pas dans `unclearTerms`.
    """

    func decide(history: [ChatMessage], userText: String, glossaryHint: String?) async -> LLMDecision {
        if #available(iOS 26.0, *) {
            return await decideWithFoundationModels(history: history, userText: userText, glossaryHint: glossaryHint)
        }
        return heuristicDecision(userText: userText, glossaryHint: glossaryHint)
    }

    @available(iOS 26.0, *)
    private func decideWithFoundationModels(history: [ChatMessage], userText: String, glossaryHint: String?) async -> LLMDecision {
        guard SystemLanguageModel.default.isAvailable else {
            return heuristicDecision(userText: userText, glossaryHint: glossaryHint)
        }

        let session = LanguageModelSession(instructions: { instructions })
        let context = history.suffix(6).map { "\($0.role == .user ? "U" : "A"): \($0.content)" }.joined(separator: "\n")

        var prompt = "Conversation récente:\n\(context)\n\nUtilisateur: \(userText)"
        if let hint = glossaryHint, !hint.isEmpty {
            prompt += "\n\nIndice du glossaire (déjà appris par l'utilisateur): \(hint)"
        }

        do {
            let response = try await session.respond(to: prompt, generating: GeneratedDecision.self)
            let d = response.content
            let action: LLMAction = d.action.lowercased().contains("clarify") ? .askClarify : .answer
            return LLMDecision(action: action, response: d.response, unclearTerms: d.unclearTerms)
        } catch {
            return heuristicDecision(userText: userText, glossaryHint: glossaryHint)
        }
    }

    private func heuristicDecision(userText: String, glossaryHint: String?) -> LLMDecision {
        let known: Set<String> = [
            "bonjour", "salut", "allo", "merci", "oui", "non", "ça va",
            "comment", "quoi", "où", "qui", "quand", "pourquoi", "comment ça va"
        ]
        let normalized = userText.lowercased()
        let isCommon = known.contains(where: { normalized.contains($0) })

        if let hint = glossaryHint {
            return LLMDecision(action: .answer, response: "D'après ton glossaire: \(hint)", unclearTerms: [])
        }

        if isCommon || userText.split(separator: " ").count <= 2 {
            return LLMDecision(
                action: .answer,
                response: "Allô ! Continue, j'enregistre tes expressions québécoises.",
                unclearTerms: []
            )
        }

        return LLMDecision(
            action: .askClarify,
            response: "Peux-tu m'expliquer cette expression dans tes propres mots ?",
            unclearTerms: []
        )
    }
}
