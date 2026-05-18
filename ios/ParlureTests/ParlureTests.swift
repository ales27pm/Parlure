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
    func testQFRJSONLDecodeValidation() throws {
        let turns = [DialogueTurn(input: "allo", output: "salut", reviewStatus: .accepted, consentForTraining: true)]
        let glossary = [GlossaryEntry(utterance: "char", unclearTerms: ["char"], explanation: "auto", reviewStatus: .accepted, consentForTraining: true)]
        let result = try ExportService.shared.export(turns: turns, glossary: glossary, options: .init(allowTrainingExport: true, markContainsPersonalData: false, requireReviewBeforeExport: false, exportRedactedText: false))

        guard let qfrURL = result.files.first(where: { $0.lastPathComponent.contains("_qfr_import.jsonl") }) else {
            return XCTFail("qfr import file missing")
        }
        let raw = try String(contentsOf: qfrURL, encoding: .utf8)
        let lines = raw.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        XCTAssertEqual(lines.count, 2)

        let decoder = JSONDecoder()
        for line in lines {
            let data = try XCTUnwrap(line.data(using: .utf8))
            let record = try decoder.decode(QFRImportRecord.self, from: data)
            XCTAssertEqual(record.language, "fr-CA")
            XCTAssertFalse(record.text.isEmpty)
            XCTAssertFalse(record.content.isEmpty)
            XCTAssertEqual(record.reviewStatus, "accepted")
        }
    }

    @MainActor
    func testTSVEscaping() {
        let t = DialogueTurn(input: "a\tb\n", output: "c\rd")
        let out = ExportService.shared.buildTSV(turns: [t], glossary: [])
        XCTAssertTrue(out.contains("\\t"))
        XCTAssertTrue(out.contains("\\n"))
        XCTAssertTrue(out.contains("\\r"))
    }

    @MainActor
    func testHeuristicFallback() {
        let d = LLMService.shared.heuristicDecision(userText: "c'est rough pantoute")
        XCTAssertEqual(d.action, .askClarify)
        XCTAssertEqual(d.source, .heuristic)
    }

    @MainActor
    func testHeuristicDebarrerCharBypassesGenericCharClarification() {
        let d = LLMService.shared.heuristicDecision(userText: "Je dois débarrer mon char")
        XCTAssertEqual(d.action, .answer)
        XCTAssertTrue(d.response.contains("déverrouiller"))
        XCTAssertTrue(d.unclearTerms.isEmpty)
    }

    @MainActor
    func testExportFilenameUniqueness() throws {
        let turns = [DialogueTurn(input: "allo", output: "salut", reviewStatus: .accepted)]
        let glossary: [GlossaryEntry] = []
        let first = try ExportService.shared.export(turns: turns, glossary: glossary, options: .init())
        let second = try ExportService.shared.export(turns: turns, glossary: glossary, options: .init())
        XCTAssertNotEqual(first.files.map(\.lastPathComponent).sorted(), second.files.map(\.lastPathComponent).sorted())
    }

    @MainActor
    func testMetaPIICountNotInflatedByGlobalMarking() throws {
        let turns = [DialogueTurn(input: "texte neutre", output: "réponse neutre", reviewStatus: .accepted, containsPersonalData: false)]
        let glossary: [GlossaryEntry] = []
        let result = try ExportService.shared.export(turns: turns, glossary: glossary, options: .init(allowTrainingExport: false, markContainsPersonalData: true, requireReviewBeforeExport: false, exportRedactedText: false))

        let metaURL = try XCTUnwrap(result.files.first(where: { $0.lastPathComponent.contains("_meta.json") }))
        let metaData = try Data(contentsOf: metaURL)
        let metaObj = try JSONSerialization.jsonObject(with: metaData) as? [String: Any]
        XCTAssertEqual(metaObj?["pii_detected_count"] as? Int, 0)

        let rawURL = try XCTUnwrap(result.files.first(where: { $0.lastPathComponent.contains("_dialogues.raw.jsonl") }))
        let raw = try String(contentsOf: rawURL, encoding: .utf8)
        let firstLine = try XCTUnwrap(raw.split(separator: "\n").first)
        let rawRecord = try JSONDecoder().decode(DialogueRawExportRecord.self, from: Data(firstLine.utf8))
        XCTAssertTrue(rawRecord.containsPersonalData)
    }

    func testModelDefaults() {
        let turn = DialogueTurn(input: "a", output: "b")
        XCTAssertEqual(turn.inputLocale, "fr-CA")
        XCTAssertEqual(turn.reviewStatus, .pendingReview)
        let g = GlossaryEntry(utterance: "x", unclearTerms: [], explanation: "y")
        XCTAssertEqual(g.region, "Québec")
        XCTAssertEqual(g.reviewStatus, .pendingReview)
    }

    @MainActor
    func testExportPendingRecordsRequireReviewAndDoNotCountAsAccepted() throws {
        let turns = [
            DialogueTurn(input: "bonjour", output: "salut", outputSource: .manual, reviewStatus: .pendingReview, consentForTraining: true)
        ]
        let glossary = [
            GlossaryEntry(utterance: "char", unclearTerms: ["char"], explanation: "voiture", reviewStatus: .pendingReview, consentForTraining: true)
        ]
        let result = try ExportService.shared.export(turns: turns, glossary: glossary, options: .init(allowTrainingExport: true, markContainsPersonalData: false, requireReviewBeforeExport: true, exportRedactedText: false))

        let metaURL = try XCTUnwrap(result.files.first(where: { $0.lastPathComponent.contains("_meta.json") }))
        let meta = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as? [String: Any])
        XCTAssertEqual(meta["accepted_count"] as? Int, 0)
        XCTAssertEqual(meta["pending_review_count"] as? Int, 2)

        let qualityURL = try XCTUnwrap(result.files.first(where: { $0.lastPathComponent.contains("_quality_report.json") }))
        let quality = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: qualityURL)) as? [String: Any])
        XCTAssertEqual(quality["training_eligible_count"] as? Int, 0)

        let qfrURL = try XCTUnwrap(result.files.first(where: { $0.lastPathComponent.contains("_qfr_import.jsonl") }))
        let qfrLines = try String(contentsOf: qfrURL, encoding: .utf8).split(separator: "\n")
        let decoder = JSONDecoder()
        let qfrRecords = try qfrLines.map { try decoder.decode(QFRImportRecord.self, from: Data($0.utf8)) }
        XCTAssertTrue(qfrRecords.allSatisfy { $0.requiresReview })
        XCTAssertTrue(qfrRecords.allSatisfy { !$0.consentForTraining })
    }

    @MainActor
    func testTrainingEligibilityRequiresAcceptedAndConsent() throws {
        let turns = [
            DialogueTurn(input: "a", output: "b", reviewStatus: .accepted, consentForTraining: true),
            DialogueTurn(input: "c", output: "d", reviewStatus: .accepted, consentForTraining: false),
            DialogueTurn(input: "e", output: "f", reviewStatus: .pendingReview, consentForTraining: true)
        ]
        let result = try ExportService.shared.export(turns: turns, glossary: [], options: .init(allowTrainingExport: true, markContainsPersonalData: false, requireReviewBeforeExport: false, exportRedactedText: false))
        let qualityURL = try XCTUnwrap(result.files.first(where: { $0.lastPathComponent.contains("_quality_report.json") }))
        let quality = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: qualityURL)) as? [String: Any])
        XCTAssertEqual(quality["training_eligible_count"] as? Int, 1)
        XCTAssertEqual(quality["accepted"] as? Int, 2)
    }

    @MainActor
    func testGlossaryRAGIgnoresUnrelatedCommonWords() {
        let rag = GlossaryRAG()
        rag.reload([
            GlossaryEntry(utterance: "kit", unclearTerms: ["kit"], explanation: "ensemble d'outils nécessaires pour débarrer une porte")
        ])

        let query = "Car je vois à l'épicerie c'est mieux que j'aille pas faim quand j'ai faim"
        let match = rag.bestMatch(for: query)
        if let match {
            XCTAssertFalse(rag.shouldUseGlossary(match: match, query: query))
        }
    }

    @MainActor
    func testGlossaryRAGUsesStrongNearMatch() {
        let rag = GlossaryRAG()
        rag.reload([
            GlossaryEntry(utterance: "kit", unclearTerms: ["kit"], explanation: "ensemble d'outils nécessaires pour débarrer une porte")
        ])
        let query = "Le gars de taxi avait son kit pour débarrer la porte"
        let match = rag.bestMatch(for: query)
        guard let match else {
            XCTFail("Expected a glossary match")
            return
        }
        XCTAssertTrue(rag.shouldUseGlossary(match: match, query: query))
    }

    @MainActor
    func testGlossaryRAGDoesNotUseBelowOverlapThreshold() {
        let rag = GlossaryRAG()
        let entry = GlossaryEntry(utterance: "kit", unclearTerms: ["kit"], explanation: "ensemble d'outils nécessaires pour débarrer une porte")
        let match = GlossaryMatch(entry: entry, score: GlossaryRAG.overlapThreshold - 0.01)
        XCTAssertFalse(rag.shouldUseGlossary(match: match, query: "Le taxi avait un kit"))
    }

    @MainActor
    func testLLMServiceNoGlossaryDebugPrefix() {
        let d = LLMService.shared.heuristicDecision(userText: "Le gars avait son kit", glossaryContext: .init(displayTerm: "kit", utterance: "Le gars avait son kit", explanation: "l'ensemble des outils nécessaires", score: 0.8))
        XCTAssertEqual(d.source, .glossary)
        XCTAssertFalse(d.response.contains("Bonne note du glossaire"))
        XCTAssertFalse(d.response.lowercased().contains("rag"))
    }

    @MainActor
    func testGlossaryContextDisplayTermUsesUnclearTermFirst() {
        let rag = GlossaryRAG()
        let entry = GlossaryEntry(utterance: "le gars de taxi avait un kit pour débarrer", unclearTerms: ["kit"], explanation: "ensemble d'outils")
        XCTAssertEqual(rag.displayTerm(for: entry), "kit")
    }

    @MainActor
    func testGlossaryHeuristicUsesDisplayTermNotUtterance() {
        let context = GlossaryContext(displayTerm: "kit", utterance: "le gars de taxi avait un kit pour débarrer", explanation: "l’ensemble des outils nécessaires", score: 0.9)
        let d = LLMService.shared.heuristicDecision(userText: "ok", glossaryContext: context)
        XCTAssertTrue(d.response.contains("« kit »"))
        XCTAssertFalse(d.response.contains("« le gars de taxi avait un kit pour débarrer »"))
    }

    func testClarificationValidatorRejectsWeakReplies() {
        XCTAssertFalse(ClarificationValidator.validate(utterance: "kit", explanation: "oui c'est ça le kit c'est").isValid)
        XCTAssertFalse(ClarificationValidator.validate(utterance: "kit", explanation: "je sais pas").isValid)
    }

    func testClarificationValidatorAcceptsUsefulReplies() {
        XCTAssertTrue(ClarificationValidator.validate(utterance: "kit", explanation: "un kit c'est l'ensemble des outils nécessaires pour débarrer une porte").isValid)
        XCTAssertTrue(ClarificationValidator.validate(utterance: "kit", explanation: "ça veut dire qu'il avait tout ce qu'il fallait pour faire la job").isValid)
    }

    func testFrenchTextHeuristicsFiltersStopwordsAndKeepsMeaningfulTerms() {
        XCTAssertFalse(FrenchTextHeuristics.meaningfulTokens("c'est").contains("c'est"))
        XCTAssertFalse(FrenchTextHeuristics.meaningfulTokens("c’est").contains("c'est"))
        XCTAssertTrue(FrenchTextHeuristics.meaningfulTokens("pis ben là ça").isEmpty)

        let meaningful = FrenchTextHeuristics.meaningfulTokens("kit pour débarrer la porte")
        XCTAssertTrue(meaningful.contains("kit"))
        XCTAssertTrue(meaningful.contains("débarrer"))
        XCTAssertTrue(meaningful.contains("porte"))
    }


    func testPendingClarificationResolvedTermsNoStaleReuse() {
        XCTAssertEqual(PendingClarification.resolvedTerms(utterance: "Fucké le chien", detectedTerms: ["faire le fin"]), ["faire le fin"])
        XCTAssertNotEqual(PendingClarification.resolvedTerms(utterance: "Fucké le chien", detectedTerms: []), ["faire le fin"])
        XCTAssertNotEqual(PendingClarification.resolvedTerms(utterance: "Virer une brosse", detectedTerms: []), ["attache ta tuque"])
    }

    func testGlossaryQualityRejectsStaleUnclearTerms() {
        let r1 = GlossaryQualityValidator.validate(utterance: "Fucké le chien", explanation: "Ça veut dire avoir manqué une bonne occasion de réussir.", unclearTerms: ["faire le fin"], detectedTerms: [])
        XCTAssertFalse(r1.isValid)
        let r2 = GlossaryQualityValidator.validate(utterance: "Virer une brosse", explanation: "Ça veut dire boire beaucoup d'alcool avec des amis.", unclearTerms: ["attache ta tuque"], detectedTerms: [])
        XCTAssertFalse(r2.isValid)
    }

    func testGlossaryQualityRejectsDanglingTermsWithTrailingPunctuation() {
        let result = GlossaryQualityValidator.validate(utterance: "Virer une brosse", explanation: "Ça veut dire boire beaucoup avec des amis parce que.", unclearTerms: ["Virer une brosse"], detectedTerms: [])
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.weakExplanation)
    }

    func testGlossaryQualityMatchesUnclearTermsAsWholeTerms() {
        let stale = GlossaryQualityValidator.validate(utterance: "Le charbon est dans le poêle", explanation: "Ça veut dire une voiture utilisée pour aller travailler.", unclearTerms: ["char"], detectedTerms: [])
        XCTAssertFalse(stale.isValid)
        XCTAssertTrue(stale.staleTermsDetected)

        let wholeWord = GlossaryQualityValidator.validate(utterance: "Mon char est barré", explanation: "Ça veut dire une voiture utilisée pour aller travailler.", unclearTerms: ["char"], detectedTerms: [])
        XCTAssertTrue(wholeWord.isValid)
    }

    @MainActor
    func testExportManualVsSyntheticFlags() throws {
        let turns = [
            DialogueTurn(input: "u", output: "h", outputSource: .manual, reviewStatus: .accepted, containsPersonalData: false),
            DialogueTurn(input: "u2", output: "a", outputSource: .heuristic, reviewStatus: .pendingReview, containsPersonalData: false)
        ]
        let result = try ExportService.shared.export(turns: turns, glossary: [], options: .init(markContainsPersonalData: false))
        let rawURL = try XCTUnwrap(result.files.first(where: { $0.lastPathComponent.contains("_dialogues.raw.jsonl") }))
        let lines = try String(contentsOf: rawURL, encoding: .utf8).split(separator: "\n").map(String.init)
        let decoder = JSONDecoder()
        let records = try lines.map { try decoder.decode(DialogueRawExportRecord.self, from: Data($0.utf8)) }
        let manual = try XCTUnwrap(records.first(where: { $0.outputSource == "manual" }))
        XCTAssertFalse(manual.syntheticOutput)
        XCTAssertTrue(manual.humanOutput)
        let heuristic = try XCTUnwrap(records.first(where: { $0.outputSource == "heuristic" }))
        XCTAssertTrue(heuristic.syntheticOutput)

        let qfrURL = try XCTUnwrap(result.files.first(where: { $0.lastPathComponent.contains("_qfr_import.jsonl") }))
        let qfrLines = try String(contentsOf: qfrURL, encoding: .utf8).split(separator: "\n").map(String.init)
        let qfr = try qfrLines.map { try decoder.decode(QFRImportRecord.self, from: Data($0.utf8)) }
        XCTAssertFalse(try XCTUnwrap(qfr.first(where: { $0.outputSource == "manual" })).syntheticComponent)
        XCTAssertTrue(try XCTUnwrap(qfr.first(where: { $0.outputSource == "heuristic" })).syntheticComponent)
    }

    @MainActor
    func testGlossaryExportFlagsMarkManualHumanOutput() throws {
        let glossary = [
            GlossaryEntry(utterance: "char", unclearTerms: ["char"], explanation: "Une voiture.", source: .manual, reviewStatus: .accepted, containsPersonalData: false)
        ]
        let result = try ExportService.shared.export(turns: [], glossary: glossary, options: .init(markContainsPersonalData: false))

        let rawURL = try XCTUnwrap(result.files.first(where: { $0.lastPathComponent.contains("_glossary.raw.jsonl") }))
        let line = try XCTUnwrap(try String(contentsOf: rawURL, encoding: .utf8).split(separator: "\n").first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(object["synthetic_output"] as? Bool, false)
        XCTAssertEqual(object["human_output"] as? Bool, true)
        XCTAssertEqual(object["assistant_generated"] as? Bool, false)
    }

    @MainActor
    func testQualityReportUsesActualEligibilityAndWarnings() throws {
        let turns = [
            DialogueTurn(input: "u", output: "h", outputSource: .manual, reviewStatus: .accepted, containsPersonalData: false, consentForTraining: true)
        ]
        let result = try ExportService.shared.export(turns: turns, glossary: [], options: .init(allowTrainingExport: true, markContainsPersonalData: false, requireReviewBeforeExport: false, exportRedactedText: false))

        let qualityURL = try XCTUnwrap(result.files.first(where: { $0.lastPathComponent.contains("_quality_report.json") }))
        let qualityData = try Data(contentsOf: qualityURL)
        let quality = try XCTUnwrap(JSONSerialization.jsonObject(with: qualityData) as? [String: Any])
        XCTAssertEqual(quality["training_eligible_count"] as? Int, 1)
        XCTAssertEqual(quality["warnings"] as? [String], [])
    }

    func testAssistantMessageDeduperConsecutiveOnly() {
        XCTAssertFalse(AssistantMessageDeduper.shouldAppend(lastRole: .assistant, lastAssistantNormalized: "Merci", candidateText: "Merci"))
        XCTAssertTrue(AssistantMessageDeduper.shouldAppend(lastRole: .user, lastAssistantNormalized: "Merci", candidateText: "Merci"))
    }

    func testAssistantMessageDeduperRejectsEmptyAssistantText() {
        XCTAssertFalse(AssistantMessageDeduper.shouldAppend(lastRole: .assistant, lastAssistantNormalized: "Merci", candidateText: "   \n\t"))
        XCTAssertFalse(AssistantMessageDeduper.shouldAppend(lastRole: .user, lastAssistantNormalized: nil, candidateText: "  "))
    }
}
