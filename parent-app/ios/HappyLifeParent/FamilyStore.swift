import Foundation
import SwiftUI
import AgentIdentity
import WatchConnectivity

@MainActor final class FamilyStore: NSObject, ObservableObject {
    let identity = AgentIdentitySession(origin: URL(string: "https://happylife.ai.xmkurt.com")!, callback: URL(string: "linkofamily://login-complete/")!, keychainService: "net.impx.happylife.parent.identity")
    private let base = URL(string: "https://happylife.ai.xmkurt.com")!
    private let session = URLSession(configuration: .ephemeral)
    let photoSource = DearPhotoSource()
    private var photoTransferStatuses: [String: String] = [:]
    @Published var photoRequestNotice: String?
    @Published var photoTransferProgress: Double?
    @Published var profile: Record?
    @Published var groups: [Record] = []
    @Published var children: [Record] = []
    @Published var rules: [Record] = []
    @Published var requests: [Record] = []
    @Published var transactions: [Record] = []
    @Published var growth: [Record] = []
    @Published var members: [Record] = []
    @Published var groupID = 0
    @Published var loading = false
    @Published var error: String?
    @Published var ledgerPage = 1
    @Published var ledgerTotal = 0
    private var revision = UUID()
    private var lastRefresh = Date.distantPast
    override init() {
        super.init()
        photoSource.store = self
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    var scope: String { groupID == 0 ? "" : "familyGroupId=\(groupID)" }
    var ready: Bool { profile?.text("role") == "parent" && profile?.flag("needsRole") == false }
    var selectedFamily: String { groups.first(where: { $0.id == groupID })?.text("name") ?? "我的群组" }

    func call(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Any {
        guard let token = identity.accessToken else { throw APIError.message("请先登录用户中心。") }
        let current = revision
        var request = URLRequest(url: URL(string: path, relativeTo: base)!.absoluteURL)
        request.httpMethod = method; request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard current == revision, token == identity.accessToken else { throw CancellationError() }
        guard let response = response as? HTTPURLResponse, response.url?.host == base.host else { throw APIError.message("网络响应无效。") }
        let value = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        if response.statusCode == 401 { logout(); throw APIError.message("登录已过期，请重新登录。") }
        guard (200..<300).contains(response.statusCode) else {
            let detail = value as? [String: Any]
            throw APIError.message(detail?["error"] as? String ?? detail?["message"] as? String ?? "请求失败（\(response.statusCode)），请重试。")
        }
        return value
    }
    func authenticatedImage(_ path: String) async throws -> UIImage {
        guard let token = identity.accessToken else { throw APIError.message("请先登录用户中心。") }
        let current = revision
        var request = URLRequest(url: URL(string: path, relativeTo: base)!.absoluteURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard current == revision, token == identity.accessToken else { throw CancellationError() }
        guard let response = response as? HTTPURLResponse, response.url?.host == base.host else {
            throw APIError.message("照片预览网络响应无效。")
        }
        guard response.statusCode == 200 else {
            throw APIError.message("照片预览读取失败（\(response.statusCode)），请刷新相册。")
        }
        guard let image = UIImage(data: data) else { throw APIError.message("照片预览格式无效。") }
        return image
    }
    func streamChat(sessionID: String, message: String) async throws {
        guard let token = identity.accessToken else { throw APIError.message("请先登录用户中心。") }
        let current = revision
        var request = URLRequest(url: URL(string: "/api/agentfree/chat/stream", relativeTo: base)!.absoluteURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["sessionId": sessionID, "message": message, "attachments": []])
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.url?.host == base.host else { throw APIError.message("对话响应无效。") }
        guard (200..<300).contains(response.statusCode) else { throw APIError.message("对话请求失败（\(response.statusCode)）。") }
        for try await _ in stream.lines {
            guard current == revision, token == identity.accessToken else { throw CancellationError() }
        }
    }
    func load() async {
        guard identity.isAuthenticated else { return }
        revision = UUID()
        let current = revision
        loading = true; error = nil
        defer { if current == revision { loading = false } }
        do {
            let info = try await call("/api/user/profile?channel=pc")
            guard let fields = info as? [String: Any] else { throw APIError.message("无法读取家长身份。") }
            profile = Record(fields: fields)
            guard ready else { return }
            groups = try Record.list(await call("/api/family-groups"))
            if !groups.contains(where: { $0.id == groupID }) { groupID = groups.first?.id ?? 0 }
            try await loadFamily()
        } catch is CancellationError {} catch { if current == revision { self.error = error.localizedDescription } }
    }
    func loadFamily() async throws {
        // Clear old family data before loading the selected scope.
        children = []; requests = []; transactions = []; growth = []; rules = []; members = []
        children = try await fetchChildren()
        rules = try Record.list(await call("/api/rules"), key: "rules")
        let approval = try await call("/api/reward-requests?limit=50") as? [String: Any]
        requests = try Record.list(approval?["requests"] as Any)
        members = try Record.list(await call("/api/family-members"))
        try await loadLedger(page: 1)
        if groupID != 0 {
            let stats = try await call("/api/stats/growth?\(scope)") as? [String: Any]
            growth = try Record.list(stats?["children"] as Any)
        }
        lastRefresh = Date()
    }
    private func fetchChildren(strictCredit: Bool = false) async throws -> [Record] {
        var result = try Record.list(await call("/api/children?\(scope)"))
        let creditRows: [[String: Any]]
        do {
            let overview = try await call("/api/credit/overview") as? [String: Any]
            guard let rows = overview?["children"] as? [[String: Any]] else { throw APIError.message("信用分数据格式不正确。") }
            creditRows = rows
        } catch {
            if strictCredit { throw error }
            return result.map { Record(fields: $0.fields.merging(["creditUnavailable": true]) { _, new in new }) }
        }
        let creditByProfile = Dictionary(creditRows.compactMap { row -> (String, [String: Any])? in
            guard let key = row["profileKey"] as? String else { return nil }
            return (key, row)
        }, uniquingKeysWith: { first, _ in first })
        result = result.map { child in
            let key = child.text("profileKey")
            guard let credit = creditByProfile[key] else { return child }
            return Record(fields: child.fields.merging(credit) { _, new in new })
        }
        return result
    }
    func refreshBalancesAndLedger() async throws {
        let current = revision
        let updated = try await fetchChildren(strictCredit: true)
        let ledger = try await call("/api/transactions?page=1&pageSize=30") as? [String: Any]
        guard let data = ledger?["data"] as? [String: Any] else { throw APIError.message("无法读取最新积分记录。") }
        let items = try Record.list(data["items"] as Any)
        guard current == revision else { throw CancellationError() }
        children = updated
        transactions = items
        ledgerPage = 1
        ledgerTotal = (data["total"] as? NSNumber)?.intValue ?? 0
        lastRefresh = Date()
    }
    func refreshIfStale() async {
        guard ready, Date().timeIntervalSince(lastRefresh) > 5 else { return }
        do { try await refreshBalancesAndLedger() }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func loadLedger(page: Int) async throws {
        let result = try await call("/api/transactions?page=\(page)&pageSize=30") as? [String: Any]
        guard let data = result?["data"] as? [String: Any] else { throw APIError.message("无法读取积分记录。") }
        let items = try Record.list(data["items"] as Any)
        ledgerPage = page; ledgerTotal = (data["total"] as? NSNumber)?.intValue ?? 0
        transactions = page == 1 ? items : transactions + items
    }
    func chooseGroup(_ id: Int) async {
        groupID = id; revision = UUID(); await load()
    }
    func logout() {
        DearShareInbox.clearCatalog()
        photoSource.logout(token: identity.accessToken)
        photoRequestNotice = nil
        photoTransferProgress = nil
        revision = UUID(); identity.logout(); profile = nil; groups = []; children = []; rules = []; requests = []; transactions = []; growth = []; members = []; groupID = 0; loading = false
    }

    func resumePhotoSharing() { if identity.isAuthenticated { photoSource.start(); Task { await photoSource.importSharedItems() } } }
    func suspendPhotoSharing() { photoSource.stop() }
}

extension FamilyStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { Task { @MainActor in session.activate() } }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            do { replyHandler(try await watchActivityReply(message)) }
            catch { replyHandler(["error": error.localizedDescription]) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let data = try? Data(contentsOf: file.fileURL)
        Task { @MainActor in
            guard let operationID = metadata["operationId"] as? String, UUID(uuidString: operationID) != nil else { return }
            photoTransferStatuses[operationID] = "publishing"
            do {
                guard let data, let spaceID = metadata["spaceId"] as? String,
                      let activityID = metadata["activityId"] as? String else {
                    throw APIError.message("照片传输文件无效。")
                }
                try await photoSource.publish(data, spaceID: spaceID, activityID: activityID,
                                              name: metadata["name"] as? String ?? "手表照片.jpg")
                photoTransferStatuses[operationID] = "published"
            } catch { photoTransferStatuses[operationID] = "error: \(error.localizedDescription)" }
        }
    }

    private func watchActivityReply(_ message: [String: Any]) async throws -> [String: Any] {
        guard identity.isAuthenticated else { throw APIError.message("请先在配对的 iPhone 上登录 Linko Moment。") }
        let base = "/api/dear/social/tenants"
        switch message["action"] as? String {
        case "photoTransferStatus":
            let id = try watchUUID(message, key: "operationId")
            return ["status": photoTransferStatuses[id] ?? "waiting"]
        case "spaces":
            let rows = try watchRows(await call("/api/dear/social/spaces/mine"))
            return ["items": rows.map { ["id": $0["id"] as? String ?? "", "name": $0["name"] as? String ?? "",
                                           "owner": ($0["role"] as? String) == "owner"] as [String: Any] }]
        case "invitations":
            let rows = try watchRows(await call("/api/dear/social/invites/username/pending"))
            return ["items": rows.filter { ($0["joined"] as? Bool) != true }.map {
                ["id": $0["id"] as? String ?? "", "tenantId": $0["tenantId"] as? String ?? "",
                                           "activityId": $0["activityId"] as? String ?? "",
                 "title": $0["activityTitle"] as? String ?? "活动"] }]
        case "createSpace":
            let name = try watchText(message, key: "name", limit: 200)
            _ = try await call(base, method: "POST", body: ["name": name])
            return ["ok": true]
        case "activities", "createActivity", "renameSpace", "deleteSpace", "acceptInvitation",
             "photos", "thumbnail", "moments", "createMoment", "deleteMoment", "checkins", "createCheckIn",
             "members", "renameActivity", "deleteActivity", "inviteUsername", "inviteLink", "deletePhoto":
            guard let spaceID = message["spaceId"] as? String, UUID(uuidString: spaceID) != nil else {
                throw APIError.message("空间标识无效。")
            }
            if message["action"] as? String == "renameSpace" {
                let name = try watchText(message, key: "name", limit: 200)
                _ = try await call(base + "/\(spaceID)", method: "PATCH", body: ["name": name])
                return ["ok": true]
            }
            if message["action"] as? String == "deleteSpace" {
                _ = try await call(base + "/\(spaceID)", method: "DELETE")
                return ["ok": true]
            }
            if message["action"] as? String == "activities" {
                let rows = try watchRows(await call("/api/dear/social/spaces/\(spaceID)/activities"))
                return ["items": rows.map { ["id": $0["id"] as? String ?? "", "title": $0["title"] as? String ?? "",
                                               "sourceTenantId": $0["sourceTenantId"] as? String ?? spaceID,
                                               "canEdit": $0["canEdit"] as? Bool ?? false] as [String: Any] }]
            }
            if message["action"] as? String == "createActivity" {
                let title = try watchText(message, key: "title", limit: 200)
                _ = try await call(base + "/\(spaceID)/activities", method: "POST", body: ["title": title, "description": ""])
                return ["ok": true]
            }
            guard let activityID = message["activityId"] as? String, UUID(uuidString: activityID) != nil else {
                throw APIError.message("活动标识无效。")
            }
            let prefix = base + "/\(spaceID)/activities/\(activityID)"
            switch message["action"] as? String {
            case "renameActivity":
                let title = try watchText(message, key: "title", limit: 200)
                _ = try await call(prefix, method: "PATCH", body: ["title": title]); return ["ok": true]
            case "deleteActivity":
                _ = try await call(prefix, method: "DELETE"); return ["ok": true]
            case "moments":
                let rows = try watchRows(await call(prefix + "/moments"))
                return ["items": rows.map { ["id": $0["id"] as? String ?? "", "text": $0["text"] as? String ?? "",
                                               "author": $0["authorName"] as? String ?? "",
                                               "canDelete": $0["canDelete"] as? Bool ?? false] as [String: Any] }]
            case "createMoment":
                let body = try watchText(message, key: "text", limit: 1000)
                let requestID = try watchUUID(message, key: "requestId")
                _ = try await call(prefix + "/moments", method: "POST", body: ["text": body, "requestId": requestID])
                return ["ok": true]
            case "deleteMoment":
                let id = try watchUUID(message, key: "itemId")
                _ = try await call(prefix + "/moments/\(id)", method: "DELETE"); return ["ok": true]
            case "checkins":
                let rows = try watchRows(await call(prefix + "/checkins"))
                return ["items": rows.map { ["id": $0["id"] as? String ?? "", "note": $0["note"] as? String ?? "",
                                               "address": $0["address"] as? String ?? "",
                                               "author": $0["authorName"] as? String ?? "",
                                               "altitudeMeters": $0["altitudeMeters"] as? Double ?? 0] as [String: Any] }]
            case "createCheckIn":
                let requestID = try watchUUID(message, key: "requestId")
                guard let latitude = message["latitude"] as? Double, (-90...90).contains(latitude),
                      let longitude = message["longitude"] as? Double, (-180...180).contains(longitude),
                      let altitude = message["altitudeMeters"] as? Double, altitude.isFinite else {
                    throw APIError.message("手表位置无效，请重新定位。")
                }
                let address = try watchText(message, key: "address", limit: 500)
                let note = (message["note"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard note.count <= 1000 else { throw APIError.message("备注不能超过 1000 字。") }
                _ = try await call(prefix + "/checkins", method: "POST", body: ["requestId": requestID,
                    "latitude": latitude, "longitude": longitude, "altitudeMeters": altitude,
                    "address": address, "note": note.isEmpty ? address : note])
                return ["ok": true]
            case "members":
                let rows = try watchRows(await call(prefix + "/members"))
                return ["items": rows.map { ["name": $0["displayName"] as? String ?? "",
                                               "isSelf": $0["isSelf"] as? Bool ?? false] as [String: Any] }]
            case "inviteUsername":
                let username = try watchText(message, key: "username", limit: 200)
                _ = try await call(prefix + "/invites/username", method: "POST", body: ["username": username])
                return ["ok": true]
            case "inviteLink":
                let value = try await call(prefix + "/invites/link", method: "POST", body: [:]) as? [String: Any]
                guard let token = value?["token"] as? String,
                      let safe = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                    throw APIError.message("邀请链接无效。")
                }
                return ["url": "https://happylife.ai.xmkurt.com/dear?invite=\(safe)"]
            case "acceptInvitation":
                let me = try await call("/api/dear/social/me") as? [String: Any]
                guard let username = me?["username"] as? String,
                      let safe = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                    throw APIError.message("无法确认当前用户名。")
                }
                _ = try await call(prefix + "/invites/username/\(safe)/accept", method: "POST", body: [:])
                return ["ok": true]
            case "deletePhoto":
                let id = try watchUUID(message, key: "photoId")
                _ = try await call(prefix + "/live/photos/\(id)", method: "DELETE")
                return ["ok": true]
            default: break
            }
            var photos = try watchRows(await call(prefix + "/live/photos"))
            if message["action"] as? String == "photos" {
                await photoSource.refreshPreviews(spaceID: spaceID, activityID: activityID, rows: photos)
                if photos.contains(where: { ($0["thumbnailAvailable"] as? Bool) == false }) {
                    photos = try watchRows(await call(prefix + "/live/photos"))
                }
                let me = try await call("/api/dear/social/me") as? [String: Any]
                let subject = me?["subject"] as? String ?? ""
                let offset = max(0, message["offset"] as? Int ?? 0)
                let page = Array(photos.dropFirst(offset).prefix(30))
                return ["hasMore": offset + page.count < photos.count, "items": page.map { photo in
                    ["id": photo["id"] as? String ?? "",
                     "name": photo["originalFileName"] as? String ?? "照片",
                     "author": photo["sourceDisplayName"] as? String ?? "",
                     "available": photo["thumbnailAvailable"] as? Bool ?? false,
                     "canDelete": !subject.isEmpty && (photo["sourceSubject"] as? String) == subject] as [String: Any]
                }]
            }
            guard let photoID = message["photoId"] as? String, UUID(uuidString: photoID) != nil,
                  photos.contains(where: { ($0["id"] as? String) == photoID && ($0["thumbnailAvailable"] as? Bool) == true }) else {
                throw APIError.message("照片预览不可用，请在 iPhone 上查看。")
            }
            let image = try await authenticatedImage(prefix + "/native-photos/\(photoID)/thumbnail")
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240))
            let scale = min(240 / image.size.width, 240 / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let preview = renderer.image { context in
                UIColor.black.setFill()
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
                image.draw(in: CGRect(x: (240 - size.width) / 2, y: (240 - size.height) / 2,
                                           width: size.width, height: size.height))
            }
            guard let data = preview.jpegData(compressionQuality: 0.55), data.count <= 100_000 else {
                throw APIError.message("照片预览过大，请在 iPhone 上查看。")
            }
            return ["image": data]
        default:
            throw APIError.message("手表活动请求无效。")
        }
    }

    private func watchRows(_ value: Any) throws -> [[String: Any]] {
        guard let rows = value as? [[String: Any]] else { throw APIError.message("活动数据暂时不可用。") }
        return rows
    }

    private func watchText(_ message: [String: Any], key: String, limit: Int) throws -> String {
        let value = (message[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= limit else { throw APIError.message("输入内容须为 1 至 \(limit) 字。") }
        return value
    }

    private func watchUUID(_ message: [String: Any], key: String) throws -> String {
        guard let value = message[key] as? String, UUID(uuidString: value) != nil else {
            throw APIError.message("请求标识无效。")
        }
        return value
    }
}
