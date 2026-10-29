import Foundation

struct ExerciseInterval: Codable {
    var start: Date
    var end: Date?
    var steps: Int?
}

struct ExerciseSession: Codable, Identifiable {
    var id = UUID()
    var kind: String
    var startedAt: Date
    var endedAt: Date?
    var intervals: [ExerciseInterval]
    var running: Bool { endedAt == nil && intervals.last?.end == nil }
    var steps: Int? {
        guard intervals.allSatisfy({ $0.steps != nil }) else { return nil }
        return intervals.reduce(0) { $0 + ($1.steps ?? 0) }
    }
    func duration(at now: Date) -> TimeInterval {
        intervals.reduce(0) { $0 + max(0, ($1.end ?? now).timeIntervalSince($1.start)) }
    }
    mutating func pause(at now: Date) {
        guard running, !intervals.isEmpty else { return }
        intervals[intervals.count - 1].end = now
        intervals[intervals.count - 1].steps = nil
    }
    mutating func resume(at now: Date) {
        guard !running, endedAt == nil else { return }
        intervals.append(ExerciseInterval(start: now))
    }
    static func clock(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
