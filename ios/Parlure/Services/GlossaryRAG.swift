//
//  GlossaryRAG.swift
//  Parlure
//
//  TF-IDF semantic search over the user's glossary entries.
//

import Foundation

struct GlossaryMatch {
    let entry: GlossaryEntry
    let score: Double
}

@MainActor
final class GlossaryRAG {
    private var entries: [GlossaryEntry] = []
    private var docTerms: [[String]] = []
    private var idf: [String: Double] = [:]
    private var docVectors: [[String: Double]] = []

    func reload(_ entries: [GlossaryEntry]) {
        self.entries = entries
        rebuild()
    }

    private func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let cleaned = lowered.replacingOccurrences(of: "[^\\p{L}\\p{N}\\s']", with: " ", options: .regularExpression)
        let words = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        var grams = words
        if words.count > 1 {
            for i in 0..<(words.count - 1) {
                grams.append("\(words[i]) \(words[i+1])")
            }
        }
        return grams
    }

    private func rebuild() {
        docTerms = entries.map { tokenize([$0.utterance, $0.unclearTerms.joined(separator: " "), $0.explanation].joined(separator: " ")) }
        idf.removeAll()
        let n = Double(max(docTerms.count, 1))
        var df: [String: Int] = [:]
        for terms in docTerms {
            for term in Set(terms) { df[term, default: 0] += 1 }
        }
        for (term, count) in df {
            idf[term] = log((n + 1) / (Double(count) + 1)) + 1
        }
        docVectors = docTerms.map { terms in
            var tf: [String: Int] = [:]
            for t in terms { tf[t, default: 0] += 1 }
            var vec: [String: Double] = [:]
            for (t, c) in tf {
                vec[t] = Double(c) * (idf[t] ?? 0)
            }
            return vec
        }
    }

    func bestMatch(for query: String, threshold: Double = 0.22) -> GlossaryMatch? {
        guard !entries.isEmpty else { return nil }
        let qTerms = tokenize(query)
        var qTF: [String: Int] = [:]
        for t in qTerms { qTF[t, default: 0] += 1 }
        var qVec: [String: Double] = [:]
        for (t, c) in qTF { qVec[t] = Double(c) * (idf[t] ?? 0) }

        var bestIdx = -1
        var bestScore = 0.0
        for (i, dv) in docVectors.enumerated() {
            let score = cosine(qVec, dv)
            if score > bestScore { bestScore = score; bestIdx = i }
        }
        guard bestIdx >= 0, bestScore >= threshold else { return nil }
        return GlossaryMatch(entry: entries[bestIdx], score: bestScore)
    }

    private func cosine(_ a: [String: Double], _ b: [String: Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for (_, v) in a { na += v * v }
        for (_, v) in b { nb += v * v }
        let small = a.count < b.count ? a : b
        let big = a.count < b.count ? b : a
        for (k, v) in small { if let bv = big[k] { dot += v * bv } }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (sqrt(na) * sqrt(nb))
    }
}
