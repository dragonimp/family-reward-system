import Foundation

struct ExerciseArchive: Codable {
    var active: ExerciseSession?
    var history: [ExerciseSession] = []
    var uploaded: [UUID]?
    var pendingDeletions: [UUID]?

    func write(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    mutating func deleteHistoryRecord(id: UUID, file: URL) throws {
        guard history.contains(where: { $0.id == id }) else { return }
        var updated = self
        updated.history.removeAll { $0.id == id }
        updated.uploaded?.removeAll { $0 == id }
        if !(updated.pendingDeletions ?? []).contains(id) { updated.pendingDeletions = (updated.pendingDeletions ?? []) + [id] }
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
    var routeEnabled: Bool?
    var route: [ExerciseRoutePoint]?
    var routePoints: [ExerciseRoutePoint] { (route ?? []).filter(\.valid) }
    mutating func appendRoute(_ point: ExerciseRoutePoint) -> Bool {
        guard running, routeEnabled == true, point.valid, let start = intervals.last?.start,
              point.recordedAt >= start, (route?.count ?? 0) < 20_000,
              route?.last.map({ point.recordedAt > $0.recordedAt }) ?? true else { return false }
        if route == nil { route = [] }; route?.append(point)
        return true
    }
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
    static func syncDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = formatter.date(from: text) { return value }
            formatter.formatOptions = [.withInternetDateTime]
            if let value = formatter.date(from: text) { return value }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 workout timestamp")
        }
        return decoder
    }
    static func clock(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}

struct ExerciseRoutePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var recordedAt: Date
    var segment: UUID
    var valid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}
