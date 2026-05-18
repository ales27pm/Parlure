import XCTest
@testable import Parlure

final class DialogueGroundingTests: XCTestCase {
    @MainActor
    func testTuQuestionParticleIsAnsweredAsCurrentExpression() async {
        let history = [
            ChatMessage(role: .user, content: "J’ai oublié les clés dans mon char fait que je peux pas le débarrer"),
            ChatMessage(role: .assistant, content: "C’est quoi 'déverrouiller' dans ce contexte?")
        ]

        let decision = await LLMService.shared.decide(
            history: history,
            userText: "Tu veux-tu venir avec moi",
            glossaryContext: nil
        )

        XCTAssertEqual(decision.action, .answer)
        XCTAssertEqual(decision.source, .heuristic)
        XCTAssertTrue(decision.response.contains("Veux-tu venir avec moi"))
        XCTAssertTrue(decision.response.lowercased().contains("particule interrogative"))
        XCTAssertFalse(decision.response.lowercased().contains("déverrouiller"))
        XCTAssertFalse(decision.response.lowercased().contains("débarrer"))
        XCTAssertTrue(decision.unclearTerms.isEmpty)
    }

    @MainActor
    func testLockedKeysInCharMeansCannotUnlockOpenVehicle() async {
        let decision = await LLMService.shared.decide(
            history: [],
            userText: "J’ai oublié les clés dans mon char fait que je peux pas le débarrer",
            glossaryContext: nil
        )

        XCTAssertEqual(decision.action, .answer)
        XCTAssertEqual(decision.source, .heuristic)
        XCTAssertTrue(decision.response.contains("clés"))
        XCTAssertTrue(decision.response.lowercased().contains("char"))
        XCTAssertTrue(decision.response.lowercased().contains("déverrouiller"))
        XCTAssertTrue(decision.response.lowercased().contains("ouvrir"))
        XCTAssertTrue(decision.unclearTerms.isEmpty)
    }

    func testUngroundedClarificationRejectsStaleTermFromPreviousTopic() {
        let stale = LLMDecision(
            action: .askClarify,
            response: "C’est quoi 'déverrouiller' dans ce contexte?",
            unclearTerms: ["déverrouiller"],
            source: .foundationModels
        )

        XCTAssertFalse(QuebecFrenchHeuristics.isGrounded(stale, in: "Tu veux-tu venir avec moi"))
    }

    func testGroundedClarificationAcceptsTermPresentInCurrentPhrase() {
        let grounded = LLMDecision(
            action: .askClarify,
            response: "Juste pour être sûr: dans ta phrase, « pantoute », ça veut dire quoi exactement?",
            unclearTerms: ["pantoute"],
            source: .foundationModels
        )

        XCTAssertTrue(QuebecFrenchHeuristics.isGrounded(grounded, in: "Ça marche pas pantoute"))
    }
}
