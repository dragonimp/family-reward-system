import Foundation
import CryptoKit

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
    private static let fractional: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
    private static let whole = ISO8601DateFormatter()
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
        return fractional.date(from: raw) ?? whole.date(from: raw)
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
    static func pageOffset(horizontal: Double, vertical: Double, predictedHorizontal: Double) -> Int {
        guard horizontal.isFinite, vertical.isFinite, predictedHorizontal.isFinite,
              abs(horizontal) > 24, abs(horizontal) > abs(vertical) * 1.25,
              abs(horizontal) >= 70 || abs(predictedHorizontal) >= 160 else { return 0 }
        return horizontal < 0 ? 1 : -1
    }
    static func shouldDismiss(horizontal: Double, vertical: Double, predictedVertical: Double) -> Bool {
        guard horizontal.isFinite, vertical.isFinite, predictedVertical.isFinite,
              vertical > 24, vertical > abs(horizontal) * 1.25 else { return false }
        return vertical >= 110 || predictedVertical >= 240
    }
}

struct PhotoGeography: Sendable {
    var name: String
    var latitude: Double?
    var longitude: Double?
    var altitudeMeters: Double?
    static func altitude(_ value: Double?, belowSeaLevel: Bool) -> Double? {
        guard let value, value.isFinite else { return nil }
        let signed = belowSeaLevel ? -abs(value) : value
        return (-12000...100000).contains(signed) ? signed : nil
    }
    static func iso6709(_ text: String) -> (Double, Double, Double?)? {
        guard let regex = try? NSRegularExpression(pattern: #"^([+-]\d{2}(?:\.\d+)?)([+-]\d{3}(?:\.\d+)?)([+-]\d+(?:\.\d+)?)?/$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func value(_ index: Int) -> Double? { Range(match.range(at: index), in: text).flatMap { Double(text[$0]) } }
        guard let lat = value(1), let lon = value(2), abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return (lat,lon,altitude(value(3),belowSeaLevel:false))
    }
}

// Map labels identify the person and place; filenames are confined to photo details.
enum ActivityMapLabel {
    static func title(nickname: String, placeName: String) -> String {
        let person = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(person.isEmpty ? "活动成员" : person) · \(place.isEmpty ? "地点未命名" : place)"
    }
}

// Streaming original verification: names and thumbnails never establish identity.
struct OriginalResourceDigest: Codable, Equatable {
    let length: Int
    let sha256: String
    func matches(length expectedLength: Int, sha256 expectedSHA: String) -> Bool {
        length == expectedLength && sha256.caseInsensitiveCompare(expectedSHA) == .orderedSame
    }
}
struct OriginalResourceFingerprint {
    private var hash = SHA256()
    private var length = 0
    private var exceeded = false
    let limit: Int
    mutating func append(_ bytes: Data) -> Bool {
        guard !exceeded, bytes.count <= limit - length else { exceeded = true; return false }
        hash.update(data: bytes); length += bytes.count
        return true
    }
    func finish() -> OriginalResourceDigest? {
        guard !exceeded else { return nil }
        return OriginalResourceDigest(length: length, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
