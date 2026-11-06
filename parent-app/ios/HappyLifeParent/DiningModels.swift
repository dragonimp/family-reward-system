import Foundation

struct DiningPlace: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: String
    var provider: String
    var cost: Double?
    var rating: Double?
    var distanceMeters: Double
}
// Match details across providers without passing GCJ-02 coordinates to Apple Maps.
struct DiningMapDetails: Decodable {
    struct Center: Decodable {
        let latitude: Double
        let longitude: Double
    }
    let restaurants: [DiningPlace]
    let searchCenter: Center

    func applying(to places: [DiningPlace], latitude: Double, longitude: Double) -> [DiningPlace] {
        let northOffset = searchCenter.latitude - latitude
        let eastOffset = searchCenter.longitude - longitude
        let metersPerLongitude = 111_000 * cos(latitude * .pi / 180)
        return places.map { place in
            let nearby = restaurants.filter { candidate in
                guard candidate.provider == "amap",
                      candidate.name.compare(place.name, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame else { return false }
                let north = (candidate.latitude - place.latitude - northOffset) * 111_000
                let east = (candidate.longitude - place.longitude - eastOffset) * metersPerLongitude
                return hypot(north, east) <= 60
            }
            guard nearby.count == 1, let match = nearby.first else { return place }
            var enriched = place
            enriched.category = match.category
            enriched.cost = match.cost
            enriched.rating = match.rating
            return enriched
        }
    }
}

extension DiningPlace {
    var cuisine: String? {
        let generic = ["restaurant", "food", "餐饮服务", "餐饮相关场所", "餐饮相关", "中餐厅", "外国餐厅", "餐厅", "中餐", "西餐"]
        if let type = category.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .last(where: { !$0.isEmpty && !generic.contains($0) }) { return type }
        let dishes = ["牛肉面", "螺蛳粉", "麻辣烫", "小龙虾", "烤肉", "烧烤", "烤鱼", "火锅", "饺子", "馄饨", "小笼包",
                      "砂锅", "卤肉饭", "煲仔饭", "米线", "拉面", "寿司", "披萨", "汉堡", "炸鸡", "粤菜", "川菜", "湘菜", "日料",
                      "pizza", "ramen", "sushi", "burgers", "barbecue", "hot pot"]
        return dishes.first(where: { name.localizedCaseInsensitiveContains($0) })
    }
}

enum DiningMood: String, Codable, CaseIterable {
    case automatic, familiar, fresh, budget, treat, spicy
}
struct DiningHabit: Codable {
    var selected = 0
    var eaten = 0
    var skipped = 0
}
struct DiningChoice: Codable, Identifiable {
    var id = UUID()
    var place: DiningPlace
    var mood: DiningMood
    var selectedAt: Date
    var eatenAt: Date?
}
struct DiningCircle: Codable, Identifiable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
}
struct DiningArchive: Codable {
    var history: [DiningChoice] = []
    var habits: [String: DiningHabit] = [:]
    var favorites: [DiningPlace] = []
    var circles: [DiningCircle] = []

    mutating func choose(_ place: DiningPlace, mood: DiningMood, at date: Date = Date()) {
        history.insert(DiningChoice(place: place, mood: mood, selectedAt: date), at: 0)
        history = Array(history.prefix(300))
        habits[place.id, default: DiningHabit()].selected += 1
    }
    mutating func confirmEaten(_ id: UUID, at date: Date = Date()) {
        guard let index = history.firstIndex(where: { $0.id == id }), history[index].eatenAt == nil else { return }
        history[index].eatenAt = date
        habits[history[index].place.id, default: DiningHabit()].eaten += 1
    }
    mutating func toggleFavorite(_ place: DiningPlace) {
        if favorites.contains(where: { $0.id == place.id }) { favorites.removeAll { $0.id == place.id } }
        else { favorites.append(place) }
    }
    func write(to file: URL) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(self)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
enum DiningRecommendation {
    static func weight(_ place: DiningPlace, mood: DiningMood, archive: DiningArchive) -> Double {
        let habit = archive.habits[place.id] ?? DiningHabit()
        var value = 1.0 / (1.0 + max(0, place.distanceMeters) / 1500)
        value *= 1 + min(4, log1p(Double(habit.selected + habit.eaten * 2)))
        if archive.favorites.contains(where: { $0.id == place.id }) { value *= 2 }
        value /= 1 + Double(min(habit.skipped, 5)) * 0.12
        if let rating = place.rating, rating.isFinite, (0...5).contains(rating) { value *= 0.7 + rating / 5 }
        switch mood {
        case .automatic: break
        case .familiar: value *= habit.selected > 0 ? 4 : 1
        case .fresh: value *= habit.selected == 0 ? 5 : 0.8
        case .budget: if let cost = place.cost, cost > 0 { value *= min(4, max(0.25, 40 / cost)) } else { value /= 1 + max(0, place.distanceMeters) / 500 }
        case .treat: if let cost = place.cost, cost > 0 { value *= min(3, max(0.5, cost / 40)) } else if archive.favorites.contains(where: { $0.id == place.id }) || habit.eaten > 0 { value *= 2 }
        case .spicy:
            if ["川", "湘", "辣", "火锅", "chili", "sichuan", "hunan"].contains(where: { (place.name + place.category).localizedCaseInsensitiveContains($0) }) { value *= 4 }
        }
        return max(0.01, value)
    }
    static func pick(_ places: [DiningPlace], mood: DiningMood, archive: DiningArchive, excluding: String?, draw: Double = Double.random(in: 0..<1)) -> DiningPlace? {
        var seen = Set<String>()
        let unique = places.filter { !$0.name.isEmpty && $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 && seen.insert($0.id).inserted }
        let alternatives = unique.filter { $0.id != excluding }
        let candidates = alternatives.isEmpty ? unique : alternatives
        let weights = candidates.map { weight($0, mood: mood, archive: archive) }
        var target = min(0.999999, max(0, draw)) * weights.reduce(0, +)
        for (place, weight) in zip(candidates, weights) { target -= weight; if target < 0 { return place } }
        return candidates.last
    }
}

enum DiningAccount {
    static func identity(_ raw: String) -> String {
        if raw.count == 36, let id = UUID(uuidString: raw) { return id.uuidString.lowercased() }
        return raw
    }
}
