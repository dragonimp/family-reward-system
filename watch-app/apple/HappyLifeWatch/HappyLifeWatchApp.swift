import SwiftUI

@main
struct HappyLifeWatchApp: App {
    @StateObject private var store = WatchStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchHomeView().environmentObject(store)
                .task { await store.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && store.ready && store.token != nil && store.pairing == nil { Task { await store.refresh() } }
                }
        }
    }
}

struct WatchHomeView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        NavigationStack {
            List {
                if !store.ready {
                    Button("读取设备凭据") { Task { await store.start() } }
                } else if store.token == nil {
                    WatchPairingView()
                } else {
                    Section("我的积分") {
                        if let score = store.score {
                            ForEach(score.children) { child in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(child.name).font(.headline)
                                    Text("\(child.points.formatted()) 分")
                                        .font(.title2.bold()).foregroundStyle(.green)
                                        .minimumScaleFactor(0.5).lineLimit(1)
                                        .frame(maxWidth: .infinity, minHeight: 100)
                                        .background { Circle().stroke(.green, lineWidth: 5) }
                                    Text("现金 \(child.cash.formatted()) · 物品 \(child.items)")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Text(score.familyGroupName).font(.footnote)
                        } else { Text("请刷新获取积分") }
                    }
                    NavigationLink("申请奖励", destination: RulesView())
                    NavigationLink("申请记录", destination: RequestsView())
                    NavigationLink("爸爸妈妈的闪光时刻", destination: WarmMomentView())
                    NavigationLink("亲子互动", destination: WatchConnectionsView())
                    NavigationLink("今日鼓励", destination: GrowthView())
                    NavigationLink("我的好友", destination: FriendsView())
                    if store.settings?.friendLeaderboardEnabled == true {
                        NavigationLink("好友积分榜", destination: FriendsView(leaderboard: true))
                    }
                    NavigationLink("表盘设置", destination: FaceSettingsView())
                    NavigationLink("更换绑定孩子", destination: WatchPairingView())
                    NavigationLink("设备解绑", destination: UnbindView())
                    Button("刷新") { Task { await store.refresh() } }
                }
                if store.busy { ProgressView("处理中") }
            }
            .disabled(store.busy)
            .navigationTitle("Linko Family")
            .containerBackground(WatchTheme.colors(store.face).gradient, for: .navigation)
            .alert("提示", isPresented: Binding(get: { store.message != nil }, set: {
                if !$0 { store.message = nil }
            })) { Button("知道了") { store.message = nil } } message: { Text(store.message ?? "") }
        }
    }
}

struct WatchPairingView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var completed = false
    var body: some View {
        Section {
            if completed {
                Text("已完成绑定").font(.headline)
                Button("返回") { dismiss() }
            }
            if let challenge = store.pairing, !store.pairingExpired {
                Canvas { context, size in
                    let rows = challenge.qrModules
                    let unit = min(size.width, size.height) / CGFloat(rows.count)
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    for (y, row) in rows.enumerated() {
                        for (x, dark) in row.enumerated() where dark {
                            context.fill(Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit,
                                                     width: unit, height: unit)), with: .color(.black))
                        }
                    }
                }
                .frame(width: 106, height: 106)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("家长扫码绑定二维码")
                Text(String(challenge.code.prefix(4)) + " " + String(challenge.code.suffix(4)))
                    .font(.system(.title3, design: .monospaced).bold())
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text("设备码 · 10 分钟内有效").font(.caption2)
            }
            if !completed { Text(store.pairingMessage).font(.footnote) }
            if (store.pairing == nil && !completed) || store.pairingExpired {
                Button(store.pairingExpired ? "刷新设备码" : "获取设备码") {
                    Task { await store.beginPairing() }
                }
            }
        }
        .onChange(of: store.token) { _, token in
            if token != nil && store.pairing == nil { completed = true }
        }
        .task(id: "\(phase == .active):\(store.pairing?.code ?? "")") {
            guard phase == .active else { return }
            if store.pairing == nil && store.token == nil { await store.beginPairing() }
            while !Task.isCancelled && store.pairing != nil {
                await store.pollPairing()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
}

struct RulesView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            if store.rules.isEmpty { Text("暂无可申请规则，请家长添加奖励规则。") }
            ForEach(store.rules) { rule in
                NavigationLink(destination: RequestEditor(rule: rule)) {
                    VStack(alignment: .leading) {
                        Text(rule.name)
                        Text("+\(rule.points.formatted()) 分").foregroundStyle(.orange)
                    }
                }
            }
        }.navigationTitle("申请奖励")
    }
}

struct RequestEditor: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    let rule: RewardRule
    @State private var note = ""
    var body: some View {
        List {
            Text(rule.name).font(.headline)
            Text("+\(rule.points.formatted()) 分").foregroundStyle(.orange)
            if !rule.description.isEmpty { Text(rule.description).font(.footnote) }
            TextField("备注（选填）", text: $note)
            Button("提交给家长") {
                Task {
                    await store.submit(rule: rule, note: String(note.prefix(500)))
                    dismiss()
                }
            }
        }.disabled(store.busy).navigationTitle("确认申请")
    }
}

