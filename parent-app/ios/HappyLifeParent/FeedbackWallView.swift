import SwiftUI
import AgentIdentity

private struct WallPost: Decodable, Identifiable {
    let id: Int
    let category: String
    let title: String
    let content: String
    let createdAt: String
    let requestedPublic: Bool
    let moderationStatus: String
    let status: String
    let replyContent: String?
    let upvotes: Int
    let downvotes: Int
    let score: Int
    let myVote: Int
    let isMine: Bool
}

private struct WallSnapshot: Decodable {
    let total: Int
    let wishes: Int
    let opinions: Int
    let upvotes: Int
    let downvotes: Int
    let items: [WallPost]
}

@MainActor
private final class FeedbackWallStore: ObservableObject {
    @Published var snapshot = WallSnapshot(total: 0, wishes: 0, opinions: 0, upvotes: 0, downvotes: 0, items: [])
    @Published var mine: [WallPost] = []
    @Published var error: String?
    @Published var busy = false

    private let origin = URL(string: "https://auth.ai.xmkurt.com")!
    private let clientID = "happylife.ai"
    private let session = URLSession(configuration: .ephemeral)
    private weak var identity: AgentIdentitySession?

    init(identity: AgentIdentitySession?) { self.identity = identity }
    var isAuthenticated: Bool { identity?.isAuthenticated == true }

    private func call<T: Decodable>(_ suffix: String = "", method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: "/api/feedback/wall/\(clientID)\(suffix)", relativeTo: origin)?.absoluteURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try await identity?.validAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if method != "GET" || suffix == "/mine" {
            throw WallError.loginRequired
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == origin.host else { throw WallError.unavailable }
        if http.statusCode == 401 { throw WallError.loginRequired }
        guard http.statusCode == 200 else { throw WallError.server(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func refresh() async {
        do {
            snapshot = try await call()
            if identity?.isAuthenticated == true {
                mine = try await call("/mine")
            } else {
                mine = []
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func submit(requestId: UUID, category: String, title: String, content: String, requestedPublic: Bool) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let _: WallPost = try await call(method: "POST", body: [
                "requestId": requestId.uuidString, "category": category,
                "title": title, "content": content, "requestedPublic": requestedPublic
            ])
            await refresh()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func vote(_ post: WallPost, value: Int) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let _: WallPost = try await call("/\(post.id)/vote", method: "PUT", body: ["value": value])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
}

private enum WallError: LocalizedError {
    case loginRequired, unavailable, server(Int)
    var errorDescription: String? {
        switch self {
        case .loginRequired: "请先在“我的”登录用户中心。"
        case .unavailable: "反馈服务暂时不可用。"
        case .server(let code): "反馈服务返回错误（\(code)），请稍后重试。"
        }
    }
}

struct FeedbackWallView: View {
    @StateObject private var store: FeedbackWallStore
    @State private var category = "wish"
    @State private var showingComposer = false
    @State private var showingMine = false

    init(identity: AgentIdentitySession?) {
        _store = StateObject(wrappedValue: FeedbackWallStore(identity: identity))
    }

    var body: some View {
        List {
            Section {
                Picker("栏目", selection: $category) {
                    Text("心愿墙").tag("wish")
                    Text("意见墙").tag("opinion")
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("已公开 \(store.snapshot.total)")
                    Spacer()
                    Text("赞成 \(store.snapshot.upvotes)")
                    Spacer()
                    Text("反对 \(store.snapshot.downvotes)")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let error = store.error {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section(category == "wish" ? "心愿提案 · \(store.snapshot.wishes)" : "意见提案 · \(store.snapshot.opinions)") {
                if store.snapshot.items.contains(where: { $0.category == category }) {
                    ForEach(store.snapshot.items.filter { $0.category == category }) { post in
                        postRow(post, voting: true)
                    }
                } else {
                    Text("还没有审核通过的提案").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("用户反馈")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("我的反馈") { showingMine = true }
                Button { showingComposer = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("发布反馈")
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
        .sheet(isPresented: $showingComposer) {
            FeedbackComposer(category: category, error: store.error) { requestId, title, content, requestedPublic in
                await store.submit(requestId: requestId, category: category, title: title, content: content,
                                   requestedPublic: requestedPublic)
            }
        }
        .sheet(isPresented: $showingMine) {
            NavigationStack {
                List {
                    if !store.isAuthenticated {
                        Text("请先返回“我的”登录用户中心。").foregroundStyle(.secondary)
                    } else if store.mine.isEmpty {
                        Text("还没有提交反馈。").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.mine) { post in postRow(post, voting: false) }
                    }
                }
                .navigationTitle("我的反馈")
                .toolbar { Button("完成") { showingMine = false } }
                .refreshable { await store.refresh() }
            }
        }
    }

    private func postRow(_ post: WallPost, voting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.title).font(.headline)
            Text(post.content)
            if voting {
                HStack {
                    Button {
                        Task { await store.vote(post, value: post.myVote == 1 ? 0 : 1) }
                    } label: {
                        Label("\(post.upvotes)", systemImage: post.myVote == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                    }
                    Button {
                        Task { await store.vote(post, value: post.myVote == -1 ? 0 : -1) }
                    } label: {
                        Label("\(post.downvotes)", systemImage: post.myVote == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }
                    Text("净支持 \(post.score)").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(post.isMine || store.busy)
            } else {
                Text(status(post)).font(.footnote).foregroundStyle(.secondary)
                if let reply = post.replyContent, !reply.isEmpty {
                    Text("回复：\(reply)").font(.footnote)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func status(_ post: WallPost) -> String {
        switch post.moderationStatus {
        case "private": "仅自己可见"
        case "pending": "申请公开 · 待审核"
        case "approved": "已公开"
        case "rejected": "公开申请未通过"
        default: "处理中"
        }
    }
}

private struct FeedbackComposer: View {
    let category: String
    let error: String?
    let submit: (UUID, String, String, Bool) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var requestedPublic = false
    @State private var busy = false
    @State private var requestId = UUID()
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("简短标题", text: $title)
                        .focused($titleFocused)
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                        .accessibilityLabel("反馈内容")
                } header: {
                    Text(category == "wish" ? "提交心愿" : "提交意见")
                }
                Section {
                    Toggle("审核通过后公开展示", isOn: $requestedPublic)
                    Text("关闭时仅自己和管理员可见。开启后，审核通过才会出现在公开墙，其他用户可点赞或点踩。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(category == "wish" ? "写心愿" : "提意见")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") {
                        busy = true
                        Task {
                            if await submit(requestId, title.trimmingCharacters(in: .whitespacesAndNewlines),
                                            content.trimmingCharacters(in: .whitespacesAndNewlines),
                                            requestedPublic) { dismiss() }
                            busy = false
                        }
                    }
                    .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { titleFocused = true }
        }
    }
}
