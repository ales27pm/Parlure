import XCTest
@testable import Parlure

final class ParlureTests: XCTestCase {
    func testPIIRedaction() {
        let t = "je m'appelle Marc et mon téléphone 514-555-1212"
        XCTAssertTrue(PIIRedactor.containsPII(text: t))
        XCTAssertTrue(PIIRedactor.redact(text: t).contains("REDACTED"))
    }

    func testHeuristicDecision() {
        let d = LLMService.shared.heuristicDecision(userText: "c'est rough pantoute")
        XCTAssertEqual(d.action, .askClarify)
        XCTAssertEqual(d.source, .heuristic)
    }

    func testModelDefaults() {
        let turn = DialogueTurn(input: "a", output: "b")
        XCTAssertEqual(turn.inputLocale, "fr-CA")
        XCTAssertEqual(turn.reviewStatus, .pendingReview)
        let g = GlossaryEntry(utterance: "x", unclearTerms: [], explanation: "y")
        XCTAssertEqual(g.region, "Québec")
    }
}
