import Foundation

enum LogRedactor {
    static func preview(
        events: [LogEvent],
        session: DebugSession,
        configuration: RedactionConfiguration = .recommended
    ) -> RedactionPreview {
        guard configuration.isEnabled else {
            return RedactionPreview(
                counts: [:],
                customRuleCounts: [:],
                sampleBefore: nil,
                sampleAfter: nil
            )
        }
        var counts: [RedactionCategory: Int] = [:]
        var customRuleCounts: [UUID: Int] = [:]
        var sampleBefore: String?
        var sampleAfter: String?

        for event in events {
            let source = event.rawText
            let result = redact(
                source,
                configuration: configuration,
                deviceSerial: session.device.serial
            )
            for (category, count) in result.counts {
                counts[category, default: 0] += count
            }
            for (ruleID, count) in result.customRuleCounts {
                customRuleCounts[ruleID, default: 0] += count
            }
            if sampleBefore == nil, result.text != source {
                sampleBefore = String(source.prefix(240))
                sampleAfter = String(result.text.prefix(240))
            }
        }
        return RedactionPreview(
            counts: counts,
            customRuleCounts: customRuleCounts,
            sampleBefore: sampleBefore,
            sampleAfter: sampleAfter
        )
    }

    static func redact(
        event: LogEvent,
        configuration: RedactionConfiguration,
        deviceSerial: String
    ) -> LogEvent {
        guard configuration.isEnabled else { return event }
        let message = redact(
            event.message,
            configuration: configuration,
            deviceSerial: deviceSerial
        ).text
        let rawText = redact(
            event.rawText,
            configuration: configuration,
            deviceSerial: deviceSerial
        ).text
        return LogEvent(
            id: event.id,
            occurredAt: event.occurredAt,
            receivedAtHostTime: event.receivedAtHostTime,
            timestampText: event.timestampText,
            pid: event.pid,
            tid: event.tid,
            level: event.level,
            tag: event.tag,
            message: message,
            rawText: rawText,
            buffer: event.buffer,
            kind: event.kind,
            evidenceID: event.evidenceID
        )
    }

    static func redactedSession(
        _ session: DebugSession,
        configuration: RedactionConfiguration
    ) -> DebugSession {
        guard configuration.isEnabled else { return session }
        let serial = configuration.categories.contains(.deviceSerial)
            ? replacement(for: .deviceSerial)
            : session.device.serial
        let adbPath = redact(
            session.adbPath,
            configuration: configuration,
            deviceSerial: session.device.serial
        ).text
        let device = AndroidDevice(
            serial: serial,
            state: session.device.state,
            model: session.device.model,
            product: session.device.product,
            transportID: configuration.categories.contains(.deviceSerial)
                ? nil
                : session.device.transportID,
            androidVersion: session.device.androidVersion,
            apiLevel: session.device.apiLevel,
            connectionType: session.device.connectionType
        )
        return DebugSession(
            id: session.id,
            createdAt: session.createdAt,
            endedAt: session.endedAt,
            timeZoneIdentifier: session.timeZoneIdentifier,
            device: device,
            targetPackage: session.targetPackage,
            initialPIDs: session.initialPIDs,
            observedPIDs: session.observedPIDs,
            adbPath: adbPath,
            adbVersion: session.adbVersion,
            buffers: session.buffers,
            initialPreset: session.initialPreset,
            initialFilterConfiguration: session.initialFilterConfiguration,
            artifacts: session.artifacts
        )
    }

    static func redact(
        incident: IncidentRecord,
        configuration: RedactionConfiguration,
        deviceSerial: String
    ) -> IncidentRecord {
        guard configuration.isEnabled else { return incident }
        return IncidentRecord(
            id: incident.id,
            createdAt: incident.createdAt,
            eventID: incident.eventID,
            title: redactText(
                incident.title,
                configuration: configuration,
                deviceSerial: deviceSerial
            ),
            note: redactText(
                incident.note,
                configuration: configuration,
                deviceSerial: deviceSerial
            ),
            evidenceIDs: incident.evidenceIDs,
            recordingID: incident.recordingID,
            recordingOffset: incident.recordingOffset,
            logWindowBefore: incident.logWindowBefore,
            logWindowAfter: incident.logWindowAfter
        )
    }

    static func redactText(
        _ source: String,
        configuration: RedactionConfiguration,
        deviceSerial: String
    ) -> String {
        redact(
            source,
            configuration: configuration,
            deviceSerial: deviceSerial
        ).text
    }

    private static func redact(
        _ source: String,
        configuration: RedactionConfiguration,
        deviceSerial: String
    ) -> (
        text: String,
        counts: [RedactionCategory: Int],
        customRuleCounts: [UUID: Int]
    ) {
        var text = source
        var counts: [RedactionCategory: Int] = [:]
        var customRuleCounts: [UUID: Int] = [:]

        for category in RedactionCategory.allCases where configuration.categories.contains(category) {
            if category == .deviceSerial {
                guard !deviceSerial.isEmpty else { continue }
                let count = text.components(separatedBy: deviceSerial).count - 1
                if count > 0 {
                    text = text.replacingOccurrences(
                        of: deviceSerial,
                        with: replacement(for: category)
                    )
                    counts[category, default: 0] += count
                }
                continue
            }
            for pattern in patterns(for: category) {
                guard let expression = try? NSRegularExpression(
                    pattern: pattern,
                    options: [.caseInsensitive]
                ) else { continue }
                let range = NSRange(text.startIndex..., in: text)
                let matches = expression.numberOfMatches(in: text, range: range)
                guard matches > 0 else { continue }
                text = expression.stringByReplacingMatches(
                    in: text,
                    range: range,
                    withTemplate: replacement(for: category)
                )
                counts[category, default: 0] += matches
            }
        }
        for rule in configuration.customRules where rule.isEnabled {
            guard let expression = try? NSRegularExpression(
                pattern: rule.pattern,
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let matches = expression.numberOfMatches(in: text, range: range)
            guard matches > 0 else { continue }
            text = expression.stringByReplacingMatches(
                in: text,
                range: range,
                withTemplate: rule.replacement
            )
            customRuleCounts[rule.id, default: 0] += matches
        }
        return (text, counts, customRuleCounts)
    }

    private static func patterns(for category: RedactionCategory) -> [String] {
        switch category {
        case .accessToken:
            [
                #"\bBearer\s+[A-Za-z0-9._~+/=-]{8,}"#,
                #"\b(token|authorization|api[_-]?key|secret|password)\s*[:=]\s*["']?[A-Za-z0-9._~+/=-]{6,}["']?"#
            ]
        case .accountIdentifier:
            [
                #"\b(user[_-]?id|account[_-]?id|uid|openid)\s*[:=]\s*["']?[A-Za-z0-9_-]{4,}["']?"#
            ]
        case .emailAddress:
            [#"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#]
        case .ipAddress:
            [#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#]
        case .localPath:
            [#"/(?:Users|home)/[^ \t\r\n\"']+"#]
        case .deviceSerial:
            []
        }
    }

    private static func replacement(for category: RedactionCategory) -> String {
        String(localized: "‹已脱敏:\(category.title)›")
    }
}
