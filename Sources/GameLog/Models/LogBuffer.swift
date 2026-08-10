import Foundation

struct LogBuffer: Sendable {
    private var storage: [LogEvent] = []
    private var startIndex = 0
    private(set) var capacity: Int

    var events: [LogEvent] {
        guard startIndex > 0 else { return storage }
        return Array(storage[startIndex...])
    }

    init(capacity: Int = 50_000) {
        self.capacity = max(1, capacity)
    }

    @discardableResult
    mutating func append(contentsOf newEvents: [LogEvent]) -> Int {
        guard !newEvents.isEmpty else { return 0 }

        let retainedCount = storage.count - startIndex
        if newEvents.count >= capacity {
            let evicted = retainedCount + newEvents.count - capacity
            storage = Array(newEvents.suffix(capacity))
            startIndex = 0
            return evicted
        }

        storage.append(contentsOf: newEvents)
        let overflow = max(0, retainedCount + newEvents.count - capacity)
        startIndex += overflow
        compactStorageIfNeeded()
        return overflow
    }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        startIndex = 0
    }

    mutating func updateCapacity(_ newValue: Int) {
        capacity = max(1, newValue)
        let overflow = max(0, storage.count - startIndex - capacity)
        if overflow > 0 {
            startIndex += overflow
        }
        compactStorageIfNeeded(force: true)
    }

    private mutating func compactStorageIfNeeded(force: Bool = false) {
        guard startIndex > 0,
              force || startIndex >= capacity || startIndex >= storage.count / 2 else {
            return
        }
        storage.removeFirst(startIndex)
        startIndex = 0
    }
}
