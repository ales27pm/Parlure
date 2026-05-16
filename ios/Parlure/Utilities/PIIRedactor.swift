import Foundation

struct PIIMatch: Equatable {
    let type: String
    let value: String
}

enum PIIRedactor {
    private static let patterns: [(String, String)] = [
        ("email", #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#),
        ("phone", #"(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4})"#),
        ("postal_code", #"\b[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTV-Z][ -]?\d[ABCEGHJ-NPRSTV-Z]\d\b"#),
        ("url", #"https?://[^\s]+"#),
        ("long_number", #"\b\d{6,}\b"#),
        ("address_marker", #"(?i)\b(mon adresse|j'habite au|je demeure au)\b[^\n,.]*"#),
        ("name_marker", #"(?i)\bje m'appelle\b[^\n,.]*"#),
        ("phone_marker", #"(?i)\bmon téléphone\b[^\n,.]*"#)
    ]

    static func detect(text: String) -> [PIIMatch] {
        patterns.flatMap { type, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
            let ns = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
                PIIMatch(type: type, value: ns.substring(with: $0.range))
            }
        }
    }

    static func containsPII(text: String) -> Bool { !detect(text: text).isEmpty }

    static func redact(text: String) -> String {
        var result = text
        for m in detect(text: text).sorted(by: { $0.value.count > $1.value.count }) {
            result = result.replacingOccurrences(of: m.value, with: "[REDACTED_\(m.type.uppercased())]")
        }
        return result
    }
}
