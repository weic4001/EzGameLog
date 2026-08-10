import Foundation

struct LogcatParser: Sendable {
    private var byteBuffer = Data()
    private var pendingEvent: LogEvent?
    private var currentBuffer: LogBufferName = .unknown
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
            let lineData = byteBuffer[lineStart..<newline]
            let line = String(decoding: lineData, as: UTF8.self)
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
            let line = String(decoding: byteBuffer, as: UTF8.self)
            byteBuffer.removeAll(keepingCapacity: false)
            consumeLine(line, output: &output)
        }
        if let pendingEvent {
            output.append(pendingEvent)
            self.pendingEvent = nil
        }
        return output
    }

    private mutating func consumeLine(_ line: String, output: inout [LogEvent]) {
        if line.hasPrefix("--------- beginning of") {
            flushPending(into: &output)
            let bufferName = line
                .split(separator: " ")
                .last
                .flatMap { LogBufferName(rawValue: String($0)) } ?? .unknown
            currentBuffer = bufferName
            output.append(LogEvent(
                timestampText: "",
                pid: nil,
                tid: nil,
                level: .info,
                tag: "Logcat",
                message: line,
                rawText: line,
                isMarker: true,
                buffer: bufferName
            ))
            return
        }

        if let parsed = parseThreadtimeLine(line) {
            flushPending(into: &output)
            pendingEvent = parsed
        } else if var event = pendingEvent {
            event.message += "\n" + line
            event.rawText += "\n" + line
            pendingEvent = event
        } else if !line.isEmpty {
            output.append(LogEvent(
                timestampText: "",
                pid: nil,
                tid: nil,
                level: .unknown,
                tag: "Logcat",
                message: line,
                rawText: line,
                buffer: currentBuffer
            ))
        }
    }

    private mutating func flushPending(into output: inout [LogEvent]) {
        if let pendingEvent {
            output.append(pendingEvent)
            self.pendingEvent = nil
        }
    }

    private func parseThreadtimeLine(_ line: String) -> LogEvent? {
        let parts = line.split(maxSplits: 6, whereSeparator: { $0 == " " || $0 == "\t" })
        let hasYearAndZone = parts.count == 7
            && parts[0].count == 10
            && parts[0].contains("-")
            && parts[2].count == 5
        let timestamp: Date
        let timestampText: String
        let pidIndex: Int
        let tidIndex: Int
        let levelIndex: Int
        let remainderIndex: Int

        if hasYearAndZone {
            guard let parsed = Self.yearAndZoneFormatter.date(
                from: "\(parts[0]) \(parts[1]) \(parts[2])"
            ) else {
                return nil
            }
            timestamp = parsed
            timestampText = Self.tableTimeFormatter.string(from: parsed)
            pidIndex = 3
            tidIndex = 4
            levelIndex = 5
            remainderIndex = 6
        } else {
            guard parts.count >= 6,
                  parts[0].count == 5,
                  parts[1].contains(":"),
                  let parsed = legacyTimestamp(
                    monthDay: String(parts[0]),
                    time: String(parts[1])
                  ) else {
                return nil
            }
            timestamp = parsed
            timestampText = Self.tableTimeFormatter.string(from: parsed)
            pidIndex = 2
            tidIndex = 3
            levelIndex = 4
            remainderIndex = 5
        }

        guard let pid = Int(parts[pidIndex]),
              let tid = Int(parts[tidIndex]) else {
            return nil
        }
        let level = LogLevel(rawValue: String(parts[levelIndex])) ?? .unknown
        let remainder = parts[remainderIndex...].joined(separator: " ")
        let tagAndMessage = remainder.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let tag = tagAndMessage.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let message = tagAndMessage.count == 2
            ? String(tagAndMessage[1]).trimmingCharacters(in: .whitespaces)
            : remainder

        return LogEvent(
            occurredAt: timestamp,
            receivedAtHostTime: Date(),
            timestampText: timestampText,
            pid: pid,
            tid: tid,
            level: level,
            tag: tag,
            message: message,
            rawText: line,
            buffer: currentBuffer
        )
    }

    private func legacyTimestamp(monthDay: String, time: String) -> Date? {
        guard let month = Int(monthDay.prefix(2)),
              let day = Int(monthDay.suffix(2)) else {
            return nil
        }
        let timeParts = time.split(separator: ":")
        guard timeParts.count == 3,
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1]) else {
            return nil
        }
        let secondParts = timeParts[2].split(separator: ".", maxSplits: 1)
        guard let second = Int(secondParts[0]) else { return nil }
        let nanosecond = secondParts.count == 2
            ? (Int(secondParts[1].prefix(9)) ?? 0) * Self.nanosecondMultiplier(for: secondParts[1].count)
            : 0
        var components = calendar.dateComponents([.year], from: referenceDate)
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanosecond
        guard var candidate = calendar.date(from: components) else { return nil }

        // A December line read during the first days of January belongs to the
        // previous year. This also avoids assigning a future year after clock
        // adjustments close to New Year.
        if candidate.timeIntervalSince(referenceDate) > 36 * 60 * 60,
           let previousYear = calendar.date(byAdding: .year, value: -1, to: candidate) {
            candidate = previousYear
        }
        return candidate
    }

    private static func nanosecondMultiplier(for digits: Int) -> Int {
        guard digits < 9 else { return 1 }
        return (0..<(9 - digits)).reduce(1) { value, _ in value * 10 }
    }

    private static let yearAndZoneFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        return formatter
    }()

    private static let tableTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
