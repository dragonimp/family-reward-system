import Foundation

struct Record: Identifiable {
    let fields: [String: Any]
    var id: Int { int("id") }
    func text(_ key: String) -> String { fields[key] as? String ?? "" }
    func number(_ key: String) -> Double { (fields[key] as? NSNumber)?.doubleValue ?? 0 }
    func int(_ key: String) -> Int { (fields[key] as? NSNumber)?.intValue ?? 0 }
    func flag(_ key: String) -> Bool { fields[key] as? Bool ?? false }
    func has(_ key: String) -> Bool { fields[key] != nil && !(fields[key] is NSNull) }
    func amount(_ key: String) -> String { number(key).formatted(.number.precision(.fractionLength(0...2))) }
    static func list(_ value: Any, key: String) throws -> [Record] {
        guard let object = value as? [String: Any], let rows = object[key] else {
            throw APIError.message("服务返回的\(key)数据格式不正确。")
        }
        return try list(rows)
    }
    static func list(_ value: Any) throws -> [Record] {
        guard let values = value as? [[String: Any]] else { throw APIError.message("服务返回的数据格式不正确。") }
        return values.map { Record(fields: $0) }
    }
}
enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct FormField: Identifiable {
    let key: String
    let title: String
    var initial = ""
    var numeric = false
    var required = true
    var id: String { key }
}
struct EditorSpec: Identifiable {
    let id = UUID()
    let title: String
    let path: String
    var method = "POST"
    var fields: [FormField]
    var fixed: [String: Any] = [:]
    var scansWatchCode = false
    var showsReceipt = false
}

enum WatchPairingCode {
    static func parse(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URLComponents(string: value), url.scheme != nil {
            guard url.scheme == "https", ["happylife.ai.xmkurt.com", "happylife.ai.impx.net"].contains(url.host ?? ""),
                  url.path == "/children", url.user == nil, url.password == nil,
                  url.port == nil || url.port == 443,
                  let codes = url.queryItems?.filter({ $0.name == "watchCode" }),
                  codes.count == 1, let code = codes.first?.value else { return nil }
            value = code
        }
        value = value.components(separatedBy: .whitespacesAndNewlines).joined().replacingOccurrences(of: "-", with: "").uppercased()
        return value.range(of: "^[A-HJ-NP-Z2-9]{8}$", options: .regularExpression) != nil ? value : nil
    }
}

// Activity timestamps use the device time zone; calendar-only dates retain their day.
enum ActivityListDate {
    static func parse(_ raw: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        if raw.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            return formatter.date(from: raw)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    static func value(startsAt: String, createdAt: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        parse(startsAt, timeZone: timeZone) ?? parse(createdAt, timeZone: timeZone)
    }

    static func label(startsAt: String, createdAt: String, timeZone: TimeZone = .autoupdatingCurrent,
                      locale: Locale = .autoupdatingCurrent) -> String {
        guard let date = value(startsAt: startsAt, createdAt: createdAt, timeZone: timeZone) else { return "日期未设置" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return (parse(startsAt, timeZone: timeZone) == nil ? "创建于 " : "活动日期 ") + formatter.string(from: date)
    }
}

// Keep dismissal directional so a page swipe, short drag or upward pan cannot close the viewer.
enum PhotoViewerSwipe {
    static func shouldDismiss(horizontal: Double, vertical: Double, predictedVertical: Double) -> Bool {
        guard horizontal.isFinite, vertical.isFinite, predictedVertical.isFinite,
              vertical > 24, vertical > abs(horizontal) * 1.25 else { return false }
        return vertical >= 110 || predictedVertical >= 240
    }
}
