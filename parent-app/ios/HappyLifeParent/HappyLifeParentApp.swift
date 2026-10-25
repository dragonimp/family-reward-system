import SwiftUI
import CoreImage.CIFilterBuiltins
import AgentIdentity
import Charts
import UserNotifications

@MainActor final class PhotoPushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var photoSource: DearPhotoSource?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await photoSource?.updatePushToken(token) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            self?.photoSource?.start()
            completionHandler()
        }
    }
}

private struct ReadablePage: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

extension View {
    func readablePage(maxWidth: CGFloat = 860) -> some View {
        modifier(ReadablePage(maxWidth: maxWidth))
    }
}

@main struct LinkoFamilyApp: App {
    @UIApplicationDelegateAdaptor(PhotoPushDelegate.self) private var photoPushDelegate
    @StateObject private var store = FamilyStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene { WindowGroup { FamilyRoot(store: store, identity: store.identity).tint(.teal).onAppear {
        photoPushDelegate.photoSource = store.photoSource
    }.onChange(of: scenePhase) { _, phase in
        if phase == .active { store.resumePhotoSharing(); Task { await store.refreshIfStale() } }
        else { store.suspendPhotoSharing() }
    } } }
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
                        Text("欢迎使用 Linko Moment").font(.title2.bold())
                        if store.loading { ProgressView("正在读取家长资料…") }
                        else {
                            Text("家长资料暂时无法读取。")
                            Button("重新加载") { Task { await store.load() } }.buttonStyle(.borderedProminent)
                        }
                        Button("退出登录") { store.logout() }
                    }.padding().navigationTitle("Linko Moment")
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if let notice = store.photoRequestNotice {
                VStack(spacing: 5) {
                    Label(notice, systemImage: "photo.badge.arrow.down")
                        .font(.footnote.weight(.semibold)).frame(maxWidth: .infinity)
                    if let progress = store.photoTransferProgress {
                        ProgressView(value: progress).tint(.orange)
                            .accessibilityLabel("原文件发送进度")
                    }
                }.padding(10).background(.orange.opacity(0.18))
            }
        }
        .task(id: identity.isAuthenticated) {
            if identity.isAuthenticated { await store.load(); store.resumePhotoSharing() }
        }
        .alert("操作提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了", role: .cancel) { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var login: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Image("LoginBrand")
                    .resizable()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityLabel("Linko Moment 图标")
                Text("一起记录生活里的\n重要时刻").font(.largeTitle.bold())
                Text("和家人朋友共建活动、分享照片与打卡；家长还可管理孩子的成长和积分。")
                    .foregroundStyle(.secondary)
                Spacer()
                if identity.isBusy {
                    HStack { ProgressView(); Text(identity.status).font(.subheadline); Spacer(); Button("取消") { identity.cancelLogin() }.buttonStyle(.bordered) }
                }
                if let code = identity.displayCode { Text("本次登录验证码：\(code)").font(.title3.monospacedDigit()).textSelection(.enabled) }
                Button { signIn(false) } label: { HStack { Spacer(); if identity.isBusy { ProgressView() }; Text("用户中心登录").bold(); Spacer() }.padding(.vertical, 8) }.buttonStyle(.borderedProminent).disabled(identity.isBusy)
                Button("注册用户中心账号") { signIn(true) }.frame(maxWidth: .infinity).disabled(identity.isBusy)
                Text("登录和注册在系统认证窗口中完成。登录后自动返回 App。").font(.footnote).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity).navigationTitle("Linko Moment")
        }
    }
    private func signIn(_ register: Bool) {
        Task { do { try await identity.login(register: register) } catch {
            if !(error is CancellationError) && (error as NSError).code != NSURLErrorCancelled && ((error as NSError).domain != "com.apple.AuthenticationServices.WebAuthenticationSession" || (error as NSError).code != 1) { store.error = error.localizedDescription }
        } }
    }
    private var main: some View {
        TabView {
            FamilyHome(store: store).tabItem { Label("群组", systemImage: "person.3.fill") }
                .badge(store.requests.filter { $0.text("status") == "pending" }.count)
            DearSocialView(store: store).tabItem { Label("活动", systemImage: "photo.on.rectangle.angled") }
            FamilyChatView(store: store).tabItem { Label("AI 对话", systemImage: "bubble.left.and.bubble.right.fill") }
            AccountView(store: store).tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}

struct FamilyHome: View {
    @ObservedObject var store: FamilyStore
    @State private var editor: EditorSpec?
    private var pendingRequests: Int { store.requests.filter { $0.text("status") == "pending" }.count }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("一起照顾每一天").font(.title2.bold())
                        Text("孩子成长、奖励审批和积分记录，都在这里。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section {
                    if store.groups.isEmpty { Text("创建或加入一个群组，开始共同记录成长。").foregroundStyle(.secondary) }
                    else {
                        Picker("当前群组", selection: Binding(get: { store.groupID }, set: { value in Task { await store.chooseGroup(value) } })) {
                            ForEach(store.groups) { Text($0.text("name")).tag($0.id) }
                        }.disabled(store.loading)
                    }
                    HStack {
                        Button("创建群组", systemImage: "plus.circle") { editor = EditorSpec(title: "创建群组", path: "/api/family-groups", fields: [.init(key: "name", title: "群组名称"), .init(key: "description", title: "群组简介", required: false)]) }
                        Spacer()
                        Button("加入群组", systemImage: "person.badge.plus") { editor = EditorSpec(title: "加入群组", path: "/api/family-groups/join", fields: [.init(key: "inviteCode", title: "邀请码")]) }
                    }.buttonStyle(.borderless)
                } header: { Text("虚拟群组 · 一起成长") }
                Section("待办与记录") {
                    NavigationLink { ApprovalList(store: store) } label: {
                        HStack {
                            Label("奖励审批", systemImage: "checkmark.bubble.fill")
                            Spacer()
                            if pendingRequests > 0 {
                                Text("\(pendingRequests) 待处理")
                                    .font(.caption.bold()).foregroundStyle(.orange)
                            }
                        }
                    }
                    NavigationLink { LedgerView(store: store) } label: {
                        HStack {
                            Label("积分与奖励记录", systemImage: "list.bullet.rectangle")
                            Spacer()
                            Text("共 \(store.ledgerTotal) 条")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    ForEach(store.children) { child in
                        NavigationLink { ChildDetail(store: store, child: child) } label: { ChildRow(child: child) }
                    }
                    if store.children.isEmpty && !store.loading { Text("还没有孩子").foregroundStyle(.secondary) }
                    Button("添加孩子", systemImage: "plus") {
                        editor = EditorSpec(title: "添加孩子", path: "/api/children", fields: [.init(key: "name", title: "孩子姓名"), .init(key: "note", title: "备注", required: false)], fixed: store.groupID == 0 ? [:] : ["familyGroupId": store.groupID])
                    }
                } header: { Text("孩子 · \(store.children.count)") }
                Section("群组成长") {
                    NavigationLink { RulesView(store: store) } label: { Label("奖励与行为规则", systemImage: "star.square.fill") }
                    NavigationLink { GrowthView(store: store) } label: { Label("成长足迹", systemImage: "chart.xyaxis.line") }
                    NavigationLink { FamilyConnectionsView(store: store) } label: { Label("亲子互动", systemImage: "heart.text.square") }
                }
                if store.groupID != 0 { Section("群组协作") { NavigationLink { RemoteRecords(store: store, title: "群组邀请码", path: "/api/family-groups/\(store.groupID)/invite", mode: .invite) } label: { Label("邀请组员", systemImage: "qrcode") } } }
                if store.loading { ProgressView("正在更新…") }
            }.listStyle(.insetGrouped).readablePage().navigationTitle(store.selectedFamily).refreshable { await store.load() }
                .sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
        }
    }
}
struct ChildRow: View {
    let child: Record
    var body: some View {
        HStack(spacing: 14) {
            Text(String(child.text("name").prefix(1))).font(.title2.bold()).frame(width: 48, height: 48).background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 5) { Text(child.text("name")).font(.headline); Text("\(child.amount("score")) 积分 · ¥\(child.amount("cash"))").font(.subheadline).foregroundStyle(.secondary)
                Text("守约信用分：\(child.flag("creditUnavailable") ? "暂不可用" : child.flag("creditEnabled") ? child.amount("creditScore") + " / 100" : "未开通")").font(.subheadline.weight(.medium)).foregroundStyle(.teal)
            }
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
                NavigationLink("守约信用分") { CreditView(store: store, child: current) }
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
        }.readablePage().navigationTitle(current.text("name")).refreshable { await store.load() }
            .task { await store.refreshIfStale() }
            .sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
            .sheet(isPresented: $rewarding) { RewardEditor(store: store, child: current) }
    }
}

