import SwiftUI
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

struct WatchSocialSpace: Identifiable { let id: String; let name: String; let owner: Bool }
struct WatchSocialActivity: Identifiable { let id: String; let title: String; let canEdit: Bool }
struct WatchSocialPhoto: Identifiable {
    let id: String; let name: String; let author: String; let available: Bool; let canDelete: Bool
}

#if canImport(WatchConnectivity)
private final class WatchActivityTransport: NSObject, WCSessionDelegate {
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private var photoTransfers: [String: (CheckedContinuation<Void, Error>, WCSessionFileTransfer)] = [:]

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func request(_ message: [String: Any]) async throws -> [String: Any] {
        guard let session, session.activationState == .activated, session.isReachable else {
            throw APIError(status: 0, message: "请让配对的 iPhone 保持连接，并在 iPhone 上登录 Linko Dear 后重试。")
        }
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                if let error = reply["error"] as? String {
                    continuation.resume(throwing: APIError(status: 0, message: error))
                } else { continuation.resume(returning: reply) }
            }, errorHandler: { error in
                continuation.resume(throwing: APIError(status: 0, message: "无法连接配对的 iPhone：\(error.localizedDescription)"))
            })
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { }

    func sendPhoto(_ data: Data, metadata: [String: Any]) async throws {
        guard let session, session.activationState == .activated,
              let operationID = metadata["operationId"] as? String else {
            throw APIError(status: 0, message: "手表与 iPhone 的照片传输尚未就绪。")
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(operationID + ".jpg")
        try data.write(to: path, options: .atomic)
        try await withCheckedThrowingContinuation { continuation in
            let transfer = session.transferFile(path, metadata: metadata)
            photoTransfers[operationID] = (continuation, transfer)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(120))
                guard let pending = photoTransfers.removeValue(forKey: operationID) else { return }
                pending.1.cancel()
                pending.0.resume(throwing: APIError(status: 0, message: "照片传输超时，请让配对的 iPhone 保持连接后重试。"))
            }
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            guard let operationID = fileTransfer.file.metadata?["operationId"] as? String else { return }
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
            guard let pending = photoTransfers.removeValue(forKey: operationID) else { return }
            if let error { pending.0.resume(throwing: error) }
            else { pending.0.resume() }
        }
    }
}
#else
private final class WatchActivityTransport {
    func activate() { }
    func request(_ message: [String: Any]) async throws -> [String: Any] {
        throw APIError(status: 0, message: "手表活动照片需要 Apple Watch。")
    }
    func sendPhoto(_ data: Data, metadata: [String: Any]) async throws {
        throw APIError(status: 0, message: "手表活动照片需要 Apple Watch。")
    }
}
#endif

@MainActor
final class WatchStore: ObservableObject {
    private struct PendingTransfer: Codable {
        let previousToken: String
        let challenge: PairingChallenge
    }
    @Published private(set) var pairing: PairingChallenge?
    @Published private(set) var pairingMessage = "请家长扫码，或在家庭管理中输入设备码"
    @Published private(set) var pairingExpired = false
    @Published private(set) var token: String?
    @Published private(set) var score: ScoreResponse?
    @Published private(set) var rules: [RewardRule] = []
    @Published private(set) var requests: [RewardRequest] = []
    @Published private(set) var settings: WatchSettings?
    @Published private(set) var face = "world"
    @Published private(set) var friends: FriendsResponse?
    @Published private(set) var friendCode: FriendCode?
    @Published private(set) var parents: [ParentOption] = []
    @Published private(set) var growth: GrowthReport?
    @Published private(set) var connections: ConnectionResponse?
    @Published private(set) var socialSpaces: [WatchSocialSpace] = []
    @Published private(set) var socialActivities: [WatchSocialActivity] = []
    @Published private(set) var socialPhotos: [WatchSocialPhoto] = []
    @Published private(set) var socialPhotosHasMore = false
    @Published private(set) var socialLoading = false
    @Published private(set) var socialError: String?
    @Published private(set) var busy = false
    @Published private(set) var ready = false
    @Published var message: String?
    private let api: WatchAPI
    private let activityTransport = WatchActivityTransport()
    private let readCredential: () throws -> String?
    private let saveCredential: (String) throws -> Void
    private let clearCredential: () throws -> Void

