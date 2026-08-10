import Foundation

enum LogDropDetector {
    static func reportedDroppedLineCount(in event: LogEvent) -> UInt64 {
        guard event.kind == .log else { return 0 }
        let source = "\(event.tag) \(event.message) \(event.rawText)"
        let lowercaseTag = event.tag.lowercased()
        guard lowercaseTag == "chatty"
                || lowercaseTag == "logcat" else {
            return 0
        }

        for expression in expressions {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            guard let match = expression.firstMatch(in: source, range: range),
                  match.numberOfRanges > 1,
                  let countRange = Range(match.range(at: 1), in: source),
                  let count = UInt64(source[countRange]) else {
                continue
            }
            return count
        }
        return 0
    }

    private static let expressions: [NSRegularExpression] = [
        try! NSRegularExpression(
            pattern: #"(?i)\b(?:dropped|lost|expired|identical)\s+(\d+)\s+lines?\b"#
        ),
        try! NSRegularExpression(
            pattern: #"(?i)\b(\d+)\s+lines?\s+(?:dropped|lost|expired|identical)\b"#
        )
    ]
}
