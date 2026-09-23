import SwiftUI
import AgentIdentity
import Charts

@main struct LinkoFamilyApp: App {
    @StateObject private var store = FamilyStore()
    var body: some Scene { WindowGroup { FamilyRoot(store: store, identity: store.identity).tint(.teal) } }
}

struct FamilyRoot: View {
    @ObservedObject var store: FamilyStore
    @ObservedObject var identity: AgentIdentitySession
    var body: some View {
        Group {
            if !identity.isAuthenticated { login }
            else if store.ready { main }
            else {
                NavigationStack {
                    VStack(spacing: 24) {
                        Image(systemName: "person.2.circle.fill").font(.system(size: 64)).foregroundStyle(.teal)
                        Text("欢迎使用 Linko Family").font(.title2.bold())
                        if store.loading { ProgressView("正在读取家庭身份…") }
                        else if store.profile?.flag("needsRole") == true {
                            Text("选择家长身份，管理家庭与孩子的成长记录。")
                            Button("我是家长") { Task { await store.selectParent() } }.buttonStyle(.borderedProminent)
                        } else if store.profile?.text("role") == "child" {
                            Text("此账号是孩子身份，请使用家长账号登录。")
                        } else { Button("重新加载") { Task { await store.load() } } }
                        Button("退出登录") { store.logout() }
                    }.padding().navigationTitle("Linko Family")
                }
            }
        }
        .task(id: identity.isAuthenticated) { if identity.isAuthenticated { await store.load() } }
        .alert("操作提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了", role: .cancel) { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var login: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Image(systemName: "house.and.flag.fill").font(.system(size: 72)).foregroundStyle(.teal)
                Text("每一份成长\n都值得被看见").font(.largeTitle.bold())
                Text("家庭、积分与成长记录，随手相伴。").foregroundStyle(.secondary)
                Spacer()
                if identity.isBusy {
                    HStack { ProgressView(); Text(identity.status).font(.subheadline); Spacer(); Button("取消") { identity.cancelLogin() }.buttonStyle(.bordered) }
                }
                if let code = identity.displayCode { Text("本次登录验证码：\(code)").font(.title3.monospacedDigit()).textSelection(.enabled) }
                Button { signIn(false) } label: { HStack { Spacer(); if identity.isBusy { ProgressView() }; Text("用户中心登录").bold(); Spacer() }.padding(.vertical, 8) }.buttonStyle(.borderedProminent).disabled(identity.isBusy)
                Button("注册用户中心账号") { signIn(true) }.frame(maxWidth: .infinity).disabled(identity.isBusy)
                Text("登录和注册在系统认证窗口中完成。登录后自动返回 App。").font(.footnote).foregroundStyle(.secondary)
            }.padding(28).navigationTitle("Linko Family")
        }
    }
    private func signIn(_ register: Bool) {
        Task { do { try await identity.login(register: register) } catch {
            if !(error is CancellationError) && (error as NSError).code != NSURLErrorCancelled && ((error as NSError).domain != "com.apple.AuthenticationServices.WebAuthenticationSession" || (error as NSError).code != 1) { store.error = error.localizedDescription }
        } }
    }
    private var main: some View {
        TabView {
            FamilyHome(store: store).tabItem { Label("家庭", systemImage: "house.fill") }
            ApprovalList(store: store).tabItem { Label("审批", systemImage: "checkmark.bubble.fill") }.badge(store.requests.filter { $0.text("status") == "pending" }.count)
            LedgerView(store: store).tabItem { Label("记录", systemImage: "list.bullet.rectangle") }
            GrowthView(store: store).tabItem { Label("成长", systemImage: "chart.xyaxis.line") }
            AccountView(store: store).tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}

struct FamilyHome: View {
    @ObservedObject var store: FamilyStore
    @State private var editor: EditorSpec?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.groups.isEmpty { Text("创建或加入一个家庭，开始记录成长。").foregroundStyle(.secondary) }
                    else {
                        Picker("当前家庭", selection: Binding(get: { store.groupID }, set: { value in Task { await store.chooseGroup(value) } })) {
                            ForEach(store.groups) { Text($0.text("name")).tag($0.id) }
                        }.disabled(store.loading)
                    }
                    HStack {
                        Button("创建家庭", systemImage: "plus.circle") { editor = EditorSpec(title: "创建家庭", path: "/api/family-groups", fields: [.init(key: "name", title: "家庭名称"), .init(key: "description", title: "家庭简介", required: false)]) }
                        Spacer()
                        Button("加入家庭", systemImage: "person.badge.plus") { editor = EditorSpec(title: "加入家庭", path: "/api/family-groups/join", fields: [.init(key: "inviteCode", title: "邀请码")]) }
                    }.buttonStyle(.borderless)
                } header: { Text("一起成长") }
                Section {
                    ForEach(store.children) { child in
                        NavigationLink { ChildDetail(store: store, child: child) } label: { ChildRow(child: child) }
                    }
                    if store.children.isEmpty && !store.loading { Text("还没有孩子").foregroundStyle(.secondary) }
                    Button("添加孩子", systemImage: "plus") {
                        editor = EditorSpec(title: "添加孩子", path: "/api/children", fields: [.init(key: "name", title: "孩子姓名"), .init(key: "note", title: "备注", required: false)], fixed: store.groupID == 0 ? [:] : ["familyGroupId": store.groupID])
                    }
                } header: { Text("孩子 · \(store.children.count)") }
                Section {
                    NavigationLink { RulesView(store: store) } label: { Label("奖励与行为规则", systemImage: "star.square.fill") }
                    NavigationLink { MembersView(store: store) } label: { Label("家庭成员", systemImage: "person.3.fill") }
                    if store.groupID != 0 { NavigationLink { RemoteRecords(store: store, title: "家庭邀请", path: "/api/family-groups/\(store.groupID)/invite", mode: .invite) } label: { Label("邀请家人", systemImage: "qrcode") } }
                }
                if store.loading { ProgressView("正在更新…") }
            }.navigationTitle(store.selectedFamily).refreshable { await store.load() }
                .sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
        }
    }
}
struct ChildRow: View {
    let child: Record
    var body: some View {
        HStack(spacing: 14) {
            Text(String(child.text("name").prefix(1))).font(.title2.bold()).frame(width: 48, height: 48).background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 5) { Text(child.text("name")).font(.headline); Text("\(child.amount("score")) 积分 · ¥\(child.amount("cash"))").font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
        }.padding(.vertical, 5)
    }
}
struct ChildDetail: View {
    @ObservedObject var store: FamilyStore
    let child: Record
    @State private var editor: EditorSpec?
    @State private var rewarding = false
    var current: Record { store.children.first(where: { $0.id == child.id }) ?? child }
    var body: some View {
        List {
            Section { ChildRow(child: current); Button("记录奖励 / 扣分", systemImage: "plus.circle.fill") { rewarding = true } }
            Section("孩子资料") {
                LabeledContent("积分", value: current.amount("score")); LabeledContent("零用钱", value: "¥" + current.amount("cash")); LabeledContent("物品", value: current.amount("items"))
                Button("修改姓名与备注") { editor = EditorSpec(title: "修改孩子资料", path: "/api/children/\(child.id)", method: "PUT", fields: [.init(key: "name", title: "姓名", initial: current.text("name")), .init(key: "note", title: "备注", initial: current.text("note"), required: false)]) }
            }
            Section("手表与成长") {
                NavigationLink("手表设备") { RemoteRecords(store: store, title: "手表设备", path: "/api/children/\(child.id)/devices?\(store.scope)", mode: .devices, childID: child.id) }
                Button("连接手表") { editor = EditorSpec(title: "连接孩子手表", path: "/api/children/\(child.id)/pair-device", fields: [.init(key: "code", title: "手表上显示的配对码")], scansWatchCode: true) }
                Button("生成孩子授权码") { editor = EditorSpec(title: "生成孩子授权码", path: "/api/children/\(child.id)/auth-code", fields: [], fixed: ["familyGroupId": store.groupID, "expiresInMinutes": 10], showsReceipt: true) }
                NavigationLink("温暖瞬间") { RemoteRecords(store: store, title: "温暖瞬间", path: "/api/warm-moments?childId=\(child.id)&limit=30", mode: .moments) }
                NavigationLink("成长周报") { RemoteRecords(store: store, title: "成长周报", path: "/api/growth-reports?childId=\(child.id)&audience=parent&period=weekly&ai=false", mode: .reports) }
                NavigationLink("好友") { RemoteRecords(store: store, title: "孩子的好友", path: "/api/children/\(child.id)/friends?\(store.scope)", mode: .friends) }
            }
        }.navigationTitle(current.text("name"))
            .sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
            .sheet(isPresented: $rewarding) { RewardEditor(store: store, child: current) }
    }
}

