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
            if !match.category.isEmpty { enriched.category += ";" + match.category }
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

enum DiningMeal: Equatable {
    case breakfast, lunch, afternoonTea, dinner

    static func current(at date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Self {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        switch (parts.hour ?? 0) * 60 + (parts.minute ?? 0) {
        case 300..<630: return .breakfast
        case 630..<840: return .lunch
        case 840..<990: return .afternoonTea
        default: return .dinner
        }
    }

    func includes(_ place: DiningPlace) -> Bool {
        let description = place.name + ";" + place.category
        if Self.contains(description, Self.breakfastTerms) { return self == .breakfast }
        if Self.contains(description, Self.teaTerms) { return self == .afternoonTea }
        if Self.contains(description, Self.bakeryTerms) { return self == .breakfast || self == .afternoonTea }
        return (self == .lunch || self == .dinner) && Self.contains(description, Self.mealTerms)
    }

    private static func contains(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static let breakfastTerms = ["早餐", "早点", "早茶", "早午餐", "豆浆", "油条", "包子", "粥铺", "煎饼", "肠粉", "breakfast", "brunch", "congee"]
    private static let teaTerms = ["下午茶", "甜品", "甜点", "奶茶", "茶饮", "饮品", "冰淇淋", "冰激凌", "糖水", "蛋糕", "咖啡", "果汁",
                                   "dessert", "bubble tea", "boba", "milk tea", "ice cream", "coffee", "café", "cafe"]
    private static let bakeryTerms = ["烘焙", "面包", "糕饼", "bakery", "bakeshop"]
    private static let mealTerms = ["中餐", "西餐", "餐厅", "餐馆", "饭店", "快餐", "食堂", "正餐", "火锅", "烧烤", "烤肉", "面馆", "米线", "拉面", "牛肉面", "饺子", "寿司", "日料",
                                    "restaurant", "diner", "bistro", "noodle", "ramen", "pizza", "burger", "sushi", "grill", "barbecue", "hot pot"]
}

enum DiningTrip: CaseIterable, Hashable {
    case unrestricted, walk5, walk10, drive10, drive20

    var driving: Bool { self == .drive10 || self == .drive20 }
    var limit: TimeInterval? {
        switch self {
        case .unrestricted: nil
        case .walk5: 300
        case .walk10, .drive10: 600
        case .drive20: 1200
        }
    }
    func includes(_ seconds: TimeInterval?) -> Bool {
        guard let limit else { return true }
        guard let seconds, seconds.isFinite else { return false }
        return seconds > 0 && seconds <= limit
    }
}

enum DiningMood: String, Codable, CaseIterable {
    case automatic, familiar, fresh, budget, treat, spicy
}
struct DiningHabit: Codable {
    var selected = 0
    var eaten = 0
    var skipped = 0
    var checkIns: Int?
    var visits: Int { selected + (checkIns ?? 0) }
}
struct DiningChoice: Codable, Identifiable {
    var id = UUID()
    var place: DiningPlace
    var mood: DiningMood
    var selectedAt: Date
    var eatenAt: Date?
    var checkedIn: Bool?
    var restaurantType: String?
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
    var manualRestaurants: [DiningPlace]?

    func manualRestaurant(name: String, latitude: Double, longitude: Double) -> DiningPlace? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        let nearby = (manualRestaurants ?? []).filter { place in
            guard place.name.compare(name, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame else { return false }
            let north = (place.latitude - latitude) * 111_000
            let east = (place.longitude - longitude).remainder(dividingBy: 360) * 111_000 * cos(latitude * .pi / 180)
            return hypot(north, east) <= 75
        }
        let id = nearby.count == 1 ? nearby[0].id : "manual:" + UUID().uuidString
        return DiningPlace(id: id, name: name, address: "", latitude: latitude, longitude: longitude,
                           category: "", provider: "manual", distanceMeters: 0)
    }

    mutating func checkIn(_ place: DiningPlace, mood: DiningMood?, id: UUID, restaurantType: String = "", at date: Date = Date()) {
        guard !history.contains(where: { $0.id == id }) else { return }
        if place.provider == "manual", !(manualRestaurants ?? []).contains(where: { $0.id == place.id }) {
            manualRestaurants = (manualRestaurants ?? []) + [place]
        }
        let type = String(restaurantType.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        history.insert(DiningChoice(id: id, place: place, mood: mood ?? .automatic, selectedAt: date,
                                    checkedIn: true, restaurantType: type.isEmpty ? nil : type), at: 0)
        history = Array(history.prefix(300))
        var habit = habits[place.id, default: DiningHabit()]
        habit.checkIns = (habit.checkIns ?? 0) + 1
        habits[place.id] = habit
    }
    mutating func confirmEaten(_ id: UUID, at date: Date = Date()) {
        guard let index = history.firstIndex(where: { $0.id == id }), history[index].checkedIn != true, history[index].eatenAt == nil else { return }
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
        value *= 1 + min(4, log1p(Double(habit.visits + habit.eaten * 2)))
        if archive.favorites.contains(where: { $0.id == place.id }) { value *= 2 }
        value /= 1 + Double(min(habit.skipped, 5)) * 0.12
        if let rating = place.rating, rating.isFinite, (0...5).contains(rating) { value *= 0.7 + rating / 5 }
        switch mood {
        case .automatic: break
        case .familiar: value *= habit.visits > 0 ? 4 : 1
        case .fresh: value *= habit.visits == 0 ? 5 : 0.8
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
