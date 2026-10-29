import AgentIdentityLocalization
import SwiftUI

@main
struct HappyLifeWatchApp: App {
    @StateObject private var store: WatchStore
    @StateObject private var language: AgentIdentityLanguageStore
    init() {
        let store = WatchStore()
        _store = StateObject(wrappedValue: store)
        _language = StateObject(wrappedValue: store.languagePreferences)
    }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchHomeView().environmentObject(store).environmentObject(language).environment(\.locale, language.locale)
                .task { await store.start(); await language.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && store.ready && store.token != nil && store.pairing == nil { Task { await store.refresh() } }
                }
        }
    }
}

struct WatchHomeView: View {
    @EnvironmentObject private var store: WatchStore
    @EnvironmentObject private var language: AgentIdentityLanguageStore

    var body: some View {
        NavigationStack {
            List {
                if !store.ready {
                    Button(String(localized: "读取设备凭据", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.start() } }
                } else if store.token == nil {
                    WatchPairingView()
                } else {
                    Section(String(localized: "我的积分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        if let score = store.score {
                            ForEach(score.children) { child in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(child.name).font(.headline)
                                    Text(String(localized: "\(child.points.formatted()) 分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                        .font(.title2.bold()).foregroundStyle(.green)
                                        .minimumScaleFactor(0.5).lineLimit(1)
                                        .frame(maxWidth: .infinity, minHeight: 100)
                                        .background { Circle().stroke(.green, lineWidth: 5) }
                                    Text(String(localized: "现金 \(child.cash.formatted()) · 物品 \(child.items)", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Text(score.familyGroupName).font(.footnote)
                        } else { Text(String(localized: "请刷新获取积分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                    }
                    NavigationLink(String(localized: "申请奖励", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: RulesView())
                    NavigationLink(String(localized: "申请记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: RequestsView())
                    NavigationLink(String(localized: "爸爸妈妈的闪光时刻", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: WarmMomentView())
                    NavigationLink(String(localized: "亲子互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: WatchConnectionsView())
                    NavigationLink(String(localized: "活动照片", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: WatchSocialSpacesView())
                    NavigationLink(String(localized: "今日鼓励", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: GrowthView())
                    NavigationLink(String(localized: "我的好友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: FriendsView())
                    if store.settings?.friendLeaderboardEnabled == true {
                        NavigationLink(String(localized: "好友积分榜", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: FriendsView(leaderboard: true))
                    }
                    Section(language.text("settings.application")) {
                        NavigationLink(language.text("language.settings"), destination: WatchLanguageSettingsView())
                        NavigationLink(String(localized: "表盘设置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: FaceSettingsView())
                    }
                    NavigationLink(String(localized: "更换绑定孩子", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: WatchPairingView())
                    NavigationLink(String(localized: "设备解绑", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: UnbindView())
                    Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.refresh() } }
                }
                if store.busy { ProgressView(String(localized: "处理中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            }
            .disabled(store.busy)
            .navigationTitle("Linko Moment")
            .containerBackground(WatchTheme.colors(store.face).gradient, for: .navigation)
            .alert(String(localized: "提示", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(get: { store.message != nil }, set: {
                if !$0 { store.message = nil }
            })) { Button(String(localized: "知道了", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { store.message = nil } } message: { Text(store.message ?? "") }
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
                Text(String(localized: "已完成绑定", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.headline)
                Button(String(localized: "返回", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { dismiss() }
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
                .accessibilityLabel(String(localized: "家长扫码绑定二维码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                Text(String(challenge.code.prefix(4)) + " " + String(challenge.code.suffix(4)))
                    .font(.system(.title3, design: .monospaced).bold())
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(String(localized: "设备码 · 10 分钟内有效", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption2)
            }
            if !completed { Text(store.pairingMessage).font(.footnote) }
            if (store.pairing == nil && !completed) || store.pairingExpired {
                Button(store.pairingExpired ? String(localized: "刷新设备码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "获取设备码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
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
            if store.rules.isEmpty { Text(String(localized: "暂无可申请规则，请家长添加奖励规则。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            ForEach(store.rules) { rule in
                NavigationLink(destination: RequestEditor(rule: rule)) {
                    VStack(alignment: .leading) {
                        Text(rule.name)
                        Text(String(localized: "+\(rule.points.formatted()) 分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.orange)
                    }
                }
            }
        }.navigationTitle(String(localized: "申请奖励", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
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
            Text(String(localized: "+\(rule.points.formatted()) 分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.orange)
            if !rule.description.isEmpty { Text(rule.description).font(.footnote) }
            TextField(String(localized: "备注（选填）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $note)
            Button(String(localized: "提交给家长", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                Task {
                    await store.submit(rule: rule, note: String(note.prefix(500)))
                    dismiss()
                }
            }
        }.disabled(store.busy).navigationTitle(String(localized: "确认申请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
    }
}

struct RequestsView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            if store.requests.isEmpty { Text(String(localized: "暂无申请记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            ForEach(store.requests) { request in
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title)
                    Text(request.statusText).font(.footnote).foregroundStyle(.orange)
                }
            }
            Button(String(localized: "刷新记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.refresh() } }.disabled(store.busy)
        }.navigationTitle(String(localized: "申请记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
    }
}

struct UnbindView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    var body: some View {
        List {
            Text(String(localized: "请家长为当前设备生成一次性解绑认证码。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            TextField(String(localized: "解绑认证码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $code)
            Button(String(localized: "验证并解绑", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) {
                Task {
                    await store.unbind(code: code)
                    if store.token == nil { dismiss() }
                }
            }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.disabled(store.busy).navigationTitle(String(localized: "设备解绑", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
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
            Section(String(localized: "想和家长说", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                Picker(String(localized: "方式", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $kind) {
                    Text(String(localized: "十分钟陪伴", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("special_time")
                    Text(String(localized: "先听我说", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("listen")
                    Text(String(localized: "吵架后重连", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("reconnect")
                    Text(String(localized: "家庭小会议", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("meeting")
                }
                if kind == "listen" {
                    Picker(String(localized: "我希望", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $intent) {
                        Text(String(localized: "只想说说", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("share")
                        Text(String(localized: "想要安慰", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("comfort")
                        Text(String(localized: "一起想办法", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("ideas")
                    }
                }
                TextField(kind == "special_time" ? String(localized: "想一起做什么", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "想聊什么", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $title)
                    .onChange(of: title) { _, _ in requestID = UUID() }
                Button(String(localized: "告诉家长", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    Task {
                        if await store.createConnection(kind: kind, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                        intent: kind == "listen" ? intent : "", requestID: requestID) {
                            title = ""; requestID = UUID()
                        }
                    }
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            }
            Section(String(localized: "我们的互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                if store.connections?.threads.isEmpty != false { Text(String(localized: "还没有记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
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
                Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.loadSection("connections") } }
            }
            Text(String(localized: "这里不计积分，也不评分。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.footnote).foregroundStyle(.secondary)
        }.disabled(store.busy).navigationTitle(String(localized: "亲子互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
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
                    Text(["share": String(localized: "只想说说", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), "comfort": String(localized: "想要安慰", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), "ideas": String(localized: "一起想办法", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))][thread.intent] ?? String(localized: "先听我说", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                }
                if let time = thread.scheduledAt { Text(String(localized: "约定时间：\(watchLocalTime(time))（当地时间）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.footnote) }
                if !thread.trialPlan.isEmpty { Text(String(localized: "本周试行：\(thread.trialPlan)", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                ForEach(store.connections?.entries.filter { $0.connectionId == id } ?? []) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.authorRole == "child" ? String(localized: "我说", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "家长说", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption2).foregroundStyle(.secondary)
                        Text(entry.content)
                    }
                }
                if thread.status != "completed" && thread.status != "cancelled" {
                    Picker(String(localized: "记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $type) {
                        Text(String(localized: "想说的话", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("message")
                        if thread.kind == "reconnect" { Text(String(localized: "我的感受", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("feeling"); Text(String(localized: "我的期待", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("hope") }
                        if thread.kind == "meeting" { Text(String(localized: "我的提议", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("proposal") }
                        if thread.status == "trial" || thread.kind == "special_time" { Text(String(localized: "复盘", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("reflection") }
                    }
                    TextField(String(localized: "说说你的想法", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $content).onChange(of: content) { _, _ in requestID = UUID() }
                    Button(String(localized: "发送", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
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
                        Button(String(localized: "完成互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.completeConnection(id: id) } }
                    }
                }
                Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.loadSection("connections") } }
            } else { Text(String(localized: "正在读取记录…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        }.disabled(store.busy).navigationTitle(String(localized: "我们的话", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .task { await store.loadSection("connections") }
    }
}

struct WatchLanguageSettingsView: View {
    @EnvironmentObject private var language: AgentIdentityLanguageStore
    var body: some View {
        List {
            ForEach(["system", "zh-Hans", "en"], id: \.self) { value in
                Button { Task { await language.select(value) } } label: {
                    HStack {
                        Text(language.text(value == "system" ? "language.system" : value == "zh-Hans" ? "language.chinese.native" : "language.english.native"))
                        Spacer()
                        if language.global == value { Image(systemName: "checkmark") }
                    }
                }.disabled(language.busy)
            }
            Text(String(localized: "此设备的语言设置不影响家长或孩子的用户中心账号。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.footnote)
            if let code = language.errorCode { Text(language.text(code)) }
        }.navigationTitle(language.text("language.settings"))
    }
}
