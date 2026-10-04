import Foundation
import SwiftUI
import AgentIdentity

@MainActor final class FamilyStore: ObservableObject {
    let identity = AgentIdentitySession(origin: URL(string: "https://happylife.ai.impx.net")!, callback: URL(string: "linkofamily://login-complete/")!, keychainService: "net.impx.happylife.parent.identity")
    private let base = URL(string: "https://happylife.ai.impx.net")!
    private let session = URLSession(configuration: .ephemeral)
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
    var scope: String { groupID == 0 ? "" : "familyGroupId=\(groupID)" }
    var ready: Bool { profile?.text("role") == "parent" && profile?.flag("needsRole") == false }
    var selectedFamily: String { groups.first(where: { $0.id == groupID })?.text("name") ?? "我的家庭" }

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
    func selectParent() async {
        do { _ = try await call("/api/user/profile", method: "POST", body: ["channel":"pc", "role":"parent"]); await load() }
        catch { self.error = error.localizedDescription }
    }
    func logout() {
        revision = UUID(); identity.logout(); profile = nil; groups = []; children = []; rules = []; requests = []; transactions = []; growth = []; members = []; groupID = 0; loading = false
    }
}
