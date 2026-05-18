import Foundation

struct ExportOptions {
    var allowTrainingExport = false
    var markContainsPersonalData = true
    var requireReviewBeforeExport = true
    var exportRedactedText = true
}

struct ExportResult {
    let files: [URL]
    let dialogueCount: Int
    let glossaryCount: Int
    let qfrCount: Int
    let rejectedExcludedCount: Int
}

struct DialogueRawExportRecord: Codable {
    let schemaVersion: String
    let id: String
    let timestamp: Date
    let type: String
    let input: String
    let output: String
    let inputLocale: String
    let recognizerLocale: String
    let outputSource: String
    let glossaryHintUsed: Bool
    let reviewStatus: String
    let containsPersonalData: Bool
    let detectedPII: Bool
    let userMarkedSensitive: Bool
    let consentForTraining: Bool
    let syntheticOutput: Bool
    let humanOutput: Bool
    let assistantGenerated: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", id, timestamp, type, input, output
        case inputLocale = "input_locale", recognizerLocale = "recognizer_locale", outputSource = "output_source"
        case glossaryHintUsed = "glossary_hint_used", reviewStatus = "review_status"
        case containsPersonalData = "contains_personal_data", detectedPII = "detected_pii", userMarkedSensitive = "user_marked_sensitive", consentForTraining = "consent_for_training"
        case syntheticOutput = "synthetic_output", humanOutput = "human_output", assistantGenerated = "assistant_generated", notes
    }
}

struct GlossaryRawExportRecord: Codable {
    let schemaVersion: String
    let id: String
    let timestamp: Date
    let type: String
    let utterance: String
    let unclearTerms: [String]
    let explanation: String
    let region: String
    let reviewStatus: String
    let containsPersonalData: Bool
    let detectedPII: Bool
    let userMarkedSensitive: Bool
    let consentForTraining: Bool
    let syntheticOutput: Bool
    let humanOutput: Bool
    let assistantGenerated: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", id, timestamp, type, utterance
        case unclearTerms = "unclear_terms", explanation, region, reviewStatus = "review_status"
        case containsPersonalData = "contains_personal_data", detectedPII = "detected_pii", userMarkedSensitive = "user_marked_sensitive", consentForTraining = "consent_for_training"
        case syntheticOutput = "synthetic_output", humanOutput = "human_output", assistantGenerated = "assistant_generated", notes
    }
}

struct QFRImportRecord: Codable {
    let text: String
    let content: String
    let sourceId: String
    let captureType: String
    let language: String
    let dialectRegion: String
    let register: String
    let containsPersonalData: Bool
    let detectedPII: Bool
    let userMarkedSensitive: Bool
    let requiresReview: Bool
    let consentForTraining: Bool
    let syntheticComponent: Bool
    let provenance: String
    let license: String
    let reviewStatus: String
    let outputSource: String?
    let redactedText: String?

    enum CodingKeys: String, CodingKey {
        case text, content, language, register, provenance, license
        case sourceId = "source_id", captureType = "capture_type", dialectRegion = "dialect_region"
        case containsPersonalData = "contains_personal_data", detectedPII = "detected_pii", userMarkedSensitive = "user_marked_sensitive", requiresReview = "requires_review"
        case consentForTraining = "consent_for_training", syntheticComponent = "synthetic_component"
        case reviewStatus = "review_status", outputSource = "output_source", redactedText = "redacted_text"
    }
}

struct ExportMetaRecord: Codable {
    let appName: String
    let appVersion: String
    let exportTimestamp: Date
    let schemaVersions: [String]
    let dialogueCount: Int
    let glossaryCount: Int
    let qfrImportCount: Int
    let rejectedExcludedCount: Int
    let pendingReviewCount: Int
    let acceptedCount: Int
    let redactedCount: Int
    let piiDetectedCount: Int
    let sensitiveMarkedCount: Int
    let defaultLocale: String
    let consentSettings: [String: Bool]
    let privacyFlags: [String: Bool]
    let warning: String

