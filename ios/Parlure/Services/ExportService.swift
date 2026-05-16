import Foundation

struct ExportOptions { var allowTrainingExport = false; var markContainsPersonalData = true; var requireReviewBeforeExport = true; var exportRedactedText = true }
struct ExportResult { let files:[URL]; let dialogueCount:Int; let glossaryCount:Int; let qfrCount:Int }

@MainActor final class ExportService {
    static let shared = ExportService()
    private let iso = ISO8601DateFormatter()
    private var exportDir: URL { let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("export", isDirectory: true); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }

    func export(turns:[DialogueTurn], glossary:[GlossaryEntry], options: ExportOptions) throws -> ExportResult {
        let stamp = String(Int(Date().timeIntervalSince1970)); let base = "parlure_\(stamp)"
        let dURL=exportDir.appendingPathComponent("\(base)_dialogues.raw.jsonl"); let gURL=exportDir.appendingPathComponent("\(base)_glossary.raw.jsonl"); let qURL=exportDir.appendingPathComponent("\(base)_qfr_import.jsonl"); let tsv=exportDir.appendingPathComponent("\(base)_parallel.tsv"); let mURL=exportDir.appendingPathComponent("\(base)_meta.json")
        var qrows:[[String:Any]]=[]
        let dLines = try turns.map { t -> String in
            let pii = PIIRedactor.containsPII(text: t.input + " " + t.output)
            let dict:[String:Any?] = ["schema_version":"parlure.raw.dialogue.v1","id":t.id.uuidString,"timestamp":iso.string(from:t.timestamp),"type":"dialogue_pair","input":t.input,"output":t.output,"input_locale":t.inputLocale,"recognizer_locale":t.recognizerLocale,"output_source":t.outputSource.rawValue,"glossary_hint_used":t.glossaryHintUsed,"review_status":t.reviewStatus.rawValue,"contains_personal_data":pii || t.containsPersonalData || options.markContainsPersonalData,"consent_for_training": options.allowTrainingExport && t.consentForTraining,"synthetic_output":true,"notes":t.notes as Any]
            qrows.append(qfrDialogue(t, containsPII: pii, options: options)); return try line(dict)
        }
        let gLines = try glossary.map { g -> String in
            let pii = PIIRedactor.containsPII(text: g.utterance + " " + g.explanation)
            let dict:[String:Any?] = ["schema_version":"parlure.raw.glossary.v1","id":g.id.uuidString,"timestamp":iso.string(from:g.timestamp),"type":"idiom_clarification","utterance":g.utterance,"unclear_terms":g.unclearTerms,"explanation":g.explanation,"region":g.region,"review_status":g.reviewStatus.rawValue,"contains_personal_data":pii || g.containsPersonalData || options.markContainsPersonalData,"consent_for_training": options.allowTrainingExport && g.consentForTraining,"synthetic_output":false,"notes":g.notes as Any]
            qrows.append(qfrGlossary(g, containsPII: pii, options: options)); return try line(dict)
        }
        try dLines.joined(separator:"\n").write(to:dURL, atomically:true, encoding:.utf8); try gLines.joined(separator:"\n").write(to:gURL, atomically:true, encoding:.utf8)
        try qrows.map{try line($0)}.joined(separator:"\n").write(to:qURL, atomically:true, encoding:.utf8)
        var t = "type\tinput\toutput\n"; turns.forEach { t += "dialogue\t\($0.input.replacingOccurrences(of: "\t", with: " "))\t\($0.output.replacingOccurrences(of: "\t", with: " "))\n"}; glossary.forEach { t += "idiom\t\($0.utterance)\t\($0.explanation)\n" }; try t.write(to: tsv, atomically: true, encoding: .utf8)
        let meta:[String:Any] = ["app_name":"Parlure","export_timestamp":iso.string(from:Date()),"schema_versions":["parlure.raw.dialogue.v1","parlure.raw.glossary.v1"],"dialogue_count":turns.count,"glossary_count":glossary.count,"qfr_import_count":qrows.count,"default_locale":"fr-CA","consent_settings":["allow_training_export":options.allowTrainingExport],"privacy_flags":["mark_contains_personal_data":options.markContainsPersonalData,"require_review_before_export":options.requireReviewBeforeExport,"export_redacted_text":options.exportRedactedText],"warning":"Review/redact before production/commercial training."]
        try JSONSerialization.data(withJSONObject: meta, options:[.prettyPrinted]).write(to:mURL)
        return .init(files:[dURL,gURL,qURL,tsv,mURL], dialogueCount:turns.count, glossaryCount:glossary.count, qfrCount:qrows.count)
    }
    private func qfrDialogue(_ t: DialogueTurn, containsPII: Bool, options: ExportOptions) -> [String:Any] { let base = "Utilisateur: \(t.input)\nAssistant: \(t.output)"; var r:[String:Any] = ["text":base,"content":base,"source_id":"parlure_dialogue_capture","capture_type":"dialogue_pair","language":"fr-CA","dialect_region":"Quebec","register":"informal","contains_personal_data":containsPII || options.markContainsPersonalData,"requires_review":options.requireReviewBeforeExport,"consent_for_training":options.allowTrainingExport && t.consentForTraining,"synthetic_component":true,"output_source":t.outputSource.rawValue,"provenance":"Parlure iOS local speech capture","license":"private_first_party_consent_required"]; if options.exportRedactedText { r["redacted_text"] = PIIRedactor.redact(text: base) }; return r }
    private func qfrGlossary(_ g: GlossaryEntry, containsPII: Bool, options: ExportOptions) -> [String:Any] { let base = "Expression: \(g.utterance)\nExplication: \(g.explanation)"; var r:[String:Any] = ["text":base,"content":base,"source_id":"parlure_user_capture","capture_type":"idiom_clarification","language":"fr-CA","dialect_region":"Quebec","register":"informal","contains_personal_data":containsPII || options.markContainsPersonalData,"requires_review":options.requireReviewBeforeExport,"consent_for_training":options.allowTrainingExport && g.consentForTraining,"synthetic_component":false,"provenance":"Parlure iOS local speech capture","license":"private_first_party_consent_required"]; if options.exportRedactedText { r["redacted_text"] = PIIRedactor.redact(text: base) }; return r }
    private func line(_ d: [String:Any?]) throws -> String { try line(d.compactMapValues{$0}) }
    private func line(_ d:[String:Any]) throws -> String { let data = try JSONSerialization.data(withJSONObject:d); return String(data:data, encoding:.utf8)! }
}
