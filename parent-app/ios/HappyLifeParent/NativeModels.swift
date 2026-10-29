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
