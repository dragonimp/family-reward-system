import Foundation

enum DearShareInbox {
    static let groupID = "group.net.impx.happylife.parent"

    struct Activity: Codable, Identifiable {
        let id: String
        let tenantID: String
        let title: String
        let date: Date
    }

    struct Catalog: Codable {
        let account: String
        let activities: [Activity]
    }

    struct Item: Codable {
        let fileName: String
        let displayName: String
        let mediaType: String
    }

    struct Batch: Codable {
        let account: String
        let activityID: String
        let tenantID: String
        var items: [Item]
    }

    static func root() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw NSError(domain: "DearShareInbox", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "共享空间不可用，请重新安装 Linko Moment。"])
        }
        return url
    }

    static func catalog() -> Catalog? {
        guard let root = try? root(),
              let data = try? Data(contentsOf: root.appendingPathComponent("activities.json")) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }

    static func saveCatalog(_ catalog: Catalog) throws {
        let root = try root()
        try JSONEncoder().encode(catalog).write(to: root.appendingPathComponent("activities.json"), options: .atomic)
    }

    static func clearCatalog() {
        guard let root = try? root() else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent("activities.json"))
    }

    static func pendingRoot() throws -> URL {
        let url = try root().appendingPathComponent("pending", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ batch: Batch, at directory: URL) throws {
        try JSONEncoder().encode(batch).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }
}
