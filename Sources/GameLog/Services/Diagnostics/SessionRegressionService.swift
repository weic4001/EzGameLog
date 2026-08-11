import Foundation

enum SessionRegressionService {
    static func align(
        baselineSession: DebugSession,
        baselineEvents: [LogEvent],
        baselineSnapshot: SessionAnalysisSnapshot,
        comparisonSession: DebugSession,
        comparisonEvents: [LogEvent],
        comparisonSnapshot: SessionAnalysisSnapshot
    ) -> SessionTimelineAlignment {
        if let diagnosticAnchor = matchingDiagnosticAnchor(
            baselineEvents: baselineEvents,
            baselineSnapshot: baselineSnapshot,
            comparisonEvents: comparisonEvents,
            comparisonSnapshot: comparisonSnapshot
        ) {
            return SessionTimelineAlignment(
                baselineSessionID: baselineSession.id,
                comparisonSessionID: comparisonSession.id,
                method: .matchingDiagnostic,
                comparisonOffset: diagnosticAnchor.baselineTime
                    .timeIntervalSince(diagnosticAnchor.comparisonTime),
                confidence: 0.95,
                anchor: diagnosticAnchor
            )
        }
        if let eventAnchor = matchingEventAnchor(
            baselineEvents: baselineEvents,
            comparisonEvents: comparisonEvents
        ) {
            return SessionTimelineAlignment(
                baselineSessionID: baselineSession.id,
                comparisonSessionID: comparisonSession.id,
                method: .matchingEvent,
                comparisonOffset: eventAnchor.baselineTime
                    .timeIntervalSince(eventAnchor.comparisonTime),
                confidence: 0.8,
                anchor: eventAnchor
            )
        }
        let fallback = TimelineAnchor(
            title: String(localized: "会话开始"),
            baselineEventID: nil,
            comparisonEventID: nil,
            baselineTime: baselineSession.createdAt,
            comparisonTime: comparisonSession.createdAt
        )
        return SessionTimelineAlignment(
            baselineSessionID: baselineSession.id,
            comparisonSessionID: comparisonSession.id,
            method: .sessionStart,
            comparisonOffset: baselineSession.createdAt
                .timeIntervalSince(comparisonSession.createdAt),
            confidence: 0.25,
            anchor: fallback
        )
    }

