import Foundation

struct ExerciseArchive: Codable {
    var active: ExerciseSession?
    var history: [ExerciseSession] = []

    func write(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    mutating func deleteHistoryRecord(id: UUID, file: URL) throws {
        guard history.contains(where: { $0.id == id }) else { return }
        var updated = self
        updated.history.removeAll { $0.id == id }
        try updated.write(to: file)
        self = updated
    }
}

struct ExerciseInterval: Codable {
    var start: Date
    var end: Date?
    var steps: Int?
    var distanceMeters: Double?
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
    var distanceMeters: Double? {
        guard !intervals.isEmpty, intervals.allSatisfy({ $0.distanceMeters != nil }) else { return nil }
        return intervals.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
    }
    var distanceText: String {
        distanceMeters.map { String(format: "%.2f 公里", $0 / 1000) } ?? "距离未获取"
    }
    func duration(at now: Date) -> TimeInterval {
        intervals.reduce(0) { $0 + max(0, ($1.end ?? now).timeIntervalSince($1.start)) }
    }
    mutating func pause(at now: Date) {
        guard running, !intervals.isEmpty else { return }
        intervals[intervals.count - 1].end = now
        intervals[intervals.count - 1].steps = nil
        intervals[intervals.count - 1].distanceMeters = nil
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
