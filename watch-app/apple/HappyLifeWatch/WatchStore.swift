import AgentIdentityLocalization
import AgentIdentityHTTP
import SwiftUI
import HealthKit
import CryptoKit
import CoreLocation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

struct WatchSocialSpace: Identifiable { let id: String; let name: String; let owner: Bool }
struct WatchSocialActivity: Identifiable { let id: String; let title: String; let sourceTenantId: String; let canEdit: Bool }
struct WatchSocialPhoto: Identifiable {
    let id: String; let name: String; let author: String; let available: Bool; let canDelete: Bool
}

#if canImport(WatchConnectivity)
private final class WatchActivityTransport: NSObject, WCSessionDelegate {
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private var photoTransfers: [String: (CheckedContinuation<Void, Error>, WCSessionFileTransfer)] = [:]

    private var workoutRoot: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ExerciseOutbox") }
    func queueWorkout(_ data: Data, id: UUID) throws {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let acknowledged = UserDefaults.standard.dictionary(forKey: "exercise.acknowledged")?[id.uuidString] as? String {
            guard acknowledged == hash else { throw CocoaError(.fileWriteFileExists) }; return
        }
        try FileManager.default.createDirectory(at: workoutRoot, withIntermediateDirectories: true)
        let file = workoutRoot.appendingPathComponent(id.uuidString + ".json")
        if FileManager.default.fileExists(atPath: file.path) {
            guard try Data(contentsOf: file) == data else { throw CocoaError(.fileWriteFileExists) }
        } else { try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        retryWorkouts()
    }
    func retryWorkouts() {
        guard let session, session.activationState == .activated,
              let files = try? FileManager.default.contentsOfDirectory(at: workoutRoot, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            guard !session.outstandingFileTransfers.contains(where: { $0.file.fileURL.lastPathComponent == file.lastPathComponent }), let data = try? Data(contentsOf: file) else { continue }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            session.transferFile(file, metadata: ["kind": "exercise", "sha256": hash])
        }
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard userInfo["kind"] as? String == "exerciseAck", let raw = userInfo["id"] as? String, let id = UUID(uuidString: raw), let hash = userInfo["sha256"] as? String else { return }
        let file = workoutRoot.appendingPathComponent(id.uuidString + ".json")
        guard let data = try? Data(contentsOf: file), SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash else { return }
        var acknowledged = UserDefaults.standard.dictionary(forKey: "exercise.acknowledged") ?? [:]
        acknowledged[id.uuidString] = hash; UserDefaults.standard.set(acknowledged, forKey: "exercise.acknowledged")
        try? FileManager.default.removeItem(at: file)
    }
    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func request(_ message: [String: Any]) async throws -> [String: Any] {
        guard let session, session.activationState == .activated, session.isReachable else {
            throw APIError(status: 0, message: String(localized: "请让配对的 iPhone 保持连接，并在 iPhone 上登录 Linko Moment 后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        }
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                if let error = reply["error"] as? String {
                    continuation.resume(throwing: APIError(status: 0, message: error))
                } else { continuation.resume(returning: reply) }
            }, errorHandler: { error in
                continuation.resume(throwing: APIError(status: 0, message: String(localized: "无法连接配对的 iPhone：\(watchDisplayError(error))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))))
            })
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { retryWorkouts() }

    func sendPhoto(_ data: Data, metadata: [String: Any]) async throws {
        guard let session, session.activationState == .activated,
              let operationID = metadata["operationId"] as? String else {
            throw APIError(status: 0, message: String(localized: "手表与 iPhone 的照片传输尚未就绪。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
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
                pending.0.resume(throwing: APIError(status: 0, message: String(localized: "照片传输超时，请让配对的 iPhone 保持连接后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))))
            }
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if fileTransfer.file.metadata?["kind"] as? String == "exercise" { return } // Retain until durable iPhone acknowledgement.
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
    func retryWorkouts() { }
    func queueWorkout(_ data: Data, id: UUID) throws { throw CocoaError(.featureUnsupported) }
    func activate() { }
    func request(_ message: [String: Any]) async throws -> [String: Any] {
        throw APIError(status: 0, message: String(localized: "手表活动照片需要 Apple Watch。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
    }
    func sendPhoto(_ data: Data, metadata: [String: Any]) async throws {
        throw APIError(status: 0, message: String(localized: "手表活动照片需要 Apple Watch。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
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
    @Published private(set) var pairingMessage = String(localized: "请家长扫码，或在家庭管理中输入设备码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
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
    let accountLogin: AgentIdentityDeviceLogin
    private lazy var accountAPI = AgentIdentityHTTPClient(origin: accountOrigin, applicationID: "happylife.ai", token: { [weak self] in try await self?.accountLogin.accessToken() })
    private var accountOrigin: URL { URL(string: Bundle.main.object(forInfoDictionaryKey: "HappyLifeIdentityOrigin") as! String)! }
    private let api: WatchAPI
    private let activityTransport = WatchActivityTransport()
    func retryWorkoutSync() {
        activityTransport.retryWorkouts()
        Task {
            guard let context = try? await exerciseContext(), let user = context["userID"] as? String, !user.isEmpty else { return }
            let owner = UUID(uuidString: user)?.uuidString ?? user
            let health = HKHealthStore()
            let predicate = HKQuery.predicateForObjects(withMetadataKey: "net.impx.moment.owner", allowedValues: [owner])
            let samples: [HKSample] = await withCheckedContinuation { continuation in
                health.execute(HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in continuation.resume(returning: samples ?? []) })
            }
            for sample in samples {
                guard let text = sample.metadata?["net.impx.moment.record"] as? String, let data = text.data(using: .utf8), let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let raw = record["id"] as? String, let id = UUID(uuidString: raw), let payload = try? JSONSerialization.data(withJSONObject: ["owner": owner, "record": record], options: [.sortedKeys]) else { continue }
                try? queueWorkoutRecord(payload, id: id)
            }
        }
    }
    func queueWorkoutRecord(_ data: Data, id: UUID) throws {
        try activityTransport.queueWorkout(data, id: id)
        if accountLogin.signedIn { Task { try? await uploadAccountWorkout(data, id: id) } }
    }
    private func uploadAccountWorkout(_ data: Data, id: UUID) async throws {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let owner = envelope["owner"] as? String, let record = envelope["record"] as? [String: Any] else { return }
        let profile = try await accountAPI.send("/api/user/profile?channel=watch")
        guard UUID(uuidString: owner) == UUID(uuidString: profile["unifiedUserId"].text), UUID(uuidString: owner) != nil else { return }
        let body = try JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: record))
        _ = try await accountAPI.send("/api/exercise/records/" + id.uuidString, method: "PUT", body: body)
    }
    func exerciseMetrics(owner: String, values: [String: Double]) async {
        _ = try? await activityTransport.request(["action": "exerciseLive", "owner": owner, "metrics": values])
    }
    func exerciseContext() async throws -> [String: Any] {
        do {
            let context = try await activityTransport.request(["action": "exerciseContext"])
            if let user = context["userID"] as? String, !user.isEmpty { return context }
        } catch { if !accountLogin.signedIn { throw error } }
        let profile = try await accountAPI.send("/api/user/profile?channel=watch")
        let user = profile["unifiedUserId"].text
        guard !user.isEmpty else { throw ServiceClientError.signedOut }
        return ["userID": user]
    }
    // Watch pairing is a device credential; it does not prove the paired phone's account owns this Watch identity.
    lazy var languagePreferences = AgentIdentityLanguageStore(applicationKey: "net.impx.happylife.parent.watchkitapp",
        load: { nil }, save: { _ in })
    private let readCredential: () throws -> String?
    private let saveCredential: (String) throws -> Void
    private let clearCredential: () throws -> Void

    init(api: WatchAPI? = nil,
         readCredential: @escaping () throws -> String? = DeviceCredential.read,
         saveCredential: @escaping (String) throws -> Void = DeviceCredential.save,
         clearCredential: @escaping () throws -> Void = DeviceCredential.clear) {
        let address = Bundle.main.object(forInfoDictionaryKey: "HappyLifeAPIBaseURL") as? String ?? ""
        let origin = URL(string: Bundle.main.object(forInfoDictionaryKey: "HappyLifeIdentityOrigin") as! String)!
        accountLogin = AgentIdentityDeviceLogin(origin: origin, service: (Bundle.main.bundleIdentifier ?? "LinkoMomentWatch") + ".identity")
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
            self.pairingMessage = String(localized: "请家长扫码，或在家庭管理中输入设备码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
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
                pairingMessage = String(localized: "设备码已过期，请刷新后让家长重新扫码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
            } else { pairingMessage = String(localized: "等待家长选择孩子并确认绑定", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
        } catch {
            if !Task.isCancelled { pairingMessage = String(localized: "暂时无法连接，请检查网络；联网后会自动继续", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
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
                throw APIError(status: 0, message: String(localized: "绑定已成功，但凭据保存失败。请勿退出 App；请解锁手表后点击刷新重试保存。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
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
            self.message = String(localized: "已提交，等待家长确认", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
            // A refresh failure must not suggest that the successful write should be retried.
            do { try await self.load() }
            catch { self.message = String(localized: "申请已提交；列表刷新失败，请点击刷新查看，勿重复提交。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
        }
    }

    func unbind(code: String) async {
        await perform {
            guard let token = self.token else { return }
            try await self.api.send("device-unbind", token: token, body: ["code": code])
            try self.clearBinding()
            self.message = String(localized: "设备已解绑", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
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
        socialLoading = true; socialError = nil
        defer { socialLoading = false }
        do {
            let reply = try await activityTransport.request(["action": "spaces"])
            guard let rows = reply["items"] as? [[String: Any]] else { throw APIError(status: 0, message: String(localized: "空间列表无效。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            socialSpaces = rows.compactMap { row in
                guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
                return WatchSocialSpace(id: id, name: name, owner: row["owner"] as? Bool ?? false)
            }
        } catch { socialError = watchDisplayError(error) }
    }

    func loadSocialActivities(spaceID: String) async {
        socialLoading = true; socialError = nil; socialActivities = []
        defer { socialLoading = false }
        do {
            let reply = try await activityTransport.request(["action": "activities", "spaceId": spaceID])
            guard let rows = reply["items"] as? [[String: Any]] else { throw APIError(status: 0, message: String(localized: "活动列表无效。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            socialActivities = rows.compactMap { row in
                guard let id = row["id"] as? String, let title = row["title"] as? String else { return nil }
                return WatchSocialActivity(id: id, title: title,
                                           sourceTenantId: row["sourceTenantId"] as? String ?? spaceID,
                                           canEdit: row["canEdit"] as? Bool ?? false)
            }
        } catch { socialError = watchDisplayError(error) }
    }

    func loadSocialPhotos(spaceID: String, activityID: String, more: Bool = false) async {
        guard !socialLoading else { return }
        socialLoading = true; socialError = nil
        if !more { socialPhotos = []; socialPhotosHasMore = false }
        defer { socialLoading = false }
        do {
            let reply = try await activityTransport.request(["action": "photos", "spaceId": spaceID,
                                                             "activityId": activityID, "offset": more ? socialPhotos.count : 0])
            guard let rows = reply["items"] as? [[String: Any]] else { throw APIError(status: 0, message: String(localized: "照片列表无效。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            let page = rows.compactMap { row -> WatchSocialPhoto? in
                guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
                return WatchSocialPhoto(id: id, name: name, author: row["author"] as? String ?? "",
                                        available: row["available"] as? Bool ?? false,
                                        canDelete: row["canDelete"] as? Bool ?? false)
            }
            socialPhotos = more ? socialPhotos + page : page
            socialPhotosHasMore = reply["hasMore"] as? Bool ?? false
        } catch { socialError = watchDisplayError(error) }
    }

    func socialPreview(spaceID: String, activityID: String, photoID: String) async throws -> Data {
        let reply = try await activityTransport.request(["action": "thumbnail", "spaceId": spaceID,
                                                         "activityId": activityID, "photoId": photoID])
        guard let data = reply["image"] as? Data, data.count <= 100_000 else {
            throw APIError(status: 0, message: String(localized: "照片预览无法读取。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        }
        return data
    }

    func socialRequest(_ action: String, spaceID: String? = nil, activityID: String? = nil,
                       fields: [String: Any] = [:]) async throws -> [String: Any] {
        var message = fields
        message["action"] = action
        if let spaceID { message["spaceId"] = spaceID }
        if let activityID { message["activityId"] = activityID }
        return try await activityTransport.request(message)
    }

    func shareSocialPhoto(_ data: Data, spaceID: String, activityID: String) async throws {
        guard data.count > 0, data.count <= 50 * 1024 * 1024 else {
            throw APIError(status: 0, message: String(localized: "照片超过 50 MB，请选择较小的照片。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        }
        let operationID = UUID().uuidString
        try await activityTransport.sendPhoto(data, metadata: ["operationId": operationID,
            "spaceId": spaceID, "activityId": activityID, "name": String(localized: "手表照片.jpg", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))])
        for _ in 0..<30 {
            let reply = try await socialRequest("photoTransferStatus", fields: ["operationId": operationID])
            let status = reply["status"] as? String ?? "waiting"
            if status == "published" { return }
            if status.hasPrefix("error: ") { throw APIError(status: 0, message: String(status.dropFirst(7))) }
            try await Task.sleep(for: .seconds(4))
        }
        throw APIError(status: 0, message: String(localized: "照片已发送到 iPhone，登记尚未确认，请稍后刷新相册。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
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
            self.message = String(localized: "已添加好友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        }
    }

    func saveWarmMoment(parentID: Int, content: String) async -> Bool {
        var saved = false
        await perform {
            guard let token = self.token else { return }
            try await self.api.send("warm-moments", token: token, body: [
                "householdMemberId": String(parentID), "content": content, "inputMethod": "text"])
            saved = true
            self.message = String(localized: "已保存，爸爸妈妈会看到这份温暖", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
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
            self.message = String(localized: "已告诉家长，可以一起慢慢聊", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
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
            do { try clearBinding(); message = String(localized: "设备绑定已失效，请让家长扫描新的设备码绑定。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
            catch { message = watchDisplayError(error) }
        }
        catch { message = watchDisplayError(error) }
    }
}

@MainActor final class WatchWorkout: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, CLLocationManagerDelegate {
    @Published var running = false
    @Published var active = false
    @Published var saving = false
    @Published var heart: Double?
    @Published var energy: Double?
    @Published var distance: Double?
    @Published var message: String?
    var onCompleted: ((Data, UUID) throws -> Void)?
    var onMetrics: ((String, [String: Double]) -> Void)?
    private var collectionEnded = false
    private var metadataAdded = false
    private let health = HKHealthStore()
    private let locator = CLLocationManager()
    private var route: [[String: Any]] = []
    private var routeSegment = UUID()
    private var lastLocation: CLLocation?
    @Published var altitude: Double?
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var owner = ""
    private var activity: [String: Any]?
    private var id = UUID()
    private var kind = "徒步"
    private var starts: [Date] = []
    private var stops: [Date] = []
    func start(kind: String, context: [String: Any]) async {
        guard !active, !saving, HKHealthStore.isHealthDataAvailable(), let user = context["userID"] as? String, !user.isEmpty else { message = String(localized: "请先在配对 iPhone 登录并连接健康数据。", bundle: AgentIdentityLanguage.appBundle()); return }
        do {
            let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.stepCount)]
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read)
            guard health.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { message = String(localized: "请允许保存体能训练后重试。", bundle: AgentIdentityLanguage.appBundle()); return }
            let config = HKWorkoutConfiguration()
            config.activityType = kind == "徒步" ? .hiking : kind == "慢跑" ? .running : .walking
            config.locationType = .outdoor
            let session = try HKWorkoutSession(healthStore: health, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: config)
            session.delegate = self; builder.delegate = self
            self.session = session; self.builder = builder; self.owner = UUID(uuidString: user)?.uuidString ?? user
            activity = context["activity"] as? [String: Any]; self.kind = kind; id = UUID(); starts = [Date()]; stops = []
            heart = nil; energy = nil; distance = nil; message = nil; collectionEnded = false; metadataAdded = false
            route = []; routeSegment = UUID(); lastLocation = nil; altitude = nil
            locator.delegate = self; locator.desiredAccuracy = kCLLocationAccuracyBest; locator.distanceFilter = 5; locator.activityType = .fitness
            locator.requestWhenInUseAuthorization()
            session.startActivity(with: starts[0]); active = true; running = true
            locator.startUpdatingLocation()
            try await builder.beginCollection(at: starts[0])
        } catch { session?.end(); active = false; running = false; message = String(localized: "运动启动失败：\(error.localizedDescription)", bundle: AgentIdentityLanguage.appBundle()) }
    }
    func duration(at now: Date) -> TimeInterval {
        starts.enumerated().reduce(0) { $0 + max(0, (stops.indices.contains($1.offset) ? stops[$1.offset] : now).timeIntervalSince($1.element)) }
    }
    func toggle() {
        guard active, !saving, let session, session.state == .running || session.state == .paused else { return }
        if running { stops.append(Date()); session.pause() } else { starts.append(Date()); session.resume() }
        running.toggle()
        if running { routeSegment = UUID(); lastLocation = nil; locator.startUpdatingLocation() } else { locator.stopUpdatingLocation() }
    }
    func finish() async {
        guard active, !saving, let session, let builder else { return }
        saving = true
        defer { saving = false }
        let end = stops.count == starts.count ? stops.last! : Date()
        if stops.count < starts.count { stops.append(end) }
        running = false; locator.stopUpdatingLocation()
        if session.state != .stopped && session.state != .ended { session.stopActivity(with: end) }
        do {
            let deadline = Date().addingTimeInterval(15)
            while session.state != .stopped && session.state != .ended {
                guard Date() < deadline else { throw CancellationError() }
                try await Task.sleep(for: .milliseconds(100))
            }
            if !collectionEnded { try await builder.endCollection(at: end); collectionEnded = true }
            distance = builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()) ?? distance
            let formatter = ISO8601DateFormatter()
            let intervals: [[String: Any]] = zip(starts, stops).enumerated().map { index, pair in
                var row: [String: Any] = ["start": formatter.string(from: pair.0), "end": formatter.string(from: pair.1)]
                if let distance { row["distanceMeters"] = index == 0 ? distance : 0 }
                return row
            }
            var record: [String: Any] = ["id": id.uuidString, "kind": kind, "startedAt": formatter.string(from: starts[0]), "endedAt": formatter.string(from: end), "intervals": intervals]
            if let activity { record["activity"] = activity }
            let text = String(data: try JSONSerialization.data(withJSONObject: record), encoding: .utf8)!
            if !metadataAdded { try await builder.addMetadata(["net.impx.moment.owner": owner, "net.impx.moment.record": text, "net.impx.moment.delivery": "watch-connectivity"]); metadataAdded = true }
            var delivered = record
            let includedRoute = route.filter { point in
                guard let text = point["recordedAt"] as? String, let at = formatter.date(from: text) else { return false }
                return zip(starts, stops).contains { at >= $0.0 && at <= $0.1 }
            }
            if !includedRoute.isEmpty { delivered["routeEnabled"] = true; delivered["route"] = includedRoute }
            let payload = try JSONSerialization.data(withJSONObject: ["owner": owner, "record": delivered], options: [.sortedKeys])
            guard let onCompleted else { throw CocoaError(.fileWriteUnknown) }
            try onCompleted(payload, id)
            _ = try await builder.finishWorkout()
            session.end()
            onMetrics?(owner, [:])
            active = false; self.session = nil; self.builder = nil
            message = String(localized: "运动已保存并加入同步队列，手机接收后会同步到账号和关联活动。", bundle: AgentIdentityLanguage.appBundle())
        } catch { message = String(localized: "保存未完成，请保留页面重试：\(error.localizedDescription)", bundle: AgentIdentityLanguage.appBundle()) }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active, running, route.count < 20_000 else { return }
        let formatter = ISO8601DateFormatter()
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 65,
                  abs(location.timestamp.timeIntervalSinceNow) <= 15, let start = starts.last, location.timestamp >= start else { continue }
            if let lastLocation {
                let gap = location.timestamp.timeIntervalSince(lastLocation.timestamp)
                guard gap >= 5, location.distance(from: lastLocation) >= 3, location.distance(from: lastLocation) / gap < 20 else { continue }
                if gap > 60 { routeSegment = UUID() }
            }
            var point: [String: Any] = ["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude, "recordedAt": formatter.string(from: location.timestamp), "segment": routeSegment.uuidString]
            if location.verticalAccuracy >= 0, location.altitude.isFinite {
                altitude = location.altitude; point["altitudeMeters"] = location.altitude; point["verticalAccuracyMeters"] = location.verticalAccuracy
            }
            route.append(point); lastLocation = location
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            if toState == .paused || toState == .ended {
                if self.running, self.stops.count < self.starts.count { self.stops.append(date) }
                self.running = false
            } else if toState == .running && !self.running {
                if self.stops.count == self.starts.count { self.starts.append(date) }
                self.running = true
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in if self.stops.count < self.starts.count { self.stops.append(Date()) }; self.running = false; self.message = String(localized: "运动会话异常：\(error.localizedDescription)", bundle: AgentIdentityLanguage.appBundle()) }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            guard self.active, self.running else { return }
            self.heart = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            self.energy = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            self.distance = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
            var values: [String: Double] = [:]
            if let heart = self.heart { values["heart"] = heart }
            if let energy = self.energy { values["energy"] = energy }
            if let distance = self.distance { values["distance"] = distance }
            self.onMetrics?(self.owner, values)
        }
    }
}

struct WatchWorkoutView: View {
    @EnvironmentObject private var workout: WatchWorkout
    @EnvironmentObject private var store: WatchStore
    @State private var kind = "徒步"
    @State private var connecting = false
    @State private var error: String?
    var body: some View {
        List {
            if workout.active {
                Text(workout.running ? String(localized: "运动中", bundle: AgentIdentityLanguage.appBundle()) : String(localized: "已暂停", bundle: AgentIdentityLanguage.appBundle()))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = Int(workout.duration(at: context.date))
                    Text(String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)).monospacedDigit()
                }
                if let altitude = workout.altitude { Text(String(format: String(localized: "海拔 %.1f 米", bundle: AgentIdentityLanguage.appBundle()), altitude)) }
                if let heart = workout.heart { Text(String(format: String(localized: "心率 %.0f 次/分", bundle: AgentIdentityLanguage.appBundle()), heart)) }
                if let energy = workout.energy { Text(String(format: String(localized: "%.0f 千卡", bundle: AgentIdentityLanguage.appBundle()), energy)) }
                if let distance = workout.distance { Text(String(format: String(localized: "%.2f 公里", bundle: AgentIdentityLanguage.appBundle()), distance / 1000)) }
                Button(workout.running ? String(localized: "暂停", bundle: AgentIdentityLanguage.appBundle()) : String(localized: "继续", bundle: AgentIdentityLanguage.appBundle())) { workout.toggle() }.disabled(workout.saving)
                Button(String(localized: "结束并保存", bundle: AgentIdentityLanguage.appBundle())) { Task { await workout.finish() } }.disabled(workout.saving)
            } else {
                Picker(String(localized: "运动", bundle: AgentIdentityLanguage.appBundle()), selection: $kind) { ForEach(["徒步", "散步", "慢跑"], id: \.self) { Text($0) } }
                Button(String(localized: "开始\(kind)", bundle: AgentIdentityLanguage.appBundle())) { Task {
                    connecting = true; error = nil
                    defer { connecting = false }
                    workout.onCompleted = { data, id in try store.queueWorkoutRecord(data, id: id) }
                    workout.onMetrics = { owner, values in Task { await store.exerciseMetrics(owner: owner, values: values) } }
                    do { await workout.start(kind: kind, context: try await store.exerciseContext()) }
                    catch { self.error = error.localizedDescription }
                } }.disabled(connecting)
                Text(String(localized: "开始前连接已登录的 iPhone，运动中可独立采集健康数据。活动关联以 iPhone 最近选择的活动为准。", bundle: AgentIdentityLanguage.appBundle())).font(.footnote)
            }
            Button(String(localized: "重试同步运动记录", bundle: AgentIdentityLanguage.appBundle())) { store.retryWorkoutSync() }
            if let text = error ?? workout.message { Text(text).font(.footnote) }
            if connecting || workout.saving { ProgressView() }
        }.navigationTitle(String(localized: "运动", bundle: AgentIdentityLanguage.appBundle()))
    }
}
