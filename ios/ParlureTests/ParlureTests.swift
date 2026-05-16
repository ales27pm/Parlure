import XCTest
@testable import Parlure

final class ParlureTests: XCTestCase {
    func testPIIDetectionKinds() {
        let text = "je m'appelle Alex, mon téléphone 514-555-1212, code H2X 1Y4, site https://qc.ca et mail a@b.com"
        let matches = PIIRedactor.detect(text: text)
        XCTAssertTrue(matches.contains { $0.type == "name_marker" })
        XCTAssertTrue(matches.contains { $0.type == "phone" })
        XCTAssertTrue(matches.contains { $0.type == "postal_code" })
        XCTAssertTrue(matches.contains { $0.type == "url" })
        XCTAssertTrue(matches.contains { $0.type == "email" })
    }

    func testPIIRangeSafeRedactionRepeatedAndOverlap() {
        let text = "email a@b.com puis encore a@b.com, mon adresse 123 rue Test"
        let redacted = PIIRedactor.redact(text: text)
        XCTAssertFalse(redacted.contains("a@b.com"))
        XCTAssertTrue(redacted.contains("REDACTED_EMAIL"))
    }

    @MainActor
    func testExportPolicyAndShape() throws {
        let service = ExportService.shared
        let turns = [
            DialogueTurn(input: "bonjour", output: "salut", reviewStatus: .accepted, consentForTraining: true),
            DialogueTurn(input: "secret", output: "ok", reviewStatus: .rejected, consentForTraining: true)
        ]
        let glossary = [GlossaryEntry(utterance: "char", unclearTerms: ["char"], explanation: "auto", reviewStatus: .pendingReview)]
        let result = try service.export(turns: turns, glossary: glossary, options: .init(allowTrainingExport: true, markContainsPersonalData: false, requireReviewBeforeExport: true, exportRedactedText: true))
        XCTAssertEqual(result.qfrCount, 2)
        XCTAssertEqual(result.rejectedExcludedCount, 1)
    }

    @MainActor
    func testTSVEscaping() {
        let t = DialogueTurn(input: "a\tb\n", output: "c\rd")
        let out = ExportService.shared.buildTSV(turns: [t], glossary: [])
        XCTAssertTrue(out.contains("\\t"))
        XCTAssertTrue(out.contains("\\n"))
        XCTAssertTrue(out.contains("\\r"))
    }

    func testHeuristicFallback() {
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
        XCTAssertEqual(g.reviewStatus, .pendingReview)
    }
}