struct ApprovalList: View {
    @ObservedObject var store: FamilyStore
    @State private var editor: EditorSpec?
    var body: some View {
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
        }.listStyle(.insetGrouped).readablePage().navigationTitle("奖励审批").refreshable { await store.load() }.sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
    }
}
struct LedgerView: View {
    @ObservedObject var store: FamilyStore
    @State private var filter = ""
    @State private var more = false
    var body: some View {
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
        }.listStyle(.insetGrouped).readablePage().navigationTitle("积分与奖励记录").searchable(text: $filter, prompt: "搜索已加载的孩子、内容、类别").refreshable { await store.load() }
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
            }.readablePage().navigationTitle("成长足迹").refreshable { await store.load() }
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
        }.readablePage().navigationTitle("奖励与行为规则").searchable(text: $search)
            .toolbar { Button("添加", systemImage: "plus") { edit(nil) } }.sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
    }
    private func edit(_ row: Record?) {
        editor = EditorSpec(title: row == nil ? "添加规则" : "编辑规则", path: row.map { "/api/rules/\($0.id)" } ?? "/api/rules", method: row == nil ? "POST" : "PUT", fields: [.init(key: "name", title: "规则名称", initial: row?.text("name") ?? ""), .init(key: "points", title: "积分（负数表示扣分）", initial: row?.amount("points") ?? "", numeric: true), .init(key: "category", title: "类别", initial: row?.text("category") ?? "日常"), .init(key: "description", title: "说明", initial: row?.text("description") ?? "", required: false)], fixed: ["cash_cny": row?.number("cash_cny") ?? 0])
    }
}
struct MembersView: View {
    @ObservedObject var store: FamilyStore
    @State private var editor: EditorSpec?
    @State private var links: [Record] = []
    @State private var trees: [Record] = []
    @State private var people: [Record] = []
    @State private var selectedMember: Record?
    @State private var treeID = 0
    @State private var personID = 0
    @State private var query = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            Section { Text("这里记录真实家庭成员。可明确关联族谱中的同一人；不会按姓名自动合并或改写亲属关系。")
                .font(.subheadline).foregroundStyle(.secondary) }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section("成员") {
                ForEach(store.members) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(row.text("displayName")).font(.headline)
                        if !row.text("note").isEmpty { Text(row.text("note")).foregroundStyle(.secondary) }
                        ForEach(Array(links.filter { $0.int("householdMemberId") == row.id }.enumerated()), id: \.offset) { _, link in
                            HStack {
                                Label("\(link.text("treeName")) · \(link.text("personName"))", systemImage: "person.line.dotted.person")
                                    .font(.caption)
                                Spacer()
                                Button("解除") { Task { await unlink(row.id, link.int("treeId")) } }
                                    .font(.caption).disabled(busy)
                            }
                        }
                        Button("关联族谱人物") { selectedMember = row; treeID = 0; personID = 0; people = []; query = "" }
                            .font(.subheadline)
                    }.padding(.vertical, 4)
                }
                Button("添加家庭成员", systemImage: "person.badge.plus") { editor = EditorSpec(title: "添加家庭成员", path: "/api/family-members", fields: [.init(key: "displayName", title: "称呼"), .init(key: "note", title: "备注", required: false)], fixed: ["role":"other"]) }
            }
        }.readablePage().navigationTitle("家庭成员")
            .task { await load() }
            .refreshable { await store.load(); await load() }
            .sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
            .sheet(item: $selectedMember) { member in
                NavigationStack {
                    Form {
                        Section { Text("为 \(member.text("displayName")) 选择族谱中的同一人。本人只能关联已绑定自己账号的人物。")
                            .font(.subheadline).foregroundStyle(.secondary) }
                        Section("族谱") {
                            Picker("选择族谱", selection: $treeID) {
                                Text("请选择").tag(0)
                                ForEach(trees) { tree in Text(tree.text("name")).tag(tree.id) }
                            }.onChange(of: treeID) { _, _ in personID = 0; people = []; Task { await loadPeople() } }
                        }
                        if treeID > 0 { Section("对应人物") {
                            HStack { TextField("按姓名或支系查找", text: $query)
                                Button("查找") { Task { await loadPeople() } } }
                            Picker("族谱人物", selection: $personID) {
                                Text("请选择").tag(0)
                                ForEach(people) { person in Text("\(person.text("displayName")) #\(person.id)").tag(person.id) }
                            }
                        } }
                        if let error { Section { Text(error).foregroundStyle(.red) } }
                    }
                    .navigationTitle("关联族谱人物")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { selectedMember = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await link(member.id) } }
                            .disabled(busy || treeID == 0 || personID == 0) } }
                }
            }
    }
    private func load() async {
        do {
            trees = try Record.list(await store.call("/api/genealogies"))
            links = try Record.list(await store.call("/api/family-members/genealogy-links"))
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func loadPeople() async {
        guard treeID > 0 else { return }
        do {
            let encoded = query.trimmingCharacters(in: .whitespacesAndNewlines)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))) ?? ""
            people = try Record.list(await store.call("/api/genealogies/\(treeID)/people?q=\(encoded)"), key: "people")
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func link(_ memberID: Int) async {
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await store.call("/api/family-members/\(memberID)/genealogy-links/\(treeID)", method: "PUT", body: ["personId": personID])
            links = try Record.list(await store.call("/api/family-members/genealogy-links"))
            selectedMember = nil
        } catch { self.error = error.localizedDescription }
    }
    private func unlink(_ memberID: Int, _ treeID: Int) async {
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await store.call("/api/family-members/\(memberID)/genealogy-links/\(treeID)", method: "DELETE")
            links = try Record.list(await store.call("/api/family-members/genealogy-links"))
        } catch { self.error = error.localizedDescription }
    }
}
struct FamilyInvitationHub: View {
    @ObservedObject var store: FamilyStore
    @State private var trees: [Record] = []
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text("请先在族谱中选择对应的人物，再生成专属邀请链接。对方登录并确认后会绑定该人物。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("选择族谱") {
                ForEach(trees) { tree in
                    NavigationLink(tree.text("name")) { GenealogyDetailView(store: store, treeID: tree.id) }
                }
                if trees.isEmpty { Text("尚未加入族谱，可先到“家族族谱”创建或加入。").foregroundStyle(.secondary) }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.readablePage().navigationTitle("邀请家人")
            .task { do { trees = try Record.list(await store.call("/api/genealogies")); error = nil } catch { self.error = error.localizedDescription } }
    }
}
struct AccountView: View {
    @ObservedObject var store: FamilyStore
    @State private var logout = false
    @State private var resources: MomentResources?
    @State private var resourceError: String?
    private struct MomentResources: Decodable {
        let appCode: String
        let privacyPolicyUrl: URL?
        let termsUrl: URL?
        let supportUrl: URL?
        let userManualUrl: URL?
    }
    var body: some View {
        NavigationStack {
            List {
                Section("用户中心") {
                    Label(store.profile?.text("username") ?? "账号", systemImage: "person.crop.circle.fill")
                    Link(destination: URL(string: "https://auth.ai.xmkurt.com/personal/info")!) {
                        Label("账号资料", systemImage: "person.crop.circle")
                    }
                    Link(destination: URL(string: "https://auth.ai.xmkurt.com/personal/info?deleteAccount=1")!) {
                        Label("注销账号", systemImage: "trash")
                    }
                    Button("退出当前账号", role: .destructive) { logout = true }
                }
                Section("订阅与权益") {
                    NavigationLink { RemoteRecords(store: store, title: "订阅权益", path: "/api/subscription", mode: .subscription) } label: {
                        Label("查看订阅权益", systemImage: "checkmark.seal.fill")
                    }
                }
                Section("功能设置") {
                    NavigationLink { GenealogyView(store: store) } label: { Label("家族族谱", systemImage: "person.3.sequence.fill") }
                    NavigationLink { MembersView(store: store) } label: { Label("家庭成员", systemImage: "person.3.fill") }
                    NavigationLink { FamilyInvitationHub(store: store) } label: { Label("邀请家人", systemImage: "envelope.open.fill") }
                    Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                        Label("通知、照片与位置权限", systemImage: "gearshape.fill")
                    }
                }
                Section("隐私与帮助") {
                    if let url = resources?.privacyPolicyUrl, url.scheme == "https" {
                        Link(destination: url) { Label("隐私政策", systemImage: "hand.raised.fill") }
                    } else {
                        Label("隐私政策未配置", systemImage: "hand.raised.fill").foregroundStyle(.secondary)
                    }
                    if let url = resources?.termsUrl, url.scheme == "https" { Link("用户协议", destination: url) }
                    NavigationLink { MomentHelpView() } label: {
                        Label("使用帮助", systemImage: "book.closed.fill")
                    }
                    if let url = resources?.userManualUrl, url.scheme == "https" { Link("详细使用手册", destination: url) }
                    if let url = resources?.supportUrl, url.scheme == "https" { Link("联系支持", destination: url) }
                    if let resourceError {
                        Text(resourceError).font(.footnote).foregroundStyle(.red)
                        Button("重试读取应用资料") { Task { await loadResources() } }
                    }
                    LabeledContent("版本", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                }
                Section("反馈与邀请") {
                    NavigationLink {
                        FeedbackWallView(identity: store.identity)
                    } label: {
                        Label("心愿墙与意见墙", systemImage: "bubble.left.and.bubble.right")
                    }
                    NavigationLink { MomentTeamMembersView() } label: {
                        Label("同行共创成员", systemImage: "person.3.fill")
                    }
                    NavigationLink { MomentTestInvitationView() } label: {
                        Label("生成专属测试邀请", systemImage: "square.and.arrow.up")
                    }
                    Text("生成 Linko Moment 专属链接，扫码或通过系统分享邀请朋友。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.readablePage().navigationTitle("我的")
                .task { await loadResources() }
                .confirmationDialog("退出 Linko Moment？", isPresented: $logout, titleVisibility: .visible) { Button("退出登录", role: .destructive) { store.logout() } } message: { Text("本机登录凭据将清除。用户中心的浏览器登录状态由用户中心管理。") }
        }
    }

    private func loadResources() async {
        do {
            var request = URLRequest(url: URL(string: "https://home.ai.impx.net/api/capabilities/apps/linko-family-ios/resources")!)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.message("应用资料暂不可用。") }
            let result = try JSONDecoder().decode(MomentResources.self, from: data)
            guard result.appCode == "linko-family-ios" else { throw APIError.message("应用资料来源不正确。") }
            resources = result; resourceError = nil
        } catch { resourceError = error.localizedDescription }
    }
}

private struct MomentTestInvitationView: View {
    @StateObject private var atlasIdentity = AgentIdentitySession(
        origin: URL(string: "https://home.ai.impx.net")!,
        callback: URL(string: "linkofamily://login-complete/")!,
        keychainService: "net.impx.happylife.parent.atlasShareIdentity")
    @State private var invitation: Invitation?
    @State private var details: Details?
    @State private var busy = false
    @State private var error: String?
    @State private var copied = false

    private struct Invitation: Decodable { let url: URL; let title: String }
    private struct Details: Decodable { let title: String; let description: String }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 38)).foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(.teal.gradient, in: RoundedRectangle(cornerRadius: 22))
                Text(details?.title ?? "专属测试邀请").font(.title2.bold())
                Text(details?.description ?? "正在读取邀请活动…")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