    init(api: WatchAPI? = nil,
         readCredential: @escaping () throws -> String? = DeviceCredential.read,
         saveCredential: @escaping (String) throws -> Void = DeviceCredential.save,
         clearCredential: @escaping () throws -> Void = DeviceCredential.clear) {
        let address = Bundle.main.object(forInfoDictionaryKey: "HappyLifeAPIBaseURL") as? String ?? ""
        self.api = api ?? WatchAPI(baseURL: URL(string: address) ?? URL(fileURLWithPath: "/"))
        self.readCredential = readCredential
        self.saveCredential = saveCredential
        self.clearCredential = clearCredential
        activityTransport.activate()
    }

    func start() async {
        guard !ready else { return }
        await perform {
            let credential = try self.readCredential()
            if let credential, credential.hasPrefix("transfer:") {
                let pending = try JSONDecoder().decode(PendingTransfer.self, from: Data(credential.dropFirst(9).utf8))
                self.token = pending.previousToken
                self.pairing = pending.challenge
            } else if let credential, credential.hasPrefix("pairing:") {
                self.pairing = try JSONDecoder().decode(PairingChallenge.self, from: Data(credential.dropFirst(8).utf8))
            } else { self.token = credential }
            self.ready = true
            if self.token != nil && self.pairing == nil { try await self.load() }
        }
    }

    func beginPairing() async {
        guard pairing == nil || pairingExpired else { return }
        await perform {
            let challenge: PairingChallenge = try await self.api.call("pairing", token: self.token, body: [
                "deviceName": "Apple Watch", "platform": "watchos"])
            // Persist the private token before showing its public code. A restart can recover approval.
            if let previousToken = self.token {
                let pending = PendingTransfer(previousToken: previousToken, challenge: challenge)
                try self.saveCredential("transfer:" + String(decoding: try JSONEncoder().encode(pending), as: UTF8.self))
            } else {
                try self.saveCredential("pairing:" + String(decoding: try JSONEncoder().encode(challenge), as: UTF8.self))
            }
            self.pairing = challenge
            self.pairingExpired = false
            self.pairingMessage = "请家长扫码，或在家庭管理中输入设备码"
        }
    }

    func pollPairing() async {
        guard let challenge = pairing, !busy, !pairingExpired else { return }
        do {
            let result: PairingStatus = try await api.call("pairing", token: challenge.deviceToken)
            guard !Task.isCancelled else { return }
            if result.status == "approved" {
                try saveCredential(challenge.deviceToken)
                token = challenge.deviceToken
                pairing = nil
                await refresh()
            } else if result.status == "expired" {
                pairingExpired = true
                pairingMessage = "设备码已过期，请刷新后让家长重新扫码"
            } else { pairingMessage = "等待家长选择孩子并确认绑定" }
        } catch {
            if !Task.isCancelled { pairingMessage = "暂时无法连接，请检查网络；联网后会自动继续" }
        }
    }

    func bind(code: String) async {
        await perform {
            let response: BindResponse = try await self.api.call("device-bind", body: [
                "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
                "deviceName": "Apple Watch", "platform": "watchos"])
            // Keep the received token in memory if Keychain fails; never consume another binding code.
            self.token = response.deviceToken
            do { try self.saveCredential(response.deviceToken) }
            catch {
                throw APIError(status: 0, message: "绑定已成功，但凭据保存失败。请勿退出 App；请解锁手表后点击刷新重试保存。")
            }
            try await self.load()
        }
    }

    func refresh() async {
        await perform {
            if let token = self.token { try self.saveCredential(token) }
            try await self.load()
        }
    }

    func submit(rule: RewardRule, note: String) async {
        await perform {
            guard let token = self.token else { return }
            try await self.api.send("requests", token: token, body: [
                "rule_id": String(rule.id), "note": note])
            self.message = "已提交，等待家长确认"
            // A refresh failure must not suggest that the successful write should be retried.
            do { try await self.load() }
            catch { self.message = "申请已提交；列表刷新失败，请点击刷新查看，勿重复提交。" }
        }
    }