    static func regression(
        baseline: SessionAnalysisSnapshot,
        comparison: SessionAnalysisSnapshot,
        configuration: RegressionConfiguration? = nil
    ) -> RegressionReport {
        let configuration = configuration
            ?? .recommended(for: comparison.targetPackage)
        let thresholds = configuration.thresholds.normalized()
        var alerts: [RegressionAlert] = []
        let baselineIssues = Dictionary(
            uniqueKeysWithValues: baseline.diagnosticIssues.map {
                (issueKey($0), $0)
            }
        )
        let comparisonIssues = Dictionary(
            uniqueKeysWithValues: comparison.diagnosticIssues.map {
                (issueKey($0), $0)
            }
        )
        let addedKeys = Set(comparisonIssues.keys).subtracting(baselineIssues.keys)
        for key in addedKeys {
            guard let issue = comparisonIssues[key] else { continue }
            alerts.append(RegressionAlert(
                severity: .critical,
                title: String(localized: "新增\(issue.kind.title)"),
                detail: issue.title,
                metric: "diagnostic.\(key)",
                baselineValue: 0,
                comparisonValue: issue.occurrenceCount
            ))
        }
        for key in Set(comparisonIssues.keys).intersection(baselineIssues.keys) {
            guard let old = baselineIssues[key],
                  let new = comparisonIssues[key],
                  new.occurrenceCount - old.occurrenceCount
                    >= thresholds.recurringDiagnosticIncrease else {
                continue
            }
            alerts.append(RegressionAlert(
                severity: .warning,
                title: String(localized: "\(new.kind.title)出现次数增加"),
                detail: "\(new.title)：\(old.occurrenceCount) → \(new.occurrenceCount)",
                metric: "diagnostic-occurrence.\(key)",
                baselineValue: old.occurrenceCount,
                comparisonValue: new.occurrenceCount
            ))
        }

        let errorThreshold = max(
            thresholds.errorAbsoluteIncrease,
            Int(ceil(
                Double(baseline.errorCount)
                    * thresholds.errorRelativeIncrease
            ))
        )
        if comparison.errorCount - baseline.errorCount >= errorThreshold {
            alerts.append(RegressionAlert(
                severity: .warning,
                title: String(localized: "错误日志显著增加"),
                detail: String(localized: "错误与 Fatal 日志从 \(baseline.errorCount) 增加到 \(comparison.errorCount)。"),
                metric: "error-count",
                baselineValue: baseline.errorCount,
                comparisonValue: comparison.errorCount
            ))
        }

        let allTags = Set(baseline.tagCounts.keys).union(comparison.tagCounts.keys)
        let tagAlerts = allTags.compactMap { tag -> RegressionAlert? in
            let old = baseline.tagCounts[tag, default: 0]
            let new = comparison.tagCounts[tag, default: 0]
            let threshold = max(
                thresholds.tagAbsoluteIncrease,
                Int(ceil(Double(old) * thresholds.tagRelativeIncrease))
            )
            guard new - old >= threshold else { return nil }
            return RegressionAlert(
                severity: .warning,
                title: String(localized: "\(tag) 日志激增"),
                detail: String(localized: "Tag 计数从 \(old) 增加到 \(new)。"),
                metric: "tag.\(tag)",
                baselineValue: old,
                comparisonValue: new
            )
        }
        .sorted {
            ($0.comparisonValue ?? 0) - ($0.baselineValue ?? 0)
                > ($1.comparisonValue ?? 0) - ($1.baselineValue ?? 0)
        }
        alerts.append(contentsOf: tagAlerts.prefix(5))

        if baseline.logEventCount >= thresholds.logMinimumBaseline,
           comparison.logEventCount >= baseline.logEventCount
            + max(
                thresholds.logAbsoluteIncrease,
                Int(ceil(
                    Double(baseline.logEventCount)
                        * thresholds.logRelativeIncrease
                ))
            ) {
            alerts.append(RegressionAlert(
                severity: .info,
                title: String(localized: "整体日志量增加"),
                detail: String(localized: "日志从 \(baseline.logEventCount) 增加到 \(comparison.logEventCount)，建议检查重复输出。"),
                metric: "log-count",
                baselineValue: baseline.logEventCount,
                comparisonValue: comparison.logEventCount
            ))
        }

        alerts.sort {
            let left = severityRank($0.severity)
            let right = severityRank($1.severity)
            if left == right {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return left > right
        }
        let visibleAlerts = alerts.filter {
            !configuration.ignoredAlertKeys.contains($0.suppressionKey)
        }
        return RegressionReport(
            baselineSessionID: baseline.sessionID,
            comparisonSessionID: comparison.sessionID,
            generatedAt: Date(),
            alerts: visibleAlerts,
            suppressedAlertCount: alerts.count - visibleAlerts.count
        )
    }

    private static func matchingDiagnosticAnchor(
        baselineEvents: [LogEvent],
        baselineSnapshot: SessionAnalysisSnapshot,
        comparisonEvents: [LogEvent],
        comparisonSnapshot: SessionAnalysisSnapshot
    ) -> TimelineAnchor? {
        let baselineIssues = Dictionary(
            uniqueKeysWithValues: baselineSnapshot.diagnosticIssues.map {
                (issueKey($0), $0)
            }
        )
        let comparisonIssues = Dictionary(
            uniqueKeysWithValues: comparisonSnapshot.diagnosticIssues.map {
                (issueKey($0), $0)
            }
        )
        let commonKeys = Set(baselineIssues.keys).intersection(comparisonIssues.keys)
        for key in commonKeys.sorted() {
            guard let baselineID = baselineIssues[key]?.firstEventID,
                  let comparisonID = comparisonIssues[key]?.firstEventID,
                  let baselineEvent = baselineEvents.first(where: { $0.id == baselineID }),
                  let comparisonEvent = comparisonEvents.first(where: {
                      $0.id == comparisonID
                  }) else {
                continue
            }
            return TimelineAnchor(
                title: baselineIssues[key]?.title ?? String(localized: "共同诊断"),
                baselineEventID: baselineEvent.id,
                comparisonEventID: comparisonEvent.id,
                baselineTime: baselineEvent.occurredAt,
                comparisonTime: comparisonEvent.occurredAt
            )
        }
        return nil
    }

    private static func matchingEventAnchor(
        baselineEvents: [LogEvent],
        comparisonEvents: [LogEvent]
    ) -> TimelineAnchor? {
        let baselineUnique = uniqueAnchors(in: baselineEvents)
        let comparisonUnique = uniqueAnchors(in: comparisonEvents)
        let common = Set(baselineUnique.keys).intersection(comparisonUnique.keys)
        guard let bestKey = common.max(by: { lhs, rhs in
            anchorScore(lhs) < anchorScore(rhs)
        }),
        let baselineEvent = baselineUnique[bestKey],
        let comparisonEvent = comparisonUnique[bestKey] else {
            return nil
        }
        return TimelineAnchor(
            title: "\(baselineEvent.tag)：\(baselineEvent.message.prefix(80))",
            baselineEventID: baselineEvent.id,
            comparisonEventID: comparisonEvent.id,
            baselineTime: baselineEvent.occurredAt,
            comparisonTime: comparisonEvent.occurredAt
        )
    }

    private static func uniqueAnchors(in events: [LogEvent]) -> [String: LogEvent] {
        var first: [String: LogEvent] = [:]
        var duplicates: Set<String> = []
        for event in events where event.kind == .log {
            let key = normalizedEventKey(event)
            guard key.count >= 16 else { continue }
            if first[key] == nil {
                first[key] = event
            } else {
                duplicates.insert(key)
            }
        }
        for key in duplicates {
            first[key] = nil
        }
        return first
    }

    private static func normalizedEventKey(_ event: LogEvent) -> String {
        var value = "\(event.tag.lowercased())|\(event.message.lowercased())"
        value = value.replacingOccurrences(
            of: #"0x[0-9a-f]+"#,
            with: "<hex>",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\b\d+\b"#,
            with: "<n>",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return String(value.prefix(240))
    }

    private static func anchorScore(_ key: String) -> Int {
        min(240, key.count)
    }

    private static func issueKey(_ issue: DiagnosticIssue) -> String {
        "\(issue.kind.rawValue):\(issue.signature)"
    }

    private static func severityRank(_ severity: RegressionSeverity) -> Int {
        switch severity {
        case .info: 0
        case .warning: 1
        case .critical: 2
        }
    }
}
