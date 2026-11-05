import Foundation

@main struct DiningModelTests {
    static func main() throws {
        func check(_ value: Bool, _ name: String) { precondition(value, name) }
        let known = DiningPlace(id: "a", name: "Regular", address: "Test", latitude: 31.2, longitude: 121.4, category: "food", provider: "fixture", cost: 25, rating: 4.2, distanceMeters: 200)
        var fresh = known; fresh.id = "b"
        let account = UUID().uuidString
        check(DiningAccount.identity(account.lowercased()) == DiningAccount.identity(account.uppercased()), "GUID account case variants use same private archive")
        check(DiningAccount.identity("User-A") != DiningAccount.identity("user-a"), "non-GUID subjects are not lowercased")
        var archive = DiningArchive(); archive.choose(known, mood: .automatic)
        check(DiningRecommendation.weight(known, mood: .familiar, archive: archive) > DiningRecommendation.weight(fresh, mood: .familiar, archive: archive), "regular place receives positive habit weight")
        check(DiningRecommendation.weight(fresh, mood: .fresh, archive: archive) > DiningRecommendation.weight(known, mood: .fresh, archive: archive), "fresh mode prefers new history")
        check(DiningRecommendation.pick([known, fresh], mood: .automatic, archive: archive, excluding: known.id, draw: 0)?.id == fresh.id, "reroll excludes current only")
        check(DiningRecommendation.pick([known], mood: .automatic, archive: archive, excluding: known.id, draw: 0)?.id == known.id, "regular restaurant never permanently excluded")
        check(DiningRecommendation.pick([], mood: .automatic, archive: archive, excluding: nil) == nil, "no fabricated empty result")
        var broken = known; broken.latitude = .nan
        check(DiningRecommendation.pick([broken], mood: .automatic, archive: archive, excluding: nil) == nil, "invalid coordinate rejected")
        var costly = known; costly.cost = 200
        check(DiningRecommendation.weight(known, mood: .budget, archive: archive) > DiningRecommendation.weight(costly, mood: .budget, archive: archive), "price used only when known")
        var unknown = known; unknown.cost = nil; unknown.rating = nil
        check(DiningRecommendation.weight(unknown, mood: .budget, archive: archive).isFinite, "unknown price and rating remain absent")
        let id = archive.history[0].id
        archive.confirmEaten(UUID(uuidString: id.uuidString.lowercased())!); archive.confirmEaten(UUID(uuidString: id.uuidString.uppercased())!)
        check(archive.habits[known.id]?.eaten == 1, "typed UUID eaten confirmation is idempotent")
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ATLAS_BUILD_WORK"]!).appendingPathComponent("dining-persistence-check")
        let file = root.appendingPathComponent("user-a.json")
        try archive.write(to: file)
        let bytes = try Data(contentsOf: file)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(DiningArchive.self, from: bytes)
        check(restored.history.first?.id == id && restored.habits[known.id]?.eaten == 1, "history and learning survive restart")
        do { try archive.write(to: file.appendingPathComponent("invalid.json")); preconditionFailure("write must fail") } catch { }
        check(try Data(contentsOf: file) == bytes, "failed write preserves previous records")
        for _ in 0..<350 { archive.choose(known, mood: .automatic) }
        check(archive.history.count == 300 && archive.habits[known.id]?.selected == 351, "bounded history retains lifetime habit counts")
        print("PASS: dining recommendation, unknown metadata, reroll, UUID confirmation, persistence and failed-write preservation")
    }
}