    func unbind(code: String) async {
        await perform {
            guard let token = self.token else { return }
            try await self.api.send("device-unbind", token: token, body: ["code": code])
            try self.clearBinding()
            self.message = "设备已解绑"
        }
    }

    func loadSection(_ section: String) async {
        await perform {
            guard let token = self.token else { return }
            switch section {
            case "friends": self.friends = try await self.api.call("friends", token: token)
            case "parents":
                let options: ParentOptions = try await self.api.call("warm-moment-options", token: token)
                self.parents = options.parents
            case "growth":
                let response: GrowthResponse = try await self.api.call("growth-report", token: token)
                self.growth = response.report
            case "connections":
                self.connections = try await self.api.call("family-connections", token: token)
            default:
                self.settings = try await self.api.call("settings", token: token)
                self.face = self.settings?.watchFace ?? "world"
            }
        }
    }

    func loadSocialSpaces() async {
        guard token != nil else { return }
        socialLoading = true; socialError = nil
        defer { socialLoading = false }
        do {
            let reply = try await activityTransport.request(["action": "spaces"])
            guard let rows = reply["items"] as? [[String: Any]] else { throw APIError(status: 0, message: "空间列表无效。") }
            socialSpaces = rows.compactMap { row in
                guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
                return WatchSocialSpace(id: id, name: name, owner: row["owner"] as? Bool ?? false)
            }
        } catch { socialError = error.localizedDescription }
    }

    func loadSocialActivities(spaceID: String) async {
        socialLoading = true; socialError = nil; socialActivities = []
        defer { socialLoading = false }
        do {
            let reply = try await activityTransport.request(["action": "activities", "spaceId": spaceID])
            guard let rows = reply["items"] as? [[String: Any]] else { throw APIError(status: 0, message: "活动列表无效。") }
            socialActivities = rows.compactMap { row in
                guard let id = row["id"] as? String, let title = row["title"] as? String else { return nil }
                return WatchSocialActivity(id: id, title: title, canEdit: row["canEdit"] as? Bool ?? false)
            }
        } catch { socialError = error.localizedDescription }
    }

    func loadSocialPhotos(spaceID: String, activityID: String, more: Bool = false) async {
        guard !socialLoading else { return }
        socialLoading = true; socialError = nil
        if !more { socialPhotos = []; socialPhotosHasMore = false }
        defer { socialLoading = false }
        do {
            let reply = try await activityTransport.request(["action": "photos", "spaceId": spaceID,
                                                             "activityId": activityID, "offset": more ? socialPhotos.count : 0])
            guard let rows = reply["items"] as? [[String: Any]] else { throw APIError(status: 0, message: "照片列表无效。") }
            let page = rows.compactMap { row -> WatchSocialPhoto? in
                guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
                return WatchSocialPhoto(id: id, name: name, author: row["author"] as? String ?? "",
                                        available: row["available"] as? Bool ?? false,
                                        canDelete: row["canDelete"] as? Bool ?? false)
            }
            socialPhotos = more ? socialPhotos + page : page
            socialPhotosHasMore = reply["hasMore"] as? Bool ?? false
        } catch { socialError = error.localizedDescription }
    }

    func socialPreview(spaceID: String, activityID: String, photoID: String) async throws -> Data {
        guard token != nil else { throw APIError(status: 401, message: "请先绑定手表。") }
        let reply = try await activityTransport.request(["action": "thumbnail", "spaceId": spaceID,
                                                         "activityId": activityID, "photoId": photoID])
        guard let data = reply["image"] as? Data, data.count <= 100_000 else {
            throw APIError(status: 0, message: "照片预览无法读取。")
        }
        return data
    }

    func socialRequest(_ action: String, spaceID: String? = nil, activityID: String? = nil,
                       fields: [String: Any] = [:]) async throws -> [String: Any] {
        guard token != nil else { throw APIError(status: 401, message: "请先绑定手表。") }
        var message = fields
        message["action"] = action
        if let spaceID { message["spaceId"] = spaceID }
        if let activityID { message["activityId"] = activityID }
        return try await activityTransport.request(message)
    }

