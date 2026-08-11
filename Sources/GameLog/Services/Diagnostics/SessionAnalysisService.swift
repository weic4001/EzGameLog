import Foundation

enum SessionAnalysisService {
    static func snapshot(
        session: DebugSession,
        events: [LogEvent],
        incidentCount: Int,
        logByteCount: Int64
    ) -> SessionAnalysisSnapshot {
        var levelCounts: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]
        var logEventCount = 0

        for event in events {
            guard event.kind == .log else { continue }
            logEventCount += 1
            levelCounts[event.level.rawValue, default: 0] += 1
            if !event.tag.isEmpty {
                tagCounts[event.tag, default: 0] += 1
            }
        }

        return SessionAnalysisSnapshot(
            sessionID: session.id,
            targetPackage: session.targetPackage,
            deviceSerial: session.device.serial,
            sessionCreatedAt: session.createdAt,
            eventCount: events.count,
            logEventCount: logEventCount,
            markerCount: events.count - logEventCount,
            levelCounts: levelCounts,
            tagCounts: tagCounts,
            incidentCount: incidentCount,
            artifactCount: session.artifacts.count,
            logByteCount: logByteCount,
            diagnosticIssues: DiagnosticAggregator.aggregate(
                events: events,
                targetPIDs: session.diagnosticTargetPIDs,
                targetPackage: session.targetPackage
            )
        )
    }

    static func trends(
        snapshots: [SessionAnalysisSnapshot],
        targetPackage: String? = nil,
        symbolicationReports: [UUID: SessionSymbolicationReport] = [:]
    ) -> [DiagnosticTrend] {
        let scoped = snapshots.filter {
            guard let targetPackage, !targetPackage.isEmpty else { return true }
            return $0.targetPackage == targetPackage
        }
        struct Accumulator {
            var issue: DiagnosticIssue
            var sessionIDs: Set<UUID>
            var occurrenceCount: Int
        }
        var grouped: [String: Accumulator] = [:]

        for snapshot in scoped {
            for issue in snapshot.diagnosticIssues {
                let key = "\(issue.kind.rawValue):\(issue.signature)"
                if var existing = grouped[key] {
                    existing.sessionIDs.insert(snapshot.sessionID)
                    existing.occurrenceCount += issue.occurrenceCount
                    if issue.lastOccurredAt > existing.issue.lastOccurredAt {
                        existing.issue = issue
                    }
                    grouped[key] = existing
                } else {
                    grouped[key] = Accumulator(
                        issue: issue,
                        sessionIDs: [snapshot.sessionID],
                        occurrenceCount: issue.occurrenceCount
                    )
                }
            }
        }

        return grouped.values.map { value in
            let allIssues = scoped
                .flatMap(\.diagnosticIssues)
                .filter {
                    $0.kind == value.issue.kind
                        && $0.signature == value.issue.signature
                }
            let issueIDs = Set(allIssues.map(\.id))
            let symbolicated = symbolicationReports.values
                .flatMap(\.frames)
                .first {
                    issueIDs.contains($0.frame.diagnosticID)
                        && $0.bestFunction != nil
                }
            let hint = stackHint(from: value.issue.summary)
            let source = symbolicated?.sourceFrames.first
            return DiagnosticTrend(
                kind: value.issue.kind,
                signature: value.issue.signature,
                title: value.issue.title,
                firstOccurredAt: allIssues.map(\.firstOccurredAt).min()
                    ?? value.issue.firstOccurredAt,
                lastOccurredAt: allIssues.map(\.lastOccurredAt).max()
                    ?? value.issue.lastOccurredAt,
                sessionCount: value.sessionIDs.count,
                occurrenceCount: value.occurrenceCount,
                sessionIDs: value.sessionIDs.sorted { $0.uuidString < $1.uuidString },
                symbolHint: symbolicated?.bestFunction ?? hint.symbol,
                sourceLocationHint: source.map {
                    guard let file = $0.file else { return hint.location ?? "" }
                    if let line = $0.line {
                        return "\(file):\(line)"
                    }
                    return file
                }.flatMap { $0.isEmpty ? nil : $0 } ?? hint.location
            )
        }
        .sorted {
            if $0.lastOccurredAt == $1.lastOccurredAt {
                return $0.occurrenceCount > $1.occurrenceCount
            }
            return $0.lastOccurredAt > $1.lastOccurredAt
        }
    }

    static func compare(
        baseline: SessionAnalysisSnapshot,
        comparison: SessionAnalysisSnapshot
    ) -> SessionComparison {
        let baselineIssues = Dictionary(
            uniqueKeysWithValues: baseline.diagnosticIssues.map {
                ("\($0.kind.rawValue):\($0.signature)", $0)
            }
        )
        let comparisonIssues = Dictionary(
            uniqueKeysWithValues: comparison.diagnosticIssues.map {
                ("\($0.kind.rawValue):\($0.signature)", $0)
            }
        )
        let baselineKeys = Set(baselineIssues.keys)
        let comparisonKeys = Set(comparisonIssues.keys)
        let tagNames = Set(baseline.tagCounts.keys).union(comparison.tagCounts.keys)
        let changedTags = tagNames.compactMap { tag -> SessionMetricDelta? in
            let lhs = baseline.tagCounts[tag, default: 0]
            let rhs = comparison.tagCounts[tag, default: 0]
            guard lhs != rhs else { return nil }
            return SessionMetricDelta(title: tag, baseline: lhs, comparison: rhs)
        }
        .sorted { abs($0.delta) > abs($1.delta) }

        return SessionComparison(
            baselineSessionID: baseline.sessionID,
            comparisonSessionID: comparison.sessionID,
            metrics: [
                SessionMetricDelta(
                    title: String(localized: "日志"),
                    baseline: baseline.logEventCount,
                    comparison: comparison.logEventCount
                ),
                SessionMetricDelta(
                    title: String(localized: "错误"),
                    baseline: baseline.errorCount,
                    comparison: comparison.errorCount
                ),
                SessionMetricDelta(
                    title: String(localized: "诊断"),
                    baseline: baseline.diagnosticIssues.count,
                    comparison: comparison.diagnosticIssues.count
                ),
                SessionMetricDelta(
                    title: String(localized: "问题标记"),
                    baseline: baseline.incidentCount,
                    comparison: comparison.incidentCount
                ),
                SessionMetricDelta(
                    title: String(localized: "证据"),
                    baseline: baseline.artifactCount,
                    comparison: comparison.artifactCount
                )
            ],
            addedDiagnostics: comparisonKeys.subtracting(baselineKeys)
                .compactMap { comparisonIssues[$0] }
                .sorted { $0.lastOccurredAt > $1.lastOccurredAt },
            resolvedDiagnostics: baselineKeys.subtracting(comparisonKeys)
                .compactMap { baselineIssues[$0] }
                .sorted { $0.lastOccurredAt > $1.lastOccurredAt },
            recurringDiagnostics: baselineKeys.intersection(comparisonKeys)
                .compactMap { comparisonIssues[$0] }
                .sorted { $0.lastOccurredAt > $1.lastOccurredAt },
            changedTags: Array(changedTags.prefix(20))
        )
    }

    private static func stackHint(from summary: String) -> (symbol: String?, location: String?) {
        if let expression = try? NSRegularExpression(
            pattern: #"\bat\s+([A-Za-z0-9_.$<>]+)\(([^():]+):(\d+)\)"#
        ) {
            let range = NSRange(summary.startIndex..., in: summary)
            if let match = expression.firstMatch(in: summary, range: range),
               let symbolRange = Range(match.range(at: 1), in: summary),
               let fileRange = Range(match.range(at: 2), in: summary),
               let lineRange = Range(match.range(at: 3), in: summary) {
                return (
                    String(summary[symbolRange]),
                    "\(summary[fileRange]):\(summary[lineRange])"
                )
            }
        }

        if let expression = try? NSRegularExpression(
            pattern: #"#\d+\s+pc\s+[0-9a-fA-F]+\s+(\S+)(?:\s+\(([^)+]+))?"#
        ) {
            let range = NSRange(summary.startIndex..., in: summary)
            if let match = expression.firstMatch(in: summary, range: range),
               let libraryRange = Range(match.range(at: 1), in: summary) {
                let symbol = Range(match.range(at: 2), in: summary).map {
                    String(summary[$0]).trimmingCharacters(in: .whitespaces)
                }
                return (symbol, String(summary[libraryRange]))
            }
        }
        return (nil, nil)
    }
}
