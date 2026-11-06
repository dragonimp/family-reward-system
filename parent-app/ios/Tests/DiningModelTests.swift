import Foundation

@main struct DiningModelTests {
    static func main() throws {
        func check(_ value: Bool, _ name: String) { precondition(value, name) }
        let known = DiningPlace(id: "a", name: "Regular", address: "Test", latitude: 31.2, longitude: 121.4, category: "food", provider: "fixture", cost: 25, rating: 4.2, distanceMeters: 200)
        var fresh = known; fresh.id = "b"
        let account = UUID().uuidString
        check(DiningAccount.identity(account.lowercased()) == DiningAccount.identity(account.uppercased()), "GUID account case variants use same private archive")
        check(DiningAccount.identity("User-A") != DiningAccount.identity("user-a"), "non-GUID subjects are not lowercased")
        // Old records were saved without check-in flags, types or counters.
        let legacyJSON = """
        {"history":[{"id":"18F4E989-F3A1-493D-BB56-B2F9A8DFE3B0","place":{"id":"a","name":"Regular","address":"Test","latitude":31.2,"longitude":121.4,"category":"food","provider":"fixture","distanceMeters":200},"mood":"automatic","selectedAt":"2026-11-06T00:00:00Z"}],"habits":{"a":{"selected":1,"eaten":0,"skipped":0}},"favorites":[],"circles":[]}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var archive = try decoder.decode(DiningArchive.self, from: Data(legacyJSON.utf8))
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
        var mapPlace = unknown
        mapPlace.name = "老王牛肉面"
        mapPlace.category = "restaurant"
        check(mapPlace.cuisine == "牛肉面", "explicit specialty from name")
        check(unknown.cuisine == nil, "generic category is not a cuisine")
        var match = mapPlace
        match.provider = "amap"
        match.latitude += 0.004
        match.longitude += 0.005
        match.cost = 25.5
        match.category = "餐饮服务;中餐厅;面馆"
        let center = DiningMapDetails.Center(latitude: 31.204, longitude: 121.405)
        let details = DiningMapDetails(restaurants: [match], searchCenter: center)
        let enriched = details.applying(to: [mapPlace], latitude: 31.2, longitude: 121.4)[0]
        check(enriched.cost == 25.5 && enriched.cuisine == "面馆", "same branch gets price and category")
        check(enriched.id == mapPlace.id && enriched.latitude == mapPlace.latitude && enriched.longitude == mapPlace.longitude, "Apple navigation and history keep their original identity")
        var otherBranch = match
        otherBranch.latitude += 0.01
        let distant = DiningMapDetails(restaurants: [otherBranch], searchCenter: center)
        check(distant.applying(to: [mapPlace], latitude: 31.2, longitude: 121.4) == [mapPlace], "distant branches are not matched")
        let ambiguous = DiningMapDetails(restaurants: [match, match], searchCenter: center)
        check(ambiguous.applying(to: [mapPlace], latitude: 31.2, longitude: 121.4) == [mapPlace], "ambiguous matches do not contribute prices")
        let id = archive.history[0].id
        archive.confirmEaten(UUID(uuidString: id.uuidString.lowercased())!); archive.confirmEaten(UUID(uuidString: id.uuidString.uppercased())!)
        check(archive.habits[known.id]?.eaten == 1, "typed UUID eaten confirmation is idempotent")
        let manualID = UUID()
        let firstVisit = Date(timeIntervalSince1970: 1_790_000_000)
        archive.checkIn(fresh, mood: nil, id: manualID, restaurantType: "  川菜  ", at: firstVisit)
        archive.checkIn(fresh, mood: nil, id: UUID(uuidString: manualID.uuidString.lowercased())!)
        check(archive.habits[fresh.id]?.checkIns == 1 && archive.history[0].restaurantType == "川菜", "manual check-in retry with a case variant does not count twice")
        let autoID = UUID()
        archive.checkIn(fresh, mood: .familiar, id: autoID, at: firstVisit.addingTimeInterval(86_400))
        archive.checkIn(fresh, mood: .familiar, id: autoID)
        archive.confirmEaten(autoID)
        check(archive.habits[fresh.id]?.checkIns == 2 && archive.habits[fresh.id]?.visits == 2, "automatic and manual check-ins share one counter and a later visit counts")
        check(archive.history.filter { $0.checkedIn == true }.count == 2 && archive.habits[fresh.id]?.eaten == 0, "new visits do not require a second confirmation")
        var unvisited = fresh; unvisited.id = "c"
        for mood in [DiningMood.automatic, .familiar] {
            check(DiningRecommendation.weight(fresh, mood: mood, archive: archive) > DiningRecommendation.weight(unvisited, mood: mood, archive: archive), "check-ins benefit automatic and familiar choices")
        }
        var china = Calendar(identifier: .gregorian)
        china.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var pacific = china
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = DateComponents(year: 2026, month: 11, day: 6)
        func mealAt(_ hour: Int, _ minute: Int) -> DiningMeal {
            var local = day; local.hour = hour; local.minute = minute
            return DiningMeal.current(at: china.date(from: local)!, calendar: china)
        }
        check(mealAt(4, 59) == .dinner && mealAt(5, 0) == .breakfast, "breakfast starts at 05:00")
        check(mealAt(10, 29) == .breakfast && mealAt(10, 30) == .lunch, "lunch starts at 10:30")
        check(mealAt(13, 59) == .lunch && mealAt(14, 0) == .afternoonTea, "tea starts at 14:00")
        check(mealAt(16, 29) == .afternoonTea && mealAt(16, 30) == .dinner, "dinner starts at 16:30")
        let instant = china.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 8))!
        check(DiningMeal.current(at: instant, calendar: china) == .breakfast && DiningMeal.current(at: instant, calendar: pacific) == .dinner, "same instant uses the user's timezone")
        var breakfast = known; breakfast.name = "阿婆早餐"; breakfast.category = "中餐厅"
        var tea = fresh; tea.name = "珍珠奶茶"; tea.category = "餐饮服务;快餐厅"
        var dinner = unvisited; dinner.name = "Steak House"; dinner.category = "restaurant"
        let options = [breakfast, tea, dinner]
        check(options.filter(DiningMeal.breakfast.includes) == [breakfast], "breakfast filters out tea and regular restaurants")
        check(options.filter(DiningMeal.afternoonTea.includes) == [tea], "tea filters out main meals")
        check(options.filter(DiningMeal.lunch.includes) == [dinner] && options.filter(DiningMeal.dinner.includes) == [dinner], "meal time requires main meals")
        check(DiningRecommendation.pick([tea].filter(DiningMeal.lunch.includes), mood: .familiar, archive: archive, excluding: nil) == nil, "familiarity cannot bypass the meal filter or supply a wrong fallback")
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ATLAS_BUILD_WORK"]!).appendingPathComponent("dining-persistence-check")
        let file = root.appendingPathComponent("user-a.json")
        try archive.write(to: file)
        let bytes = try Data(contentsOf: file)
        let restored = try decoder.decode(DiningArchive.self, from: bytes)
        check(restored.history.first?.id == autoID && restored.habits[fresh.id]?.checkIns == 2 && restored.habits[known.id]?.eaten == 1, "check-ins and legacy history survive restart")
        check(restored.history.first?.selectedAt == firstVisit.addingTimeInterval(86_400), "check-in time survives a UTC timestamp round trip")
        do { try archive.write(to: file.appendingPathComponent("invalid.json")); preconditionFailure("write must fail") } catch { }
        check(try Data(contentsOf: file) == bytes, "failed write preserves previous records")
        for _ in 0..<350 { archive.checkIn(known, mood: .automatic, id: UUID()) }
        check(archive.history.count == 300 && archive.habits[known.id]?.checkIns == 350, "bounded history retains lifetime habit counts")
        print("PASS: check-in retries, legacy history, local archive, recommendations and failed-write preservation")
    }
}