struct ApprovalList: View {
    @ObservedObject var store: FamilyStore
    @State private var editor: EditorSpec?
    var body: some View {
        NavigationStack {
            List {
                if store.requests.isEmpty { ContentUnavailableView("暂无申请", systemImage: "checkmark.bubble", description: Text("孩子从手表提交的奖励申请会显示在这里。")) }
                ForEach(store.requests) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(row.text("childName")).font(.headline); Spacer(); Text(row.text("statusText")).font(.caption).foregroundStyle(.secondary) }
                        Text(row.text("title")); Text("\(row.amount("points")) 积分 · \(row.text("category"))").foregroundStyle(.teal)
                        if !row.text("note").isEmpty { Text(row.text("note")).font(.subheadline) }
                        Text(beijingDate(row.text("requestedAt"))).font(.caption).foregroundStyle(.secondary)
                        if row.text("status") == "pending" {
                            Button("批准申请") { editor = EditorSpec(title: "批准 \(row.text("childName")) 的申请", path: "/api/reward-requests/\(row.id)/approve", fields: [.init(key: "reviewNote", title: "给孩子的话", required: false)], fixed: ["familyGroupId": row.int("familyGroupId")]) }.buttonStyle(.bordered)
                        }
                    }.padding(.vertical, 6)
                }
            }.navigationTitle("奖励审批").refreshable { await store.load() }.sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
        }
    }
}
struct LedgerView: View {
    @ObservedObject var store: FamilyStore
    @State private var filter = ""
    @State private var more = false
    var body: some View {
        NavigationStack {
            List {
                Section { Text("我的孩子 · 共 \(store.ledgerTotal) 条").foregroundStyle(.secondary) }
                ForEach(store.transactions.filter { filter.isEmpty || ($0.text("childName") + $0.text("description") + $0.text("category")).localizedCaseInsensitiveContains(filter) }) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(row.text("childName")).font(.headline); Spacer(); Text(row.amount("amount") + (row.text("type") == "cash" ? " 元" : row.text("type") == "item" ? " 件" : " 分")).foregroundStyle(row.number("amount") >= 0 ? .teal : .orange).font(.headline.monospacedDigit()) }
                        Text(row.text("description")); Text("\(row.text("date")) · \(row.text("category"))").font(.caption).foregroundStyle(.secondary)
                        if !row.text("notes").isEmpty { Text(row.text("notes")).font(.caption) }
                    }.padding(.vertical, 4)
                }
                if store.transactions.isEmpty { ContentUnavailableView("还没有记录", systemImage: "list.bullet.rectangle", description: Text("从孩子详情中记录奖励与扣分。")) }
                if store.transactions.count < store.ledgerTotal {
                    Button(more ? "正在加载…" : "加载更多") { Task { more = true; defer { more = false }; do { try await store.loadLedger(page: store.ledgerPage + 1) } catch { store.error = error.localizedDescription } } }.disabled(more)
                }
            }.navigationTitle("积分与奖励记录").searchable(text: $filter, prompt: "搜索已加载的孩子、内容、类别").refreshable { await store.load() }
        }
    }
}
struct GrowthView: View {
    @ObservedObject var store: FamilyStore
    var body: some View {
        NavigationStack {
            List {
                Section { Text(store.selectedFamily).font(.headline); Text("本周成长 · 北京时间").font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(store.growth.enumerated()), id: \.offset) { _, row in
                    Section(row.text("childName")) {
                        HStack { metric("本周记录", row.amount("currentWeekRecords")); Spacer(); metric("活跃天数", row.amount("activeDays")); Spacer(); metric("连续天数", row.amount("streakDays")) }
                        let trend = (row.fields["trend"] as? [[String: Any]] ?? []).map { Record(fields: $0) }
                        Chart(Array(trend.enumerated()), id: \.offset) { _, day in
                            BarMark(x: .value("日期", String(day.text("date").suffix(5))), y: .value("记录", day.number("records"))).foregroundStyle(.teal.gradient)
                        }.frame(height: 150).accessibilityLabel("每日成长记录数量")
                        Text("比上周\(row.number("change") >= 0 ? "增加" : "减少") \(abs(row.int("change"))) 条记录").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if store.growth.isEmpty { ContentUnavailableView("暂无成长统计", systemImage: "chart.bar", description: Text("记录孩子的日常进步，积累成长轨迹。")) }
            }.navigationTitle("成长足迹").refreshable { await store.load() }
        }
    }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(value).font(.title2.bold()).foregroundStyle(.teal); Text(title).font(.caption).foregroundStyle(.secondary) } }
}
struct RulesView: View {
    @ObservedObject var store: FamilyStore
    @State private var editor: EditorSpec?
    @State private var search = ""
    var body: some View {
        List {
            ForEach(store.rules.filter { search.isEmpty || ($0.text("name") + $0.text("category")).localizedCaseInsensitiveContains(search) }) { rule in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(rule.text("name")).font(.headline); Spacer(); Text("\(rule.amount("points")) 分").foregroundStyle(rule.number("points") >= 0 ? .teal : .orange) }
                    Text(rule.text("description")).font(.subheadline)
                    HStack { Text(rule.text("category")); Text(rule.flag("isPublic") ? "公共规则" : "我的规则") }.font(.caption).foregroundStyle(.secondary)
                    if !rule.flag("isPublic") { Button("编辑") { edit(rule) } }
                }.padding(.vertical, 5)
            }
        }.navigationTitle("奖励与行为规则").searchable(text: $search)
            .toolbar { Button("添加", systemImage: "plus") { edit(nil) } }.sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
    }
    private func edit(_ row: Record?) {
        editor = EditorSpec(title: row == nil ? "添加规则" : "编辑规则", path: row.map { "/api/rules/\($0.id)" } ?? "/api/rules", method: row == nil ? "POST" : "PUT", fields: [.init(key: "name", title: "规则名称", initial: row?.text("name") ?? ""), .init(key: "points", title: "积分（负数表示扣分）", initial: row?.amount("points") ?? "", numeric: true), .init(key: "category", title: "类别", initial: row?.text("category") ?? "日常"), .init(key: "description", title: "说明", initial: row?.text("description") ?? "", required: false)], fixed: ["cash_cny": row?.number("cash_cny") ?? 0])
    }
}
struct MembersView: View {
    @ObservedObject var store: FamilyStore
    @State private var editor: EditorSpec?
    var body: some View {
        List {
            ForEach(store.members) { row in
                VStack(alignment: .leading) { Text(row.text("displayName")).font(.headline); Text(row.text("note")).foregroundStyle(.secondary) }
            }
            Button("添加家庭成员", systemImage: "person.badge.plus") { editor = EditorSpec(title: "添加家庭成员", path: "/api/family-members", fields: [.init(key: "displayName", title: "称呼"), .init(key: "note", title: "备注", required: false)], fixed: ["role":"other"]) }
        }.navigationTitle("家庭成员").sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
    }
}
struct AccountView: View {
    @ObservedObject var store: FamilyStore
    @State private var logout = false
    var body: some View {
        NavigationStack {
            List {
                Section { Label(store.profile?.text("username") ?? "家长", systemImage: "person.crop.circle.fill"); LabeledContent("身份", value: "家长"); LabeledContent("应用", value: "Linko Family") }
                Section {
                    NavigationLink("订阅权益") { RemoteRecords(store: store, title: "订阅权益", path: "/api/subscription", mode: .subscription) }
                    LabeledContent("版本", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                    Text("家庭数据与网页版同步。登录由用户中心提供，凭据保存在本机钥匙串。").font(.footnote).foregroundStyle(.secondary)
                }
                Button("退出当前账号", role: .destructive) { logout = true }
            }.navigationTitle("我的").confirmationDialog("退出 Linko Family？", isPresented: $logout, titleVisibility: .visible) { Button("退出登录", role: .destructive) { store.logout() } } message: { Text("本机登录凭据将清除。用户中心的浏览器登录状态由用户中心管理。") }
        }
    }
}

struct NativeEditor: View {
    @ObservedObject var store: FamilyStore
    let spec: EditorSpec
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var saving = false
    @State private var error: String?
    @State private var scanning = false
    @State private var receipt: Record?
    @State private var saved = false
    var body: some View {
        NavigationStack {
            Form {
                if let receipt {
                    Section("授权码") { Text(receipt.text("code")).font(.largeTitle.monospacedDigit()).textSelection(.enabled); Text("有效期至 " + beijingDate(receipt.text("expiresAt"))).font(.caption); Text("仅向你要绑定的孩子提供此授权码。").font(.footnote) }
                } else if saved { Section { Label("已保存", systemImage: "checkmark.circle.fill").foregroundStyle(.teal) } }
                else {
                    ForEach(spec.fields) { field in
                        TextField(field.title, text: Binding(get: { values[field.key] ?? field.initial }, set: { values[field.key] = $0 }))
                            .keyboardType(field.numeric ? .numbersAndPunctuation : .default)
                    }
                    if spec.scansWatchCode {
                        Button("扫描手表二维码", systemImage: "qrcode.viewfinder") { scanning = true }.disabled(saving)
                    }
                    if spec.fields.isEmpty { Text("确认后生成临时授权码，有效期 10 分钟。") }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button(saving ? "正在提交…" : "确认") { Task { await save() } }.disabled(saving || !valid)
                }
            }.sheet(isPresented: $scanning) {
                WatchCodeScanner { code in values["code"] = code; error = nil }
            }.navigationTitle(spec.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(saved ? "完成" : "取消") { dismiss() }.disabled(saving) } }.interactiveDismissDisabled(saving)
        }
    }
    private var valid: Bool { spec.fields.allSatisfy { f in let text = (values[f.key] ?? f.initial).trimmingCharacters(in: .whitespacesAndNewlines); return (!f.required || !text.isEmpty) && (!f.numeric || Double(text)?.isFinite == true) } }
    private func save() async {
        saving = true; error = nil
        defer { saving = false }
        var body = spec.fixed
        for field in spec.fields {
            let text = (values[field.key] ?? field.initial).trimmingCharacters(in: .whitespacesAndNewlines)
            if field.numeric { body[field.key] = Double(text) } else { body[field.key] = text }
        }
        if spec.scansWatchCode {
            guard let code = WatchPairingCode.parse(values["code"] ?? "") else { error = "请输入手表上显示的 8 位设备码。"; return }
            body["code"] = code
        }
        do {
            let result = try await store.call(spec.path, method: spec.method, body: body)
            saved = true
            if spec.showsReceipt { receipt = Record(fields: result as? [String: Any] ?? [:]) }
            await store.load()
            if !spec.showsReceipt { dismiss() }
        } catch { self.error = error.localizedDescription + " 如网络中断，请先检查记录再重试。" }
    }
}
struct RewardEditor: View {
    @ObservedObject var store: FamilyStore
    let child: Record
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var description = ""
    @State private var category = "日常"
    @State private var kind = "points"
    @State private var direction = "+"
    @State private var item = ""
    @State private var date = Date()
    @State private var saving = false
    @State private var error: String?
    @State private var attempted = false
    @State private var requestBody: [String: Any]?
    @State private var idempotency = UUID().uuidString
    var body: some View {
        NavigationStack {
            Form {
                Section(child.text("name")) {
                    Picker("类型", selection: $kind) { Text("积分").tag("points"); Text("零用钱").tag("cash"); Text("物品").tag("items") }
                    Picker("方向", selection: $direction) { Text("奖励").tag("+"); Text("扣除").tag("-") }.pickerStyle(.segmented)
                    if kind == "items" { TextField("物品名称", text: $item) } else { TextField("数量（大于 0）", text: $amount).keyboardType(.decimalPad) }
                    TextField("记录内容", text: $description); TextField("类别", text: $category)
                    DatePicker("日期（北京时间）", selection: $date, displayedComponents: .date).environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
                    if kind == "points" {
                        Menu("使用现有规则") { ForEach(store.rules) { rule in Button(rule.text("name")) { amount = String(abs(rule.number("points"))); direction = rule.number("points") < 0 ? "-" : "+"; description = rule.text("name"); category = rule.text("category") } } }
                    }
                }.disabled(attempted || saving)
                if let error { Text(error).foregroundStyle(.red) }
                Button(saving ? "正在保存…" : attempted ? "核对并重试同一笔记录" : "保存记录") { Task { await save() } }.disabled(saving || !valid)
                Text("重试会使用同一个记录编号，避免重复记分。提交后请以服务端记录为准。").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("记录奖励").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(saving) } }.interactiveDismissDisabled(saving)
        }
    }
    private var valid: Bool { !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !category.isEmpty && (kind == "items" ? !item.isEmpty : (Double(amount)?.isFinite == true && (Double(amount) ?? 0) > 0)) }
    private func save() async {
        saving = true; error = nil
        defer { saving = false }
        if requestBody == nil {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.locale = Locale(identifier: "en_US_POSIX")
            requestBody = ["child_id": child.id, "type": kind, "direction": direction, "points": kind == "points" ? Double(amount) ?? 0 : 0, "cash_cny": kind == "cash" ? Double(amount) ?? 0 : 0, "items": item, "description": description, "category": category, "date": formatter.string(from: date), "idempotency_key": idempotency]
        }
        attempted = true
        do { _ = try await store.call("/api/transactions", method: "POST", body: requestBody); await store.load(); dismiss() }
        catch { self.error = error.localizedDescription + " 可重试同一笔记录，或关闭后在记录页核对。" }
    }
}

