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
            throw APIError.invalidData(key)
        }
        return try list(rows)
    }
    static func list(_ value: Any) throws -> [Record] {
        guard let values = value as? [[String: Any]] else { throw APIError.invalidData(nil) }
        return values.map { Record(fields: $0) }
    }
}
enum APIError: LocalizedError {
    case message(String)
    case invalidData(String?)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .invalidData: return "The service returned invalid data."
        }
    }
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
    init(limit: Int) { self.limit = limit }
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

// A receipt is valid only for the exact private file identity and filesystem
// change stamp. ctime also catches same-size edits with restored mtime.
struct OriginalFileStamp: Codable, Hashable {
    let device: Int64
    let inode: UInt64
    let length: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    static func read(_ url: URL) -> Self? {
        var value = stat()
        guard url.isFileURL,
              url.withUnsafeFileSystemRepresentation({ path in
                  guard let path else { return false }
                  return lstat(path, &value) == 0
              }), value.st_mode & S_IFMT == S_IFREG else { return nil }
        return Self(device: Int64(value.st_dev), inode: UInt64(value.st_ino), length: Int64(value.st_size),
                    modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec),
                    changedSeconds: Int64(value.st_ctimespec.tv_sec), changedNanoseconds: Int64(value.st_ctimespec.tv_nsec))
    }
}

actor OriginalFileVerifier {
    private struct Receipt: Codable {
        let stamp: OriginalFileStamp
        let sha256: String
    }
    private struct Check: Hashable {
        let path: String
        let stamp: OriginalFileStamp
        let sha256: String
    }
    private let ledger: URL
    private var receipts: [String: Receipt]?
    private var checks: [Check: Task<Bool, Never>] = [:]

    init(directory: URL) { ledger = directory.appendingPathComponent("verified-original-files.json") }

    func verify(_ url: URL, length: Int, sha256: String,
                hash: @escaping @Sendable (URL) async throws -> String = { try await OriginalFileVerifier.digest($0) }) async -> Bool {
        guard length > 0, sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }),
              let stamp = OriginalFileStamp.read(url), stamp.length == length else { return false }
        if receipts == nil {
            receipts = (try? JSONDecoder().decode([String: Receipt].self, from: Data(contentsOf: ledger))) ?? [:]
        }
        let path = url.standardizedFileURL.path
        if let saved = receipts?[path], saved.stamp == stamp,
           saved.sha256.caseInsensitiveCompare(sha256) == .orderedSame { return true }
        let check = Check(path: path, stamp: stamp, sha256: sha256.lowercased())
        if let task = checks[check] { return await task.value && OriginalFileStamp.read(url) == stamp }
        let task = Task<Bool, Never> {
            guard let digest = try? await hash(url), !Task.isCancelled else { return false }
            return digest.caseInsensitiveCompare(sha256) == .orderedSame && OriginalFileStamp.read(url) == stamp
        }
        checks[check] = task
        let valid = await task.value && OriginalFileStamp.read(url) == stamp
        checks.removeValue(forKey: check)
        guard valid else { receipts?.removeValue(forKey: path); return false }
        if (receipts?.count ?? 0) >= 4096 { receipts = [:] }
        receipts?[path] = Receipt(stamp: stamp, sha256: sha256.lowercased())
        if let data = try? JSONEncoder().encode(receipts) {
            try? data.write(to: ledger, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return true
    }

    static func digest(_ url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var value = SHA256()
            while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty {
                try Task.checkCancellation()
                value.update(data: bytes)
            }
            return value.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}

struct MomentActivityLink: Identifiable, Equatable {
    let id = UUID()
    let tenantID: UUID
    let activityID: UUID
    let invitation: String?

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["linkofamily", "linkomoment", "linkomomentx"].contains(parts.scheme?.lowercased() ?? ""), parts.host?.lowercased() == "activity",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty || parts.path == "/", parts.fragment == nil else { return nil }
        let items = parts.queryItems ?? []
        guard items.allSatisfy({ ["tenantId", "activityId", "invite"].contains($0.name) }),
              Set(items.map(\.name)).count == items.count,
              let tenant = items.first(where: { $0.name == "tenantId" })?.value.flatMap(UUID.init(uuidString:)),
              let activity = items.first(where: { $0.name == "activityId" })?.value.flatMap(UUID.init(uuidString:)) else { return nil }
        let token = items.first { $0.name == "invite" }?.value
        guard token == nil || (!(token?.isEmpty ?? true) && (token?.count ?? 0) <= 512) else { return nil }
        tenantID = tenant; activityID = activity; invitation = token
    }
}
