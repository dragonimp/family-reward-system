import SwiftUI

// The Family API owns Orbit authorization and uses Goldfish.WebAppSdk. The iOS
// client only speaks the application's authenticated conversation contract.
struct FamilyChatView: View {
    @ObservedObject var store: FamilyStore
    @State private var agents: [Record] = []
    @State private var sessions: [[String: Any]] = []
    @State private var sessionID: String?
    @State private var messages: [[String: Any]] = []
    @State private var draft = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error {
                    Text(error).foregroundStyle(.red).padding()
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { composerFocused = false }
                }
                if agents.isEmpty && !busy {
                    ContentUnavailableView("暂无可用智能体", systemImage: "bubble.left.and.bubble.right", description: Text("请在家庭积分应用中授权智能体后刷新。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { composerFocused = false }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                                    let mine = message["role"] as? String == "user"
                                    VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                                        Text(mine ? "我" : "AI 助手").font(.caption).foregroundStyle(.secondary)
                                        Text(message["content"] as? String ?? "").textSelection(.enabled)
                                            .padding(12).background(mine ? Color.teal.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                                    }.frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading).id(index)
                                }
                                if busy { ProgressView("正在等待回复…").frame(maxWidth: .infinity, alignment: .leading) }
                            }.padding()
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
                        .onChange(of: messages.count) { _, count in if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) } }
                    }
                }
                HStack(alignment: .bottom) {
                    TextField("输入消息", text: $draft, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                        .focused($composerFocused)
                    Button("发送", systemImage: "arrow.up.circle.fill") { Task { await send() } }
                        .labelStyle(.iconOnly).font(.title2)
                        .disabled(busy || agents.isEmpty || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding().background(.bar)
            }
            .navigationTitle("AI 对话")
            .toolbar {
                Menu {
                    Button("新建对话", systemImage: "plus") { composerFocused = false; sessionID = nil; messages = []; error = nil }
                    ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                        if let id = session["id"] as? String {
                            Button(session["name"] as? String ?? "对话") { composerFocused = false; Task { await open(id) } }
                        }
                    }
                } label: { Image(systemName: "clock.arrow.circlepath") }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            agents = try Record.list(await store.call("/api/agentfree/agents"))
            sessions = try stringRecords(await store.call("/api/agentfree/sessions"))
            if let sessionID { await open(sessionID) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func open(_ id: String) async {
        do {
            messages = try stringRecords(await store.call("/api/agentfree/sessions/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)/messages?take=100"))
            sessionID = id
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func send() async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, let agent = agents.first else { return }
        composerFocused = false
        busy = true; error = nil
        defer { busy = false }
        do {
            if sessionID == nil {
                guard let created = try await store.call("/api/agentfree/sessions", method: "POST", body: ["agentId": agent.id, "name": String(message.prefix(24))]) as? [String: Any],
                      let id = created["id"] as? String else { throw APIError.message("创建对话失败。") }
                sessionID = id
            }
            guard let sessionID else { return }
            draft = ""
            messages.append(["role": "user", "content": message])
            try await store.streamChat(sessionID: sessionID, message: message)
            await open(sessionID)
            sessions = try stringRecords(await store.call("/api/agentfree/sessions"))
        } catch {
            if let sessionID { await open(sessionID) }
            self.error = error.localizedDescription
        }
    }

    private func stringRecords(_ value: Any) throws -> [[String: Any]] {
        guard let rows = value as? [[String: Any]] else { throw APIError.message("对话数据格式不正确。") }
        return rows
    }
}
