import Foundation

@main struct ExerciseSessionTests {
    static func main() throws {
        let start = ISO8601DateFormatter().date(from: "2026-10-29T23:59:50Z")!
        var session = ExerciseSession(kind: "散步", startedAt: start, intervals: [ExerciseInterval(start: start)])
        precondition(session.running && session.steps == nil)
        session.intervals[0].steps = 5
        precondition(session.steps == 5)
        session.pause(at: start.addingTimeInterval(15))
        precondition(!session.running && session.duration(at: start.addingTimeInterval(90)) == 15)
        precondition(session.steps == nil) // Closed intervals must be reconciled, not retain a stale live count.
        session.intervals[0].steps = 7
        session.resume(at: start.addingTimeInterval(45))
        precondition(session.duration(at: start.addingTimeInterval(55)) == 25)
        precondition(session.steps == nil)
        session.intervals[1].steps = 8
        precondition(session.steps == 15)
        session.resume(at: start.addingTimeInterval(46))
        precondition(session.intervals.count == 2)
        session.pause(at: start.addingTimeInterval(65))
        session.intervals[1].steps = 11
        session.pause(at: start.addingTimeInterval(100))
        precondition(session.duration(at: start.addingTimeInterval(100)) == 35)
        precondition(session.steps == 18)
        session.endedAt = start.addingTimeInterval(65)
        session.resume(at: start.addingTimeInterval(150))
        precondition(session.intervals.count == 2 && !session.running)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(ExerciseSession.self, from: data)
        precondition(restored.id == session.id && restored.steps == 18)
        precondition(restored.duration(at: start.addingTimeInterval(999)) == 35)
        let local = DateFormatter(); local.dateFormat = "yyyy-MM-dd HH:mm:ss"
        local.timeZone = TimeZone(identifier: "America/Los_Angeles")
        precondition(local.string(from: restored.startedAt) == "2026-10-29 16:59:50")
        local.timeZone = TimeZone(identifier: "Asia/Tokyo")
        precondition(local.string(from: restored.startedAt) == "2026-10-30 08:59:50")
        precondition(ExerciseSession.clock(3661) == "01:01:01")
        precondition(ExerciseSession.clock(-1) == "00:00:00")
        var distanceSession = ExerciseSession(kind: "慢跑", startedAt: start,
            intervals: [ExerciseInterval(start: start, steps: 100, distanceMeters: 1234)])
        precondition(distanceSession.distanceMeters == 1234 && distanceSession.distanceText == "1.23 公里")
        distanceSession.pause(at: start.addingTimeInterval(10))
        precondition(distanceSession.distanceMeters == nil)
        distanceSession.intervals[0].distanceMeters = 1500
        distanceSession.resume(at: start.addingTimeInterval(30))
        precondition(distanceSession.distanceMeters == nil)
        distanceSession.intervals[1].distanceMeters = 250
        precondition(distanceSession.distanceMeters == 1750)
        distanceSession.pause(at: start.addingTimeInterval(40))
        distanceSession.intervals[1].distanceMeters = 300
        distanceSession.endedAt = start.addingTimeInterval(40)
        precondition(distanceSession.distanceMeters == 1800 && distanceSession.duration(at: start.addingTimeInterval(99)) == 20)
        let savedDistance = try decoder.decode(ExerciseSession.self, from: encoder.encode(distanceSession))
        precondition(savedDistance.distanceMeters == 1800)
        let legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var legacyJSON = legacy
        legacyJSON["intervals"] = (legacy["intervals"] as! [[String: Any]]).map { item in
            var item = item; item.removeValue(forKey: "distanceMeters"); return item
        }
        let oldRecord = try decoder.decode(ExerciseSession.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        precondition(oldRecord.steps == 18 && oldRecord.distanceMeters == nil && oldRecord.distanceText == "距离未获取")
        precondition(ExerciseSession(kind: "散步", startedAt: start, intervals: [ExerciseInterval(start: start, distanceMeters: 0)]).distanceText == "0.00 公里")
        print("PASS: distance totals, pause exclusion, persistence, legacy archive compatibility")
        print("PASS: pause/resume, interval steps, completed immutability, restart persistence, local time across midnight")
    }
}