    enum CodingKeys: String, CodingKey {
        case appName = "app_name", appVersion = "app_version", exportTimestamp = "export_timestamp"
        case schemaVersions = "schema_versions", dialogueCount = "dialogue_count", glossaryCount = "glossary_count"
        case qfrImportCount = "qfr_import_count", rejectedExcludedCount = "rejected_excluded_count"
        case pendingReviewCount = "pending_review_count", acceptedCount = "accepted_count", redactedCount = "redacted_count"
        case piiDetectedCount = "pii_detected_count", sensitiveMarkedCount = "sensitive_marked_count", defaultLocale = "default_locale"
        case consentSettings = "consent_settings", privacyFlags = "privacy_flags", warning
    }
}

@MainActor
final class ExportService {
    static let shared = ExportService()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private var exportDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func export(turns: [DialogueTurn], glossary: [GlossaryEntry], options: ExportOptions) throws -> ExportResult {
        let timestampMs = Int(Date().timeIntervalSince1970 * 1000)
        let suffix = UUID().uuidString.prefix(8)
        let prefix = "parlure_\(timestampMs)_\(suffix)"

        let dialoguesURL = exportDir.appendingPathComponent("\(prefix)_dialogues.raw.jsonl")
        let glossaryURL = exportDir.appendingPathComponent("\(prefix)_glossary.raw.jsonl")
        let qfrURL = exportDir.appendingPathComponent("\(prefix)_qfr_import.jsonl")
        let parallelURL = exportDir.appendingPathComponent("\(prefix)_parallel.tsv")
        let metaURL = exportDir.appendingPathComponent("\(prefix)_meta.json")
        let qualityURL = exportDir.appendingPathComponent("\(prefix)_quality_report.json")

        var qfrRecords: [QFRImportRecord] = []
        var rejectedExcludedCount = 0
        var piiDetectedCount = 0
        var pendingReviewCount = 0
        var acceptedCount = 0
        var redactedCount = 0
        var sensitiveMarkedCount = 0
        var assistantGeneratedCount = 0
        var manualHumanCount = 0
        var staleUnclearTermsCount = 0
        var weakExplanationCount = 0

        let dialogueRecords = turns.map { turn in
            let pii = PIIRedactor.containsPII(text: turn.input + " " + turn.output)
            let piiDetectedOrKnown = pii || turn.containsPersonalData
            if piiDetectedOrKnown { piiDetectedCount += 1 }
            let assistantGenerated = turn.outputSource != .manual
            let syntheticOutput = assistantGenerated
            if assistantGenerated { assistantGeneratedCount += 1 } else { manualHumanCount += 1 }
            if turn.reviewStatus == .pendingReview { pendingReviewCount += 1 }
            if turn.reviewStatus == .accepted { acceptedCount += 1 }
            if turn.reviewStatus == .redacted { redactedCount += 1 }
            if turn.reviewStatus == .rejected { rejectedExcludedCount += 1 }

            let consent = trainingConsent(global: options.allowTrainingExport, itemConsent: turn.consentForTraining, reviewStatus: turn.reviewStatus)
            let requiresReview = options.requireReviewBeforeExport || turn.reviewStatus == .pendingReview
            let containsPersonalData = pii || turn.containsPersonalData || options.markContainsPersonalData
            if options.markContainsPersonalData { sensitiveMarkedCount += 1 }

            if turn.reviewStatus != .rejected {
                qfrRecords.append(QFRImportRecord(
                    text: "Utilisateur: \(turn.input)\nAssistant: \(turn.output)",
                    content: "Utilisateur: \(turn.input)\nAssistant: \(turn.output)",
                    sourceId: "parlure_dialogue_capture",
                    captureType: "dialogue_pair",
                    language: "fr-CA",
                    dialectRegion: "Quebec",
                    register: "informal",
                    containsPersonalData: containsPersonalData,
                    detectedPII: piiDetectedOrKnown,
                    userMarkedSensitive: options.markContainsPersonalData,
                    requiresReview: requiresReview,
                    consentForTraining: consent,
                    syntheticComponent: assistantGenerated,
                    provenance: "Parlure iOS local speech capture",
                    license: "private_first_party_consent_required",
                    reviewStatus: turn.reviewStatus.rawValue,
                    outputSource: turn.outputSource.rawValue,
                    redactedText: options.exportRedactedText ? PIIRedactor.redact(text: "Utilisateur: \(turn.input)\nAssistant: \(turn.output)") : nil
                ))
            }

            return DialogueRawExportRecord(
                schemaVersion: "parlure.raw.dialogue.v1",
                id: turn.id.uuidString,
                timestamp: turn.timestamp,
                type: "dialogue_pair",
                input: turn.input,
                output: turn.output,
                inputLocale: turn.inputLocale,
                recognizerLocale: turn.recognizerLocale,
                outputSource: turn.outputSource.rawValue,
                glossaryHintUsed: turn.glossaryHintUsed,
                reviewStatus: turn.reviewStatus.rawValue,
                containsPersonalData: containsPersonalData,
                detectedPII: piiDetectedOrKnown,
                userMarkedSensitive: options.markContainsPersonalData,
                consentForTraining: consent,
                syntheticOutput: syntheticOutput,
                humanOutput: !assistantGenerated,
                assistantGenerated: assistantGenerated,
                notes: turn.notes
            )
        }

        let glossaryRecords = glossary.map { item in
            let quality = GlossaryQualityValidator.validate(utterance: item.utterance, explanation: item.explanation, unclearTerms: item.unclearTerms, detectedTerms: [])
            if quality.staleTermsDetected { staleUnclearTermsCount += 1 }
            if quality.weakExplanation { weakExplanationCount += 1 }

            let pii = PIIRedactor.containsPII(text: item.utterance + " " + item.explanation)
            let piiDetectedOrKnown = pii || item.containsPersonalData
            if piiDetectedOrKnown { piiDetectedCount += 1 }
            if item.reviewStatus == .pendingReview { pendingReviewCount += 1 }
            if item.reviewStatus == .accepted { acceptedCount += 1 }
            if item.reviewStatus == .redacted { redactedCount += 1 }
            if item.reviewStatus == .rejected { rejectedExcludedCount += 1 }

            let consent = trainingConsent(global: options.allowTrainingExport, itemConsent: item.consentForTraining, reviewStatus: item.reviewStatus)
            let requiresReview = options.requireReviewBeforeExport || item.reviewStatus == .pendingReview
            let containsPersonalData = pii || item.containsPersonalData || options.markContainsPersonalData
            if options.markContainsPersonalData { sensitiveMarkedCount += 1 }

            if item.reviewStatus != .rejected {
                qfrRecords.append(QFRImportRecord(
                    text: "Expression: \(item.utterance)\nExplication: \(item.explanation)",
                    content: "Expression: \(item.utterance)\nExplication: \(item.explanation)",
                    sourceId: "parlure_user_capture",
                    captureType: "idiom_clarification",
                    language: "fr-CA",
                    dialectRegion: "Quebec",
                    register: "informal",
                    containsPersonalData: containsPersonalData,
                    detectedPII: piiDetectedOrKnown,
                    userMarkedSensitive: options.markContainsPersonalData,
                    requiresReview: requiresReview,
                    consentForTraining: consent,
                    syntheticComponent: false,
                    provenance: "Parlure iOS local speech capture",
                    license: "private_first_party_consent_required",
                    reviewStatus: item.reviewStatus.rawValue,
                    outputSource: nil,
                    redactedText: options.exportRedactedText ? PIIRedactor.redact(text: "Expression: \(item.utterance)\nExplication: \(item.explanation)") : nil
                ))
            }

            return GlossaryRawExportRecord(
                schemaVersion: "parlure.raw.glossary.v1",
                id: item.id.uuidString,
                timestamp: item.timestamp,
                type: "idiom_clarification",
                utterance: item.utterance,
                unclearTerms: item.unclearTerms,
                explanation: item.explanation,
                region: item.region,
                reviewStatus: item.reviewStatus.rawValue,
                containsPersonalData: containsPersonalData,
                detectedPII: piiDetectedOrKnown,
                userMarkedSensitive: options.markContainsPersonalData,
                consentForTraining: consent,
                syntheticOutput: false,
                humanOutput: true,
                assistantGenerated: false,
                notes: item.notes
            )
        }

        try writeJSONL(dialogueRecords, to: dialoguesURL)
        try writeJSONL(glossaryRecords, to: glossaryURL)
        try writeJSONL(qfrRecords, to: qfrURL)
        try buildTSV(turns: turns, glossary: glossary).write(to: parallelURL, atomically: true, encoding: .utf8)

        let meta = ExportMetaRecord(
            appName: "Parlure",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            exportTimestamp: Date(),
            schemaVersions: ["parlure.raw.dialogue.v1", "parlure.raw.glossary.v1"],
            dialogueCount: turns.count,
            glossaryCount: glossary.count,
            qfrImportCount: qfrRecords.count,
            rejectedExcludedCount: rejectedExcludedCount,
            pendingReviewCount: pendingReviewCount,
            acceptedCount: acceptedCount,
            redactedCount: redactedCount,
            piiDetectedCount: piiDetectedCount,
            sensitiveMarkedCount: sensitiveMarkedCount,
            defaultLocale: "fr-CA",
            consentSettings: ["allow_training_export": options.allowTrainingExport],
            privacyFlags: [
                "mark_contains_personal_data": options.markContainsPersonalData,
                "require_review_before_export": options.requireReviewBeforeExport,
                "export_redacted_text": options.exportRedactedText
            ],
            warning: "Review and redact records before production/commercial training use."
        )

        let pretty = JSONEncoder()
        pretty.outputFormatting = [.prettyPrinted, .sortedKeys]
        pretty.dateEncodingStrategy = .iso8601
        try pretty.encode(meta).write(to: metaURL)

        let trainingEligibleCount = qfrRecords.filter(\.consentForTraining).count
        let requiresReviewCount = qfrRecords.filter(\.requiresReview).count
        let qualityWarnings = [
            options.allowTrainingExport ? nil : "training export disabled",
            pendingReviewCount > 0 ? "records require review" : nil,
            pendingReviewCount > 0 ? "pending review records present" : nil,
            trainingEligibleCount == 0 ? "no records are training eligible" : nil,
            acceptedCount > 0 ? "all accepted records must be manually reviewed" : nil,
            options.markContainsPersonalData ? "sensitive marking enabled" : nil,
            assistantGeneratedCount > 0 ? "assistant-generated records are synthetic" : nil,
            staleUnclearTermsCount > 0 || weakExplanationCount > 0 ? "some glossary terms may require manual correction" : nil
        ].compactMap { $0 }

        let quality: [String: Any] = [
            "total_records": turns.count + glossary.count,
            "accepted": acceptedCount,
            "pending_review": pendingReviewCount,
            "rejected": rejectedExcludedCount,
            "stale_unclear_terms_count": staleUnclearTermsCount,
            "weak_explanation_count": weakExplanationCount,
            "assistant_generated_count": assistantGeneratedCount,
            "manual_human_count": manualHumanCount,
            "detected_pii_count": piiDetectedCount,
            "sensitive_marked_count": sensitiveMarkedCount,
            "training_eligible_count": trainingEligibleCount,
            "requires_review_count": requiresReviewCount,
            "warnings": qualityWarnings
        ]
        let qData = try JSONSerialization.data(withJSONObject: quality, options: [.prettyPrinted, .sortedKeys])
        try qData.write(to: qualityURL)

        return ExportResult(files: [dialoguesURL, glossaryURL, qfrURL, parallelURL, metaURL, qualityURL], dialogueCount: turns.count, glossaryCount: glossary.count, qfrCount: qfrRecords.count, rejectedExcludedCount: rejectedExcludedCount)
    }

    func buildTSV(turns: [DialogueTurn], glossary: [GlossaryEntry]) -> String {
        var content = "type\tinput\toutput\n"
        for turn in turns {
            content += "dialogue\t\(escapeTSV(turn.input))\t\(escapeTSV(turn.output))\n"
        }
        for entry in glossary {
            content += "idiom\t\(escapeTSV(entry.utterance))\t\(escapeTSV(entry.explanation))\n"
        }
        return content
    }

    func trainingConsent(global: Bool, itemConsent: Bool, reviewStatus: ReviewStatus) -> Bool {
        guard global, itemConsent else { return false }
        guard reviewStatus == .accepted else { return false }
        return true
    }

    private func writeJSONL<T: Encodable>(_ records: [T], to url: URL) throws {
        let lines = try records.map { record -> String in
            let data = try encoder.encode(record)
            return String(decoding: data, as: UTF8.self)
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func escapeTSV(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