enum RemoteMode { case invite, devices, moments, reports, friends, subscription }
struct RemoteRecords: View {
    @ObservedObject var store: FamilyStore
    let title: String
    let path: String
    let mode: RemoteMode
    var childID: Int? = nil
    @State private var object: Record?
    @State private var rows: [Record] = []
    @State private var loading = true
    @State private var error: String?
    @State private var deviceToUnbind: Record?
    @State private var unbinding = false
    var body: some View {
        List {
            if loading { ProgressView("正在加载…") }
            if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load() } } }
            if let object {
                if mode == .invite {
                    Text(object.text("familyGroupName")).font(.headline)
                    Text(object.text("inviteCode")).font(.title.monospacedDigit()).textSelection(.enabled)
                    if let url = URL(string: object.text("inviteUrl")), url.scheme == "https" { ShareLink("分享家庭邀请", item: url) }
                } else if mode == .subscription {
                    LabeledContent("基础功能", value: object.flag("standardIncluded") ? "已包含" : "未开通")
                    LabeledContent("VIP 表盘", value: object.flag("vipWatchFaces") ? "已开通" : "未开通")
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 8) {
                    switch mode {
                    case .devices:
                        Text(row.text("deviceName")).font(.headline); Text(row.flag("active") ? "已连接" : "已解绑").foregroundStyle(.secondary)
                        Text("最近在线：" + beijingDate(row.text("lastSeenAt"))).font(.caption)
                        if row.flag("active") && childID != nil {
                            Button("解除绑定", role: .destructive) { deviceToUnbind = row }
                                .disabled(unbinding)
                        }
                    case .moments:
                        Text(row.text("content")); Text(row.text("parentDisplayName") + " · " + beijingDate(row.text("createdAt"))).font(.caption).foregroundStyle(.secondary)
                    case .reports:
                        Text(row.text("subjectName")).font(.headline); Text(row.text("periodStart") + " — " + row.text("periodEnd")).font(.caption)
                        Text(row.text("praise")); Text(row.text("changeSummary")); Text(row.text("nextStep")).foregroundStyle(.secondary)
                    case .friends:
                        Text(row.text("name")).font(.headline); Text(row.amount("score") + " 积分")
                    default: EmptyView()
                    }
                }.padding(.vertical, 5)
            }
            if !loading && error == nil && rows.isEmpty && mode != .invite && mode != .subscription { Text("暂无记录").foregroundStyle(.secondary) }
        }.navigationTitle(title).task { await load() }.refreshable { await load() }
            .confirmationDialog("解除这只手表与当前孩子的绑定？", isPresented: Binding(
                get: { deviceToUnbind != nil }, set: { if !$0 { deviceToUnbind = nil } }), titleVisibility: .visible) {
                Button("解除绑定", role: .destructive) {
                    guard let device = deviceToUnbind else { return }
                    deviceToUnbind = nil
                    Task { await unbind(device) }
                }
                Button("取消", role: .cancel) { deviceToUnbind = nil }
            } message: { Text("解绑后手表将退出当前孩子，需重新扫码才能使用。") }
    }
    private func unbind(_ device: Record) async {
        guard let childID else { return }
        unbinding = true; defer { unbinding = false }
        do {
            _ = try await store.call("/api/children/\(childID)/devices/\(device.id)?\(store.scope)", method: "DELETE")
            await load()
        } catch { self.error = error.localizedDescription }
    }
    private func load() async {
        loading = true; error = nil; rows = []; object = nil
        defer { loading = false }
        do {
            guard let result = try await store.call(path) as? [String: Any] else { throw APIError.message("响应格式不正确。") }
            object = Record(fields: result)
            let key: String? = switch mode { case .devices: "devices"; case .moments: "moments"; case .reports: "reports"; case .friends: "friends"; default: nil }
            if let key { rows = try Record.list(result[key] as Any) }
        } catch { self.error = error.localizedDescription }
    }
}
func beijingDate(_ raw: String) -> String {
    let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    guard let date else { return raw }
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd HH:mm（北京时间）"
    return formatter.string(from: date)
}