    func shareSocialPhoto(_ data: Data, spaceID: String, activityID: String) async throws {
        guard token != nil else { throw APIError(status: 401, message: "请先绑定手表。") }
        guard data.count > 0, data.count <= 50 * 1024 * 1024 else {
            throw APIError(status: 0, message: "照片超过 50 MB，请选择较小的照片。")
        }
        let operationID = UUID().uuidString
        try await activityTransport.sendPhoto(data, metadata: ["operationId": operationID,
            "spaceId": spaceID, "activityId": activityID, "name": "手表照片.jpg"])
        for _ in 0..<30 {
            let reply = try await socialRequest("photoTransferStatus", fields: ["operationId": operationID])
            let status = reply["status"] as? String ?? "waiting"
            if status == "published" { return }
            if status.hasPrefix("error: ") { throw APIError(status: 0, message: String(status.dropFirst(7))) }
            try await Task.sleep(for: .seconds(4))
        }
        throw APIError(status: 0, message: "照片已发送到 iPhone，登记尚未确认，请稍后刷新相册。")
    }

    func makeFriendCode() async {
        await perform {
            guard let token = self.token else { return }
            self.friendCode = try await self.api.call("friend-code", token: token,
                                                      body: ["expiresInMinutes": "30"])
        }
    }

    func addFriend(code: String) async {
        await perform {
            guard let token = self.token else { return }
            self.friends = try await self.api.call("friends", token: token, body: ["code": code])
            self.message = "已添加好友"
        }
    }

    func saveWarmMoment(parentID: Int, content: String) async -> Bool {
        var saved = false
        await perform {
            guard let token = self.token else { return }
            try await self.api.send("warm-moments", token: token, body: [
                "householdMemberId": String(parentID), "content": content, "inputMethod": "text"])
            saved = true
            self.message = "已保存，爸爸妈妈会看到这份温暖"
        }
        return saved
    }

    func createConnection(kind: String, title: String, intent: String, requestID: UUID) async -> Bool {
        var saved = false
        await perform {
            guard let token = self.token else { return }
            self.connections = try await self.api.call("family-connections", token: token, body: [
                "kind": kind, "title": title, "intent": intent, "requestId": requestID.uuidString])
            saved = true
            self.message = "已告诉家长，可以一起慢慢聊"
        }
        return saved
    }

    func addConnectionEntry(id: Int64, type: String, content: String, requestID: UUID) async -> Bool {
        var saved = false
        await perform {
            guard let token = self.token else { return }
            self.connections = try await self.api.call("family-connections/\(id)/entries", token: token, body: [
                "type": type, "content": content, "requestId": requestID.uuidString])
            saved = true
        }
        return saved
    }

    func completeConnection(id: Int64) async {
        await perform {
            guard let token = self.token else { return }
            self.connections = try await self.api.call("family-connections/\(id)/transition", token: token,
                                                       body: ["action": "complete"])
        }
    }

    func setFace(_ face: WatchFace) async {
        await perform {
            guard let token = self.token, face.available else { return }
            let response: FaceUpdate = try await self.api.call("settings", token: token,
                body: ["watchFace": face.code], method: "PUT")
            self.face = response.watchFace
        }
    }

    private func load() async throws {
        guard let token else { return }
        let score: ScoreResponse = try await api.call("score", token: token)
        let rules: RulesResponse = try await api.call("rules", token: token)
        let requests: RequestsResponse = try await api.call("requests", token: token)
        self.score = score
        self.rules = rules.rules
        self.requests = requests.requests
        let settings: WatchSettings = try await api.call("settings", token: token)
        self.settings = settings
        self.face = settings.watchFace
    }

    private func clearBinding() throws {
        token = nil
        pairing = nil
        pairingExpired = false
        score = nil
        rules = []
        requests = []
        settings = nil
        face = "world"
        friends = nil
        friendCode = nil
        parents = []
        growth = nil
        connections = nil
        socialSpaces = []
        socialActivities = []
        socialPhotos = []
        socialPhotosHasMore = false
        socialError = nil
        try clearCredential()
    }

    private func perform(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await action() }
        catch let error as APIError where error.status == 401 {
            do { try clearBinding(); message = "设备绑定已失效，请让家长扫描新的设备码绑定。" }
            catch { message = error.localizedDescription }
        }
        catch { message = error.localizedDescription }
    }
}
