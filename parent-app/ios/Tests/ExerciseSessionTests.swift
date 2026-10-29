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
        print("PASS: pause/resume, interval steps, completed immutability, restart persistence, local time across midnight")
    }
}
