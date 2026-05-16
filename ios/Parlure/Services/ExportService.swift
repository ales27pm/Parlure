//
//  ExportService.swift
//  Parlure
//

import Foundation

struct ExportResult {
    let files: [URL]
    let dialogueCount: Int
    let glossaryCount: Int
}

@MainActor
final class ExportService {
    static let shared = ExportService()

    private var exportDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func export(turns: [DialogueTurn], glossary: [GlossaryEntry]) throws -> ExportResult {
        let session = "parlure_\(Int(Date().timeIntervalSince1970))"
        var files: [URL] = []

        let turnsURL = exportDir.appendingPathComponent("\(session)_dialogues.jsonl")
        let glossaryURL = exportDir.appendingPathComponent("\(session)_glossary.jsonl")
        let parallelURL = exportDir.appendingPathComponent("\(session)_parallel.tsv")
        let metaURL = exportDir.appendingPathComponent("\(session)_meta.json")

        // Dialogues JSONL
        let turnsLines = turns.map { t -> String in
            let dict: [String: Any] = [
                "timestamp": Int(t.timestamp.timeIntervalSince1970),
                "type": "dialogue_pair",
                "input": t.input,
                "output": t.output
            ]
            return jsonLine(dict)
        }
        try turnsLines.joined(separator: "\n").write(to: turnsURL, atomically: true, encoding: .utf8)
        files.append(turnsURL)

        // Glossary JSONL
        let glossaryLines = glossary.map { g -> String in
            let dict: [String: Any] = [
                "timestamp": Int(g.timestamp.timeIntervalSince1970),
                "type": "idiom_clarification",
                "utterance": g.utterance,
                "unclear_terms": g.unclearTerms,
                "explanation": g.explanation,
                "region": g.region
            ]
            return jsonLine(dict)
        }
        try glossaryLines.joined(separator: "\n").write(to: glossaryURL, atomically: true, encoding: .utf8)
        files.append(glossaryURL)

        // TSV parallel (utterance \t explanation, dialogue input \t output)
        var tsv = "type\tinput\toutput\n"
        for t in turns {
            tsv += "dialogue\t\(escape(t.input))\t\(escape(t.output))\n"
        }
        for g in glossary {
            tsv += "idiom\t\(escape(g.utterance))\t\(escape(g.explanation))\n"
        }
        try tsv.write(to: parallelURL, atomically: true, encoding: .utf8)
        files.append(parallelURL)

        // Meta
        let meta: [String: Any] = [
            "session": session,
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "dialogue_count": turns.count,
            "glossary_count": glossary.count
        ]
        let metaData = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted])
        try metaData.write(to: metaURL)
        files.append(metaURL)

        return ExportResult(files: files, dialogueCount: turns.count, glossaryCount: glossary.count)
    }

    private func jsonLine(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
    }
}
