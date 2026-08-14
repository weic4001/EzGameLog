import Foundation

struct IOSLogParser: Sendable {
    private var byteBuffer = Data()
    private var pendingEvent: LogEvent?
    private let referenceDate: Date
    private let calendar: Calendar

    init(referenceDate: Date = Date(), calendar: Calendar = .current) {
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    mutating func consume(_ data: Data) -> [LogEvent] {
        byteBuffer.append(data)
        var output: [LogEvent] = []
        var lineStart = byteBuffer.startIndex
        while let newline = byteBuffer[lineStart...].firstIndex(of: 0x0A) {
            let line = String(decoding: byteBuffer[lineStart..<newline], as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            consumeLine(line, output: &output)
            lineStart = byteBuffer.index(after: newline)
        }
        if lineStart > byteBuffer.startIndex {
            byteBuffer.removeSubrange(byteBuffer.startIndex..<lineStart)
        }
        return output
    }

    mutating func finish() -> [LogEvent] {
        var output: [LogEvent] = []
        if !byteBuffer.isEmpty {
            consumeLine(String(decoding: byteBuffer, as: UTF8.self), output: &output)
            byteBuffer.removeAll(keepingCapacity: false)
        }
        flushPending(into: &output)
        return output
    }

    private mutating func consumeLine(_ line: String, output: inout [LogEvent]) {
        if let event = parse(line) {
            flushPending(into: &output)
            pendingEvent = event
        } else if !line.isEmpty, var pendingEvent {
            pendingEvent.message += "\n" + line
            pendingEvent.rawText += "\n" + line
            self.pendingEvent = pendingEvent
        }
    }

    private mutating func flushPending(into output: inout [LogEvent]) {
        guard let pendingEvent else { return }
        output.append(pendingEvent)
        self.pendingEvent = nil
    }

    private func parse(_ line: String) -> LogEvent? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = Self.lineExpression.firstMatch(in: line, range: range),
              let dateRange = Range(match.range(at: 1), in: line),
              let processRange = Range(match.range(at: 2), in: line),
              let pidRange = Range(match.range(at: 3), in: line),
              let levelRange = Range(match.range(at: 4), in: line),
              let messageRange = Range(match.range(at: 5), in: line),
              let pid = Int(line[pidRange]),
              let occurredAt = date(from: String(line[dateRange])) else {
            return nil
        }

        let rawProcess = String(line[processRange])
        let process = rawProcess.split(separator: "(", maxSplits: 1).first.map(String.init)
            ?? rawProcess
        return LogEvent(
            occurredAt: occurredAt,
            receivedAtHostTime: Date(),
            timestampText: Self.tableTimeFormatter.string(from: occurredAt),
            pid: pid,
            tid: nil,
            level: Self.level(String(line[levelRange])),
            tag: process,
            message: String(line[messageRange]),
            rawText: line,
            buffer: .system
        )
    }

    private func date(from value: String) -> Date? {
        guard let parsed = Self.deviceDateFormatter.date(from: value) else { return nil }
        let components = calendar.dateComponents(
            [.month, .day, .hour, .minute, .second, .nanosecond],
            from: parsed
        )
        var currentYear = calendar.dateComponents([.year], from: referenceDate)
        currentYear.month = components.month
        currentYear.day = components.day
        currentYear.hour = components.hour
        currentYear.minute = components.minute
        currentYear.second = components.second
        currentYear.nanosecond = components.nanosecond
        guard var candidate = calendar.date(from: currentYear) else { return nil }
        if candidate.timeIntervalSince(referenceDate) > 36 * 60 * 60,
           let previousYear = calendar.date(byAdding: .year, value: -1, to: candidate) {
            candidate = previousYear
        }
        return candidate
    }

    private static func level(_ value: String) -> LogLevel {
        switch value.lowercased() {
        case "debug": .debug
        case "notice", "info", "default": .info
        case "warning": .warning
        case "error": .error
        case "fault": .fatal
        default: .unknown
        }
    }

    private static let lineExpression = try! NSRegularExpression(
        pattern: #"^([A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\.\d{6})\s+(.+?)\[(\d+)\]\s+<([^>]+)>:\s?(.*)$"#
    )

    private static let deviceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d HH:mm:ss.SSSSSS"
        return formatter
    }()

    private static let tableTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
