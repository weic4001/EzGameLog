import Foundation

enum DiagnosticAggregator {
    static func aggregate(
        events: [LogEvent],
        targetPIDs: Set<Int> = [],
        targetPackage: String? = nil
    ) -> [DiagnosticIssue] {
        let logEvents = events.filter { $0.kind == .log }
        var grouped: [String: DiagnosticIssue] = [:]
        var consumedContextEventIDs = Set<UUID>()

        for (index, event) in logEvents.enumerated() {
            guard !consumedContextEventIDs.contains(event.id) else { continue }
            guard let kind = classify(event) else { continue }
            guard isRelevant(
                event,
                targetPIDs: targetPIDs,
                targetPackage: targetPackage
            ) else { continue }
            let context = diagnosticContext(
                startingAt: index,
                in: logEvents,
                kind: kind
            )
            let signature = makeSignature(kind: kind, context: context)
            let title = makeTitle(kind: kind, context: context)
            let key = "\(kind.rawValue):\(signature)"
            let eventIDs = context.map(\.id)
            consumedContextEventIDs.formUnion(context.dropFirst().map(\.id))

            if var existing = grouped[key] {
                existing.lastOccurredAt = max(existing.lastOccurredAt, event.occurredAt)
                existing.occurrenceCount += 1
                existing.eventIDs.append(contentsOf: eventIDs.filter { !existing.eventIDs.contains($0) })
                grouped[key] = existing
            } else {
                grouped[key] = DiagnosticIssue(
                    id: UUID(),
                    kind: kind,
                    signature: signature,
                    title: title,
                    // Keep the complete bounded diagnostic context so P2 Native
                    // symbolication can resolve every tombstone frame, not just
                    // the first few lines shown in compact UI summaries.
                    summary: context.map(\.message).joined(separator: "\n"),
                    firstOccurredAt: event.occurredAt,
                    lastOccurredAt: event.occurredAt,
                    occurrenceCount: 1,
                    eventIDs: eventIDs
                )
            }
        }

        return grouped.values.sorted {
            if $0.lastOccurredAt == $1.lastOccurredAt {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.lastOccurredAt > $1.lastOccurredAt
        }
    }

    static func issue(containing eventID: UUID, in issues: [DiagnosticIssue]) -> DiagnosticIssue? {
        issues.first { $0.eventIDs.contains(eventID) }
    }

    private static func isRelevant(
        _ event: LogEvent,
        targetPIDs: Set<Int>,
        targetPackage: String?
    ) -> Bool {
        let normalizedPackage = targetPackage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let hasTarget = !targetPIDs.isEmpty || normalizedPackage?.isEmpty == false
        guard hasTarget else { return true }
        if event.pid.map(targetPIDs.contains) == true {
            return true
        }
        guard let normalizedPackage, !normalizedPackage.isEmpty else { return false }
        return "\(event.tag) \(event.message)"
            .lowercased()
            .contains(normalizedPackage)
    }

    private static func classify(_ event: LogEvent) -> DiagnosticIssueKind? {
        let text = "\(event.tag) \(event.message)".lowercased()
        if text.contains("fatal exception")
            || text.contains("uncaught exception") {
            return .javaCrash
        }
        if text.contains("anr in")
            || text.contains("application not responding")
            || (event.tag.caseInsensitiveCompare("ActivityManager") == .orderedSame
                && text.contains("anr")) {
            return .anr
        }
        if text.contains("fatal signal")
            || text.contains("signal 11")
            || text.contains("signal 6")
            || (event.buffer == .crash && text.contains("backtrace")) {
            return .nativeCrash
        }
        return nil
    }

    private static func diagnosticContext(
        startingAt index: Int,
        in events: [LogEvent],
        kind: DiagnosticIssueKind
    ) -> [LogEvent] {
        let first = events[index]
        var result = [first]
        for candidate in events.dropFirst(index + 1).prefix(40) {
            guard candidate.occurredAt.timeIntervalSince(first.occurredAt) <= 5 else { break }
            guard classify(candidate) == nil else { continue }
            let sameProcess = first.pid == nil || candidate.pid == nil || candidate.pid == first.pid
            let isStackLine = candidate.message.trimmingCharacters(in: .whitespaces)
                .hasPrefix("at ")
                || candidate.message.contains("Caused by:")
                || candidate.message.contains("backtrace:")
                || candidate.message.contains("native:")
            let sameDiagnosticTag = candidate.tag == first.tag
                || candidate.buffer == .crash
                || (kind == .javaCrash && candidate.tag == "AndroidRuntime")
            guard sameProcess && (isStackLine || sameDiagnosticTag) else { continue }
            result.append(candidate)
        }
        return result
    }

    private static func makeTitle(
        kind: DiagnosticIssueKind,
        context: [LogEvent]
    ) -> String {
        let preferred = context.lazy.map(\.message).first { message in
            let lower = message.lowercased()
            switch kind {
            case .javaCrash:
                return lower.contains("exception") || lower.contains("error")
            case .nativeCrash:
                return lower.contains("fatal signal") || lower.contains("signal ")
            case .anr:
                return lower.contains("anr")
            }
        }
        let trimmed = preferred?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? String(trimmed!.prefix(120)) : kind.title
    }

    private static func makeSignature(
        kind: DiagnosticIssueKind,
        context: [LogEvent]
    ) -> String {
        let source = makeTitle(kind: kind, context: context).lowercased()
        let withoutHex = source.replacingOccurrences(
            of: #"0x[0-9a-f]+"#,
            with: "<hex>",
            options: .regularExpression
        )
        let withoutNumbers = withoutHex.replacingOccurrences(
            of: #"\b\d+\b"#,
            with: "<n>",
            options: .regularExpression
        )
        return withoutNumbers
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
