import Foundation

enum LogFilterEngine {
    static func filter(
        events: [LogEvent],
        configuration: LogFilterConfiguration,
        targetPIDs: Set<Int>
    ) throws -> [LogEvent] {
        let includedTags = tokens(configuration.includedTags)
        let excludedTags = tokens(configuration.excludedTags)
        let customPIDs = Set(tokens(configuration.customPIDs ?? "").compactMap(Int.init))
        let query = configuration.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let expression: NSRegularExpression?
        if configuration.usesRegularExpression, !query.isEmpty {
            do {
                expression = try NSRegularExpression(
                    pattern: query,
                    options: configuration.isCaseSensitive ? [] : [.caseInsensitive]
                )
            } catch {
                throw LogFilterError.invalidRegularExpression(error.localizedDescription)
            }
        } else {
            expression = nil
        }

        return events.filter { event in
            if !event.isMarker {
                guard configuration.enabledLevels.contains(event.level) else { return false }
                if let minimumLevel = configuration.minimumLevel,
                   event.level.severity < minimumLevel.severity {
                    return false
                }
                switch configuration.pidScope {
                case .target:
                    if event.pid.map(targetPIDs.contains) != true {
                        return false
                    }
                case .custom:
                    if !customPIDs.isEmpty,
                       event.pid.map(customPIDs.contains) != true {
                        return false
                    }
                case .all:
                    break
                }
                if !includedTags.isEmpty,
                   !includedTags.contains(where: { contains(event.tag, token: $0, caseSensitive: false) }) {
                    return false
                }
                if excludedTags.contains(where: { contains(event.tag, token: $0, caseSensitive: false) }) {
                    return false
                }
            }

            guard !query.isEmpty else { return true }
            let searchable = "\(event.tag)\n\(event.message)\n\(event.rawText)"
            if let expression {
                let range = NSRange(searchable.startIndex..<searchable.endIndex, in: searchable)
                return expression.firstMatch(in: searchable, range: range) != nil
            }
            return contains(
                searchable,
                token: query,
                caseSensitive: configuration.isCaseSensitive
            )
        }
    }

    private static func tokens(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func contains(_ text: String, token: String, caseSensitive: Bool) -> Bool {
        if caseSensitive {
            return text.contains(token)
        }
        return text.localizedCaseInsensitiveContains(token)
    }
}
