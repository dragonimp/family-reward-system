import Foundation

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
struct WatchAPITests {
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: configuration)
        let api = WatchAPI(baseURL: URL(string: "https://example.test")!, session: session)
        StubProtocol.handler = { request in
            precondition(request.url!.path == "/api/watch/score")
            precondition(request.url!.query == nil)
            precondition(request.value(forHTTPHeaderField: "X-Watch-Device-Token") == "test-device")
            return (200, #"{"familyGroupName":"测试家庭","children":[{"id":1,"name":"孩子","points":12.5,"cash":2,"items":3}]}"#)
        }
        let score: ScoreResponse = try await api.call("score", token: "test-device")
        precondition(score.children[0].points == Decimal(string: "12.5")!)

        StubProtocol.handler = { request in
            precondition(request.httpMethod == "POST")
            precondition(request.value(forHTTPHeaderField: "X-Watch-Device-Token") == nil)
            return (200, #"{"deviceToken":"bound-token"}"#)
        }
        let bound: BindResponse = try await api.call("device-bind", body: ["code": "test-code", "platform": "watchos"])
        precondition(bound.deviceToken == "bound-token")

        StubProtocol.handler = { request in
            precondition(request.httpMethod == "POST")
            let stream = request.httpBodyStream!
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = stream.read(&bytes, maxLength: bytes.count)
            let body = try JSONDecoder().decode([String: String].self, from: Data(bytes.prefix(count)))
            precondition(body == ["rule_id": "7", "note": "已完成"])
            return (201, #"{"id":8,"title":"整理房间","statusText":"待确认"}"#)
        }
        try await api.send("requests", token: bound.deviceToken, body: ["rule_id": "7", "note": "已完成"])

        for status in [400, 401, 403, 500] {
            StubProtocol.handler = { _ in (status, #"{"error":"测试错误","code":"test"}"#) }
            do {
                let _: ScoreResponse = try await api.call("score", token: "test")
                preconditionFailure("Expected HTTP error")
            } catch let error as APIError {
                precondition(error.status == status && error.message == "测试错误")
            }
        }
        var attempts = 0
        StubProtocol.handler = { _ in attempts += 1; throw URLError(.timedOut) }
        do {
            try await api.send("requests", token: "test", body: ["rule_id": "7"])
            preconditionFailure("Expected timeout")
        } catch let error as URLError { precondition(error.code == .timedOut) }
        precondition(attempts == 1, "A write must never retry automatically")

        let insecure = WatchAPI(baseURL: URL(string: "http://example.test")!, session: session)
        do {
            try await insecure.send("score", token: "test")
            preconditionFailure("HTTP must be rejected")
        } catch let error as APIError { precondition(error.status == 0) }
        precondition(attempts == 1)
        print("PASS: score decoding, token header, binding, request body, HTTP errors, timeout without retry, HTTPS enforcement")

        StubProtocol.handler = { request in
            precondition(request.httpMethod == "PUT")
            return (200, #"{"watchFace":"world","updatedAt":"2026-09-15T00:00:00Z"}"#)
        }
        let updated: FaceUpdate = try await api.call("settings", token: "test",
            body: ["watchFace": "world"], method: "PUT")
        precondition(updated.watchFace == "world")

        let fixtures = [
            "score": #"{"familyGroupName":"家庭","children":[]}"#,
            "rules": #"{"rules":[{"id":7,"name":"整理房间","points":2,"description":"整理自己的房间"}]}"#,
            "requests": #"{"requests":[]}"#,
            "settings": #"{"watchFace":"world","friendLeaderboardEnabled":false,"availableFaces":[{"code":"meteor","name":"流星","vip":true,"available":false}]}"#,
            "friends": #"{"friends":[{"profileKey":"child-2","name":"好友","score":2.5}],"leaderboard":[{"profileKey":"child-1","name":"我","score":3,"rank":1,"isSelf":true}]}"#,
            "warm-moment-options": #"{"parents":[{"id":1,"roleLabel":"妈妈"}]}"#,
            "growth-report": #"{"report":{"praise":"今天很棒","nextStep":"明天继续加油"}}"#
        ]
        let success: (URLRequest) throws -> (Int, String) = { request in
            (200, fixtures[request.url!.lastPathComponent]!)
        }
        var persisted: String? = "restored-token"
        let store = WatchStore(api: api, readCredential: { persisted },
            saveCredential: { persisted = $0 }, clearCredential: { persisted = nil })
        StubProtocol.handler = success
        await store.start()
        precondition(store.token == "restored-token" && store.rules.count == 1)
        precondition(store.settings?.availableFaces.first?.available == false)
        await store.loadSection("friends")
        await store.loadSection("parents")
        await store.loadSection("growth")
        precondition(store.friends?.leaderboard.first?.isSelf == true)
        precondition(store.parents.first?.roleLabel == "妈妈")
        precondition(store.growth?.praise == "今天很棒")

        StubProtocol.handler = { _ in (500, #"{"error":"服务暂时不可用"}"#) }
        await store.refresh()
        precondition(store.token == "restored-token" && persisted == "restored-token")
        var writes = 0
        StubProtocol.handler = { request in
            if request.httpMethod == "POST" { writes += 1; return (201, "{}") }
            return (500, #"{"error":"刷新失败"}"#)
        }
        await store.submit(rule: store.rules[0], note: "")
        precondition(writes == 1 && store.message!.contains("申请已提交"))
        StubProtocol.handler = { _ in (401, #"{"error":"绑定已失效"}"#) }
        await store.refresh()
        precondition(store.token == nil && persisted == nil && store.friends == nil && store.growth == nil)
        precondition(store.rules.isEmpty && store.score == nil)
        print("PASS: Web feature contracts, PUT settings, credential restore, 500 retains binding, successful write survives refresh failure, 401 clears child data")

        persisted = nil
        let pairingStore = WatchStore(api: api, readCredential: { persisted },
            saveCredential: { persisted = $0 }, clearCredential: { persisted = nil })
        await pairingStore.start()
        StubProtocol.handler = { request in
            precondition(request.httpMethod == "POST" && request.url!.lastPathComponent == "pairing")
            return (200, #"{"code":"ABCD2345","deviceToken":"private-device-token","expiresAt":"2026-09-16T00:10:00Z","verificationUrl":"https://example.test/children?watchCode=ABCD2345","qrModules":[[true,false],[false,true]]}"#)
        }
        await pairingStore.beginPairing()
        precondition(pairingStore.token == nil && pairingStore.pairing?.code == "ABCD2345")
        precondition(persisted!.hasPrefix("pairing:"))
        let restoredPairing = WatchStore(api: api, readCredential: { persisted },
            saveCredential: { persisted = $0 }, clearCredential: { persisted = nil })
        await restoredPairing.start()
        precondition(restoredPairing.pairing?.deviceToken == "private-device-token")
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await restoredPairing.pollPairing()
        precondition(restoredPairing.pairing != nil && persisted!.hasPrefix("pairing:"))
        StubProtocol.handler = { request in
            if request.url!.lastPathComponent == "pairing" {
                precondition(request.httpMethod == "GET")
                precondition(request.url!.query == nil)
                precondition(request.value(forHTTPHeaderField: "X-Watch-Device-Token") == "private-device-token")
                return (200, #"{"status":"approved"}"#)
            }
            return try success(request)
        }
        await restoredPairing.pollPairing()
        precondition(restoredPairing.token == "private-device-token" && persisted == "private-device-token")
        precondition(restoredPairing.pairing == nil && restoredPairing.rules.count == 1)
        StubProtocol.handler = { _ in (200, #"{"status":"expired"}"#) }
        await pairingStore.pollPairing()
        precondition(pairingStore.pairingExpired && pairingStore.token == nil)
        let transferStore = WatchStore(api: api, readCredential: { persisted },
            saveCredential: { persisted = $0 }, clearCredential: { persisted = nil })
        StubProtocol.handler = { request in try success(request) }
        await transferStore.start()
        StubProtocol.handler = { request in
            precondition(request.httpMethod == "POST" && request.url!.lastPathComponent == "pairing")
            precondition(request.value(forHTTPHeaderField: "X-Watch-Device-Token") == "private-device-token")
            return (200, #"{"code":"WXYZ2345","deviceToken":"replacement-token","expiresAt":"2026-09-16T00:10:00Z","verificationUrl":"https://example.test/children?watchCode=WXYZ2345","qrModules":[[true,false],[false,true]]}"#)
        }
        await transferStore.beginPairing()
        precondition(transferStore.token == "private-device-token" && persisted!.hasPrefix("transfer:"))
        let restoredTransfer = WatchStore(api: api, readCredential: { persisted },
            saveCredential: { persisted = $0 }, clearCredential: { persisted = nil })
        await restoredTransfer.start()
        precondition(restoredTransfer.token == "private-device-token" && restoredTransfer.pairing?.code == "WXYZ2345")
        StubProtocol.handler = { request in
            if request.url!.lastPathComponent == "pairing" {
                precondition(request.value(forHTTPHeaderField: "X-Watch-Device-Token") == "replacement-token")
                return (200, #"{"status":"approved"}"#)
            }
            return try success(request)
        }
        await restoredTransfer.pollPairing()
        precondition(restoredTransfer.token == "replacement-token" && persisted == "replacement-token")
        print("PASS: QR pairing, pending Keychain restore, transfer with old-token proof, offline recovery, approval and expiration")
    }
}
