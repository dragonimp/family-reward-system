import SwiftUI

@MainActor
final class WatchStore: ObservableObject {
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
    @Published private(set) var busy = false
    @Published private(set) var ready = false
    @Published var message: String?
    private let api: WatchAPI
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
    }

    func start() async {
        guard !ready else { return }
        await perform {
            let credential = try self.readCredential()
            if let credential, credential.hasPrefix("pairing:") {
                self.pairing = try JSONDecoder().decode(PairingChallenge.self, from: Data(credential.dropFirst(8).utf8))
            } else { self.token = credential }
            self.ready = true
            if self.token != nil { try await self.load() }
        }
    }

    func beginPairing() async {
        guard token == nil, pairing == nil || pairingExpired else { return }
        await perform {
            let challenge: PairingChallenge = try await self.api.call("pairing", body: [
                "deviceName": "Apple Watch", "platform": "watchos"])
            // Persist the private token before showing its public code. A restart can recover approval.
            let saved = String(decoding: try JSONEncoder().encode(challenge), as: UTF8.self)
            try self.saveCredential("pairing:" + saved)
            self.pairing = challenge
            self.pairingExpired = false
            self.pairingMessage = "请家长扫码，或在家庭管理中输入设备码"
        }
    }

    func pollPairing() async {
        guard token == nil, let challenge = pairing, !busy, !pairingExpired else { return }
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
            default:
                self.settings = try await self.api.call("settings", token: token)
                self.face = self.settings?.watchFace ?? "world"
            }
        }
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
