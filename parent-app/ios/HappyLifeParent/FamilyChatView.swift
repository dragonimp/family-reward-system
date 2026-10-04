import SwiftUI

// The Family API owns Orbit authorization and uses Goldfish.WebAppSdk. The iOS
// client only speaks the application's authenticated conversation contract.
struct FamilyChatView: View {
    @ObservedObject var store: FamilyStore
    @State private var agents: [Record] = []
    @State private var sessions: [[String: Any]] = []
    @State private var selectedAgentID: Int?
    @State private var sessionID: String?
    @State private var messages: [[String: Any]] = []
    @State private var draft = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showingSessions = false
    @State private var showingArchived = false
    @State private var renamingSessionID: String?
    @State private var sessionName = ""
    @FocusState private var composerFocused: Bool

    private var selectedAgent: Record? { agents.first { $0.id == selectedAgentID } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !agents.isEmpty {
                    HStack {
                        Menu {
                            ForEach(agents) { agent in
                                Button(agent.text("name")) { selectAgent(agent.id) }
                            }
                        } label: {
                            Label(selectedAgent?.text("name") ?? "选择智能体", systemImage: "person.crop.circle")
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("会话管理", systemImage: "tray.full") {
                            composerFocused = false
                            showingSessions = true
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
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
                        .disabled(busy || selectedAgent == nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding().background(.bar)
            }
            .navigationTitle("智能体对话")
            .toolbar {
                Button("新建对话", systemImage: "plus") { newConversation() }
                    .disabled(selectedAgent == nil || busy)
            }
            .sheet(isPresented: $showingSessions) { sessionManager }
            .alert("修改会话名称", isPresented: Binding(
                get: { renamingSessionID != nil },
                set: { if !$0 { renamingSessionID = nil } }
            )) {
                TextField("会话名称", text: $sessionName)
                Button("取消", role: .cancel) { renamingSessionID = nil }
                Button("保存") { Task { await renameSession() } }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var sessionManager: some View {
        NavigationStack {
            List {
                ForEach(agents) { agent in
                    let rows = sessions.filter { ($0["agentId"] as? Int) == agent.id && ($0["isArchived"] as? Bool == true) == showingArchived }
                    if !rows.isEmpty {
                        Section(agent.text("name")) {
                            ForEach(rows, id: \.sessionIdentifier) { session in
                                if let id = session["id"] as? String {
                                    Button {
                                        if showingArchived {
                                            Task { await changeArchive(id, archived: false, openAfterRestore: true) }
                                        } else {
                                            showingSessions = false
                                            Task { await open(id) }
                                        }
                                    } label: {
                                        HStack {
                                            Text(session["name"] as? String ?? "对话")
                                            Spacer()
                                            if id == sessionID { Image(systemName: "checkmark") }
                                        }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(showingArchived ? "恢复" : "归档", systemImage: showingArchived ? "arrow.uturn.backward" : "archivebox") {
                                            Task { await changeArchive(id, archived: !showingArchived) }
                                        }
                                        .tint(showingArchived ? .teal : .orange)
                                        if !showingArchived {
                                            Button("重命名", systemImage: "pencil") {
                                                sessionName = session["name"] as? String ?? ""
                                                renamingSessionID = id
                                            }.tint(.blue)
                                        }
                                    }
                                    .contextMenu {
                                        Button(showingArchived ? "恢复会话" : "归档会话") {
                                            Task { await changeArchive(id, archived: !showingArchived) }
                                        }
                                        if !showingArchived {
                                            Button("重命名") {
                                                sessionName = session["name"] as? String ?? ""
                                                renamingSessionID = id
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if !sessions.contains(where: { ($0["isArchived"] as? Bool == true) == showingArchived }) {
                    ContentUnavailableView(showingArchived ? "暂无归档会话" : "暂无会话", systemImage: "tray")
                }
            }
            .navigationTitle("会话管理")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("会话状态", selection: $showingArchived) {
                        Text("进行中").tag(false)
                        Text("已归档").tag(true)
                    }.pickerStyle(.segmented)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { showingSessions = false } }
            }
            .refreshable { await load() }
        }
    }

    private func newConversation() {
        composerFocused = false
        sessionID = nil
        messages = []
        error = nil
    }

    private func selectAgent(_ id: Int) {
        guard selectedAgentID != id else { return }
        selectedAgentID = id
        newConversation()
    }

    private func loadSessions() async throws {
        sessions = try stringRecords(await store.call("/api/agentfree/sessions?includeArchived=true"))
    }

    private func load() async {
        do {
            agents = try Record.list(await store.call("/api/agentfree/agents"))
            if !agents.contains(where: { $0.id == selectedAgentID }) { selectedAgentID = agents.first?.id; newConversation() }
            try await loadSessions()
            if let sessionID, sessions.contains(where: { $0["id"] as? String == sessionID && $0["isArchived"] as? Bool != true }) {
                await open(sessionID)
            } else if sessionID != nil { newConversation() }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func open(_ id: String) async {
        guard let session = sessions.first(where: { $0["id"] as? String == id }),
              session["isArchived"] as? Bool != true,
              let agentID = session["agentId"] as? Int,
              agents.contains(where: { $0.id == agentID }) else { return }
        do {
            composerFocused = false
            messages = try stringRecords(await store.call("/api/agentfree/sessions/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)/messages?take=100"))
            selectedAgentID = agentID
            sessionID = id
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func changeArchive(_ id: String, archived: Bool, openAfterRestore: Bool = false) async {
        do {
            _ = try await store.call("/api/agentfree/sessions/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)", method: "PUT", body: ["isArchived": archived])
            if archived && sessionID == id { newConversation() }
            try await loadSessions()
            if openAfterRestore { showingSessions = false; await open(id) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func renameSession() async {
        guard let id = renamingSessionID else { return }
        let name = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "请输入会话名称。"; return }
        do {
            _ = try await store.call("/api/agentfree/sessions/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)", method: "PUT", body: ["name": name])
            try await loadSessions()
            renamingSessionID = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func send() async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, let agent = selectedAgent else { return }
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
            try await loadSessions()
            await open(sessionID)
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

private extension Dictionary where Key == String, Value == Any {
    var sessionIdentifier: String { self["id"] as? String ?? "" }
}