struct RequestsView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            if store.requests.isEmpty { Text("暂无申请记录") }
            ForEach(store.requests) { request in
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title)
                    Text(request.statusText).font(.footnote).foregroundStyle(.orange)
                }
            }
            Button("刷新记录") { Task { await store.refresh() } }.disabled(store.busy)
        }.navigationTitle("申请记录")
    }
}

struct UnbindView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    var body: some View {
        List {
            Text("请家长为当前设备生成一次性解绑认证码。")
            TextField("解绑认证码", text: $code)
            Button("验证并解绑", role: .destructive) {
                Task {
                    await store.unbind(code: code)
                    if store.token == nil { dismiss() }
                }
            }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.disabled(store.busy).navigationTitle("设备解绑")
    }
}

struct WatchConnectionsView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var kind = "special_time"
    @State private var intent = "share"
    @State private var title = ""
    @State private var requestID = UUID()
    var body: some View {
        List {
            Section("想和家长说") {
                Picker("方式", selection: $kind) {
                    Text("十分钟陪伴").tag("special_time")
                    Text("先听我说").tag("listen")
                    Text("吵架后重连").tag("reconnect")
                    Text("家庭小会议").tag("meeting")
                }
                if kind == "listen" {
                    Picker("我希望", selection: $intent) {
                        Text("只想说说").tag("share")
                        Text("想要安慰").tag("comfort")
                        Text("一起想办法").tag("ideas")
                    }
                }
                TextField(kind == "special_time" ? "想一起做什么" : "想聊什么", text: $title)
                    .onChange(of: title) { _, _ in requestID = UUID() }
                Button("告诉家长") {
                    Task {
                        if await store.createConnection(kind: kind, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                        intent: kind == "listen" ? intent : "", requestID: requestID) {
                            title = ""; requestID = UUID()
                        }
                    }
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            }
            Section("我们的互动") {
                if store.connections?.threads.isEmpty != false { Text("还没有记录") }
                ForEach(store.connections?.threads ?? []) { thread in
                    NavigationLink {
                        WatchConnectionDetail(id: thread.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(thread.title)
                            Text(thread.status).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("刷新") { Task { await store.loadSection("connections") } }
            }
            Text("这里不计积分，也不评分。").font(.footnote).foregroundStyle(.secondary)
        }.disabled(store.busy).navigationTitle("亲子互动")
            .task { await store.loadSection("connections") }
    }
}

struct WatchConnectionDetail: View {
    @EnvironmentObject private var store: WatchStore
    let id: Int64
    @State private var type = "message"
    @State private var content = ""
    @State private var requestID = UUID()
    private var thread: WatchConnection? { store.connections?.threads.first { $0.id == id } }
    var body: some View {
        List {
            if let thread {
                Text(thread.title).font(.headline)
                if thread.kind == "listen" {
                    Text(["share": "只想说说", "comfort": "想要安慰", "ideas": "一起想办法"][thread.intent] ?? "先听我说")
                }
                if let time = thread.scheduledAt { Text("约定时间：\(time)").font(.footnote) }
                if !thread.trialPlan.isEmpty { Text("本周试行：\(thread.trialPlan)") }
                ForEach(store.connections?.entries.filter { $0.connectionId == id } ?? []) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.authorRole == "child" ? "我说" : "家长说").font(.caption2).foregroundStyle(.secondary)
                        Text(entry.content)
                    }
                }
                if thread.status != "completed" && thread.status != "cancelled" {
                    Picker("记录", selection: $type) {
                        Text("想说的话").tag("message")
                        if thread.kind == "reconnect" { Text("我的感受").tag("feeling"); Text("我的期待").tag("hope") }
                        if thread.kind == "meeting" { Text("我的提议").tag("proposal") }
                        if thread.status == "trial" || thread.kind == "special_time" { Text("复盘").tag("reflection") }
                    }
                    TextField("说说你的想法", text: $content).onChange(of: content) { _, _ in requestID = UUID() }
                    Button("发送") {
                        Task {
                            if await store.addConnectionEntry(id: id, type: type,
                                content: content.trimmingCharacters(in: .whitespacesAndNewlines), requestID: requestID) {
                                content = ""; requestID = UUID()
                            }
                        }
                    }.disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    if thread.kind == "special_time" && thread.status == "scheduled" ||
                       thread.kind == "listen" && thread.status == "open" ||
                       thread.kind == "reconnect" && thread.status == "open" {
                        Button("完成互动") { Task { await store.completeConnection(id: id) } }
                    }
                }
                Button("刷新") { Task { await store.loadSection("connections") } }
            } else { Text("正在读取记录…") }
        }.disabled(store.busy).navigationTitle("我们的话")
            .task { await store.loadSection("connections") }
    }
}
