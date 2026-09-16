import Foundation

struct ScoreResponse: Decodable { let familyGroupName: String; let children: [ChildScore] }
struct ChildScore: Decodable, Identifiable {
    let id: Int
    let name: String
    let points: Decimal
    let cash: Decimal
    let items: Int
}
struct RulesResponse: Decodable { let rules: [RewardRule] }
struct RewardRule: Decodable, Identifiable {
    let id: Int
    let name: String
    let points: Decimal
    let description: String
}
struct RequestsResponse: Decodable { let requests: [RewardRequest] }
struct RewardRequest: Decodable, Identifiable {
    let id: Int
    let title: String
    let statusText: String
}
struct PairingChallenge: Codable {
    let code: String
    let deviceToken: String
    let expiresAt: String
    let verificationUrl: String
    let qrModules: [[Bool]]
}
struct PairingStatus: Decodable { let status: String }
struct BindResponse: Decodable { let deviceToken: String }
struct WatchSettings: Decodable {
    let watchFace: String
    let friendLeaderboardEnabled: Bool
    let availableFaces: [WatchFace]
}
struct WatchFace: Decodable, Identifiable {
    let code: String
    let name: String
    let vip: Bool
    let available: Bool
    var id: String { code }
}
struct FaceUpdate: Decodable { let watchFace: String }
struct FriendsResponse: Decodable { let friends: [ChildFriend]; let leaderboard: [ChildFriend] }
struct ChildFriend: Decodable, Identifiable {
    let profileKey: String
    let name: String
    let score: Decimal
    let rank: Int?
    let isSelf: Bool?
    var id: String { profileKey }
}
struct FriendCode: Decodable { let code: String; let expiresAt: String }
struct ParentOptions: Decodable { let parents: [ParentOption] }
struct ParentOption: Decodable, Identifiable { let id: Int; let roleLabel: String }
struct GrowthResponse: Decodable { let report: GrowthReport? }
struct GrowthReport: Decodable { let praise: String; let nextStep: String }
struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Device credentials must never be forwarded to another origin.
        completionHandler(nil)
    }
}

final class WatchAPI {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? URLSession(configuration: .ephemeral,
                                             delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    func call<T: Decodable>(_ path: String, token: String? = nil,
                            body: [String: String]? = nil, method: String? = nil) async throws -> T {
        let data = try await send(path, token: token, body: body, method: method)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    func send(_ path: String, token: String? = nil,
              body: [String: String]? = nil, method: String? = nil) async throws -> Data {
        guard baseURL.scheme == "https", baseURL.host != nil else {
            throw APIError(status: 0, message: "服务地址必须使用 HTTPS")
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/watch/" + path))
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue(token, forHTTPHeaderField: "X-Watch-Device-Token") }
        if let body {
            request.httpMethod = method ?? "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let payload = try? JSONDecoder().decode([String: String].self, from: data)
            throw APIError(status: response.statusCode,
                           message: payload?["error"] ?? "服务暂时不可用（\(response.statusCode)）")
        }
        return data
    }
}
