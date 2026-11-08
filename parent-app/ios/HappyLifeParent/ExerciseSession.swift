import Foundation

struct ExerciseActivity: Codable, Equatable, Identifiable {
    var tenantID: UUID
    var id: UUID
    var title: String
}

struct ExerciseArchive: Codable {
    var active: ExerciseSession?
    var history: [ExerciseSession] = []
    var activityShares: [UUID: UUID]?
    var importedWatchIDs: [UUID]?
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
    var activity: ExerciseActivity?
    var activityText: String?
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
    var altitudeRange: ClosedRange<Double>? {
        let values = routePoints.compactMap(\.altitudeMeters)
        guard let low = values.min(), let high = values.max() else { return nil }
        return low...high
    }
    var activitySummary: String {
        if let activityText { return activityText }
        let elapsed = intervals.reduce(0.0) { total, interval in total + max(0, floor((interval.end ?? endedAt ?? .now).timeIntervalSince1970) - floor(interval.start.timeIntervalSince1970)) }
        let distance = distanceMeters.map { String(format: "%.2f 公里", locale: Locale(identifier: "en_US_POSIX"), $0 / 1000) } ?? "距离未获取"
        var lines = ["\(kind) · \(Self.clock(elapsed))", distance]
        if let steps { lines.append("\(steps) 步") }
        if let altitude = altitudeRange { lines.append(String(format: "海拔 %.1f–%.1f 米", locale: Locale(identifier: "zh_CN"), altitude.lowerBound, altitude.upperBound)) }
        return lines.joined(separator: "\n")
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
    func continuation(at now: Date) -> ExerciseSession {
        ExerciseSession(kind: kind, startedAt: now, intervals: [ExerciseInterval(start: now)], activity: activity, routeEnabled: routeEnabled)
    }
    static func archiveURL(userID: String) -> URL {
        // The caller supplies the same account hash used by ExerciseStore.
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Exercise/\(userID).json")
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
    var altitudeMeters: Double? = nil
    var verticalAccuracyMeters: Double? = nil
    var valid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) && (altitudeMeters?.isFinite ?? true) && (verticalAccuracyMeters.map { $0.isFinite && $0 >= 0 } ?? true) }
}

struct ExerciseDeliveryEnvelope: Codable {
    var owner: String
    var record: ExerciseSession
    var canonicalOwner: String { UUID(uuidString: owner)?.uuidString ?? owner }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 5 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let value = try ExerciseSession.syncDecoder().decode(Self.self, from: data)
        let record = value.record
        guard !value.owner.isEmpty, value.owner.count <= 200, let end = record.endedAt,
              end >= record.startedAt, !record.intervals.isEmpty, record.intervals.count <= 1000,
              record.intervals.first?.start == record.startedAt,
              (record.route?.count ?? 0) <= 20_000 else { throw CocoaError(.fileReadCorruptFile) }
        var previous = record.startedAt
        for interval in record.intervals {
            guard let stop = interval.end, interval.start >= previous, stop >= interval.start, stop <= end,
                  interval.steps.map({ $0 >= 0 }) ?? true,
                  interval.distanceMeters.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw CocoaError(.fileReadCorruptFile) }
            previous = stop
        }
        var last = Date.distantPast
        for point in record.route ?? [] {
            guard point.valid, point.recordedAt > last, record.intervals.contains(where: { point.recordedAt >= $0.start && point.recordedAt <= $0.end! }) else { throw CocoaError(.fileReadCorruptFile) }
            last = point.recordedAt
        }
        return value
    }
    static func persist(_ data: Data, at file: URL) throws -> Self {
        let value = try decode(data)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            guard try Data(contentsOf: file) == data else { throw CocoaError(.fileWriteFileExists) }
        } else { try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        return value
    }
}
