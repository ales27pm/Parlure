import Foundation

struct PIIMatch: Equatable {
    let type: String
    let value: String
    let range: NSRange
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
        let nsText = text as NSString
        var out: [PIIMatch] = []
        for (type, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                out.append(PIIMatch(type: type, value: nsText.substring(with: match.range), range: match.range))
            }
        }
        return out.sorted { $0.range.location < $1.range.location }
    }

    static func containsPII(text: String) -> Bool {
        !detect(text: text).isEmpty
    }

    static func redact(text: String) -> String {
        let matches = nonOverlapping(matches: detect(text: text))
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.sorted(by: { $0.range.location > $1.range.location }) {
            mutable.replaceCharacters(in: match.range, with: "[REDACTED_\(match.type.uppercased())]")
        }
        return mutable as String
    }

    private static func nonOverlapping(matches: [PIIMatch]) -> [PIIMatch] {
        var accepted: [PIIMatch] = []
        for m in matches.sorted(by: {
            if $0.range.location == $1.range.location { return $0.range.length > $1.range.length }
            return $0.range.location < $1.range.location
        }) {
            if accepted.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }) { continue }
            accepted.append(m)
        }
        return accepted
    }
}