                if let invitation {
                    VStack(spacing: 18) {
                        if let image = qrImage(invitation.url) {
                            Image(uiImage: image).interpolation(.none).resizable()
                                .frame(width: 220, height: 220).padding(18)
                                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                                .accessibilityLabel("邀请链接二维码")
                        }
                        Text("扫码打开邀请").font(.headline)
                        Link(destination: invitation.url) {
                            Text(invitation.url.absoluteString).font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.accessibilityIdentifier("invitationLink")
                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.url = invitation.url
                                copied = true
                            } label: { Label(copied ? "已复制" : "复制链接", systemImage: copied ? "checkmark" : "doc.on.doc") }
                                .buttonStyle(.bordered)
                            ShareLink(item: invitation.url, subject: Text("\(invitation.title) 测试邀请")) {
                                Label("分享邀请", systemImage: "square.and.arrow.up")
                            }.buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(20).frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                } else if busy { ProgressView("正在生成邀请链接…") }

                Button(invitation == nil ? (atlasIdentity.isAuthenticated ? "生成邀请链接" : "登录并生成邀请") : "生成新链接") {
                    Task { await create() }
                }.disabled(busy).buttonStyle(.bordered)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding(20).frame(maxWidth: 500).frame(maxWidth: .infinity)
        }
        .background(Color.teal.opacity(0.06))
        .navigationTitle("专属测试邀请")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetails(); if invitation == nil && atlasIdentity.isAuthenticated { await create() } }
        .onChange(of: atlasIdentity.isAuthenticated) { _, signedIn in
            if signedIn && invitation == nil { Task { await create() } }
            if !signedIn { invitation = nil }
        }
    }

    private func loadDetails() async {
        do {
            let url = URL(string: "https://home.ai.impx.net/api/marketplace/apps/linko-family-ios/sharing")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw APIError.message("此应用暂未配置测试邀请。")
            }
            details = try JSONDecoder().decode(Details.self, from: data)
        } catch { self.error = error.localizedDescription }
    }

    private func create() async {
        guard !busy else { return }
        busy = true; error = nil; copied = false
        defer { busy = false }
        do {
            if !atlasIdentity.isAuthenticated { try await atlasIdentity.login() }
            guard let token = try await atlasIdentity.validAccessToken() else {
                throw APIError.message("请先登录用户中心。")
            }
            var request = URLRequest(url: URL(string: "https://home.ai.impx.net/api/marketplace/apps/linko-family-ios/share-links")!)
            request.httpMethod = "POST"; request.timeoutInterval = 20
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw APIError.message("生成邀请失败，请稍后重试。")
            }
            let result = try JSONDecoder().decode(Invitation.self, from: data)
            guard result.url.scheme == "https", result.url.host == "home.ai.impx.net",
                  result.url.path.range(of: "^/invite/[A-Za-z0-9_-]{16,48}$", options: .regularExpression) != nil,
                  result.url.query == nil, result.url.fragment == nil else {
                throw APIError.message("邀请地址无效。")
            }
            invitation = result
        } catch { self.error = error.localizedDescription }
    }

    private func qrImage(_ url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

private struct MomentHelpView: View {
    var body: some View {
        List {
            Section("活动与照片") {
                Text("在“活动”创建或加入共同活动，收藏到自己的空间，并与成员分享照片和打卡。访问别人分享的原图时，提供照片的成员需要打开 App 完成传输。")
            }
            Section("家庭与成长") {
                Text("在“群组”管理家庭成员、奖励审批和积分记录；在“我的”维护族谱、家庭成员及设备权限。")
            }
            Section("账号与支持") {
                Text("登录由用户中心提供。遇到问题可在“我的”中的“心愿墙与意见墙”提交反馈。")
            }
        }
        .navigationTitle("使用帮助")
    }
}

private struct MomentTeamMembersView: View {
    @State private var roster: Roster?
    @State private var loading = false
    @State private var error: String?

    private struct Member: Decodable, Identifiable {
        let name: String
        let role: String
        var id: String { name + "|" + role }
    }
    private struct Roster: Decodable {
        let projectCode: String
        let humans: [Member]
        let agents: [Member]
    }

    var body: some View {
        List {
            if loading && roster == nil { ProgressView("正在读取成员…") }
            if let roster {
                Section("人类成员") {
                    ForEach(roster.humans) { member($0, symbol: "person.crop.circle.fill") }
                    if roster.humans.isEmpty { Text("暂无公开成员").foregroundStyle(.secondary) }
                }
                Section("智能体成员") {
                    ForEach(roster.agents) { member($0, symbol: "cpu.fill") }
                    if roster.agents.isEmpty { Text("暂无公开成员").foregroundStyle(.secondary) }
                }
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("重试") { Task { await refresh() } }
                }
            }
        }
        .navigationTitle("同行共创成员")
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            var request = URLRequest(url: URL(string: "https://home.ai.impx.net/api/projects/family-reward/members")!)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw APIError.message("成员资料暂不可用。")
            }
            let value = try JSONDecoder().decode(Roster.self, from: data)
            guard value.projectCode == "family-reward" else { throw APIError.message("成员资料来源不正确。") }
            roster = value
        } catch { self.error = error.localizedDescription }
    }

    private func member(_ person: Member, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.teal)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(person.name).font(.headline)
                Text(person.role).font(.subheadline).foregroundStyle(.teal)
            }
        }
        .padding(.vertical, 4)
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
            }.readablePage(maxWidth: 720).sheet(isPresented: $scanning) {
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
            }.readablePage(maxWidth: 720).navigationTitle("记录奖励").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(saving) } }.interactiveDismissDisabled(saving)
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
        do { _ = try await store.call("/api/transactions", method: "POST", body: requestBody); try await store.refreshBalancesAndLedger(); dismiss() }
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
        }.readablePage().navigationTitle(title).task { await load() }.refreshable { await load() }
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

private let connectionKinds = [
    ("special_time", "孩子决定的十分钟"), ("listen", "先听我说"),
    ("reconnect", "吵架后的重连"), ("meeting", "家庭小会议")
]

struct FamilyConnectionsView: View {
    @ObservedObject var store: FamilyStore
    @State private var threads: [Record] = []
    @State private var entries: [Record] = []
    @State private var childID = 0
    @State private var kind = "special_time"
    @State private var intent = "share"
    @State private var title = ""
    @State private var requestID = UUID()
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Text("听见彼此，留出陪伴时间。互动记录不计积分、不评分。")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("孩子", selection: $childID) {
                    Text("请选择").tag(0)
                    ForEach(store.children) { child in Text(child.text("name")).tag(child.id) }
                }
                Picker("互动方式", selection: $kind) {
                    ForEach(connectionKinds, id: \.0) { item in Text(item.1).tag(item.0) }
                }
                if kind == "listen" {
                    Picker("希望怎样被倾听", selection: $intent) {
                        Text("只想说说").tag("share")
                        Text("想要安慰").tag("comfort")
                        Text("一起想办法").tag("ideas")
                    }
                }
                TextField("这次想聊什么或一起做什么", text: $title).onChange(of: title) { _, _ in requestID = UUID() }
                Button("发起互动") {
                    Task { await write("/api/family-connections", [
                        "childId": childID, "kind": kind, "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                        "intent": kind == "listen" ? intent : "", "requestId": requestID.uuidString
                    ]) { title = ""; requestID = UUID() } }
                }.disabled(busy || childID == 0 || title.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            } header: { Text("开始一段互动") }
            Section("互动记录") {
                if threads.isEmpty { Text("暂无记录，孩子也可以从手表发起。") }
                ForEach(threads) { thread in
                    NavigationLink {
                        FamilyConnectionDetail(store: store, thread: thread,
                            entries: entries.filter { $0.int("connectionId") == thread.id }, reload: load)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connectionKinds.first { $0.0 == thread.text("kind") }?.1 ?? thread.text("kind")).font(.headline)
                            Text("\(thread.text("childName")) · \(thread.text("title"))").font(.subheadline)
                            Text(thread.text("status")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.readablePage().navigationTitle("亲子互动").refreshable { await load() }
            .task { if childID == 0 { childID = store.children.first?.id ?? 0 }; await load() }
            .disabled(busy)
            .alert("操作提示", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了") { error = nil }
            } message: { Text(error ?? "") }
    }
    private func load() async {
        do {
            let response = try await store.call("/api/family-connections")
            threads = try Record.list(response, key: "threads")
            entries = try Record.list(response, key: "entries")
        } catch { self.error = error.localizedDescription }
    }
    private func write(_ path: String, _ body: [String: Any], done: @escaping () -> Void) async {
        busy = true; defer { busy = false }
        do { _ = try await store.call(path, method: "POST", body: body); done(); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct FamilyConnectionDetail: View {
    @ObservedObject var store: FamilyStore
    let thread: Record
    let entries: [Record]
    let reload: () async -> Void
    @State private var latest: Record?
    @State private var latestEntries: [Record]?
    private var current: Record { latest ?? thread }
    private var shownEntries: [Record] { latestEntries ?? entries }
    @State private var type = "message"
    @State private var content = ""
    @State private var requestID = UUID()
    @State private var schedule = Date().addingTimeInterval(3600)
    @State private var plan = ""
    @State private var busy = false
    @State private var error: String?
    private var active: Bool { !["completed", "cancelled"].contains(current.text("status")) }
    var body: some View {
        List {
            Section {
                Text(current.text("title"))
                if current.text("kind") == "listen" {
                    Text("孩子希望：\(["share": "只想说说", "comfort": "想要安慰", "ideas": "一起想办法"][current.text("intent")] ?? "先听听")")
                }
                if current.has("scheduledAt") { Text("约定时间：\(beijingDate(current.text("scheduledAt")))") }
                if !current.text("trialPlan").isEmpty { Text("本周试行：\(current.text("trialPlan"))") }
            }
            Section("彼此说的话") {
                ForEach(shownEntries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(entry.text("authorRole") == "child" ? "孩子" : "家长") · \(entry.text("type"))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(entry.text("content"))
                    }
                }
            }
            if active {
                Section("记录想法") {
                    Picker("内容", selection: $type) {
                        Text("想说的话").tag("message")
                        if current.text("kind") == "reconnect" { Text("我的感受").tag("feeling"); Text("我的期待").tag("hope") }
                        if current.text("kind") == "meeting" { Text("我的提议").tag("proposal") }
                        if current.text("status") == "trial" || current.text("kind") == "special_time" { Text("复盘").tag("reflection") }
                    }
                    TextField("温和地写下想表达的内容", text: $content, axis: .vertical)
                        .lineLimit(2...5).onChange(of: content) { _, _ in requestID = UUID() }
                    Button("发送") { Task { await write("entries", ["type": type, "content": content, "requestId": requestID.uuidString]) { content = ""; requestID = UUID() } } }
                        .disabled(busy || content.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                Section("下一步") {
                    if current.text("kind") == "special_time" && current.text("status") == "open" {
                        DatePicker("专心陪伴时间", selection: $schedule, in: Date()...Date().addingTimeInterval(90 * 86400))
                        Button("约定时间") { Task { await write("transition", ["action": "schedule", "scheduledAt": ISO8601DateFormatter().string(from: schedule)]) {} } }
                    }
                    if current.text("kind") == "meeting" && current.text("status") == "open" {
                        TextField("双方提出想法后，写下本周试行安排", text: $plan, axis: .vertical)
                        Button("开始一周试行") { Task { await write("transition", ["action": "start_trial", "plan": plan]) {} } }
                            .disabled(plan.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    }
                    if current.text("kind") == "meeting" && current.text("status") == "trial" {
                        Button("七天后完成复盘") { Task { await write("transition", ["action": "review"]) {} } }
                    } else if current.text("kind") != "meeting" && (current.text("kind") != "special_time" || current.text("status") == "scheduled") {
                        Button("完成互动") { Task { await write("transition", ["action": "complete"]) {} } }
                    }
                    Button("取消互动", role: .destructive) { Task { await write("transition", ["action": "cancel"]) {} } }
                }
            }
        }.readablePage().navigationTitle("亲子互动").disabled(busy).task { await loadLocal() }
            .alert("操作提示", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了") { error = nil }
            } message: { Text(error ?? "") }
    }
    private func loadLocal() async {
        do {
            let response = try await store.call("/api/family-connections")
            let threads = try Record.list(response, key: "threads")
            let entries = try Record.list(response, key: "entries")
            latest = threads.first { $0.id == thread.id }
            latestEntries = entries.filter { $0.int("connectionId") == thread.id }
        } catch { self.error = error.localizedDescription }
    }
    private func write(_ endpoint: String, _ body: [String: Any], done: @escaping () -> Void) async {
        busy = true; defer { busy = false }
        do {
            _ = try await store.call("/api/family-connections/\(current.id)/\(endpoint)", method: "POST", body: body)
            done(); await loadLocal(); await reload()
        } catch { self.error = error.localizedDescription }
    }
}
