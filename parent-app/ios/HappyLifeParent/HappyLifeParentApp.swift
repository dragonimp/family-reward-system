import AtlasReleases
import SwiftUI
import CoreImage.CIFilterBuiltins
import AgentIdentity
import Charts
import UserNotifications

@MainActor final class PhotoPushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var photoSource: DearPhotoSource?
    weak var notifications: MomentNotifications?
    private var pendingMessageID: Int64?

    func connect(store: FamilyStore) {
        photoSource = store.photoSource; notifications = store.notifications
        if let pendingMessageID { store.notifications.open(messageID: pendingMessageID); self.pendingMessageID = nil }
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        notifications?.updatePushToken(token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        notifications?.registrationFailed()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor [weak self] in await self?.notifications?.reload() }
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            self?.photoSource?.start()
            let info = response.notification.request.content.userInfo
            if info["applicationKey"] as? String == "happylife.ai",
               let raw = info["messageId"] as? String, let id = Int64(raw), id > 0 {
                if let notifications = self?.notifications { notifications.open(messageID: id) }
                else { self?.pendingMessageID = id }
            }
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
    @StateObject private var store: FamilyStore
    @StateObject private var language: AgentIdentityLanguageStore
    init() {
        let store = FamilyStore()
        _store = StateObject(wrappedValue: store)
        let language = AgentIdentityLanguageStore(applicationKey: "happylife.ai",
            authority: URL(string: "https://auth.ai.xmkurt.com")!,
            accountIdentifier: store.identity.accountIdentifier,
            accountIdentifierProvider: { store.identity.accountIdentifier },
            tokenProvider: { try await store.identity.validAccessToken() })
        _language = StateObject(wrappedValue: language)
    }
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene { WindowGroup { FamilyRoot(store: store, identity: store.identity, notifications: store.notifications).agentIdentityInAppLinks().environmentObject(store.language).tint(.teal).onAppear {
        photoPushDelegate.connect(store: store)
    }.onOpenURL { url in
        if let link = MomentActivityLink(url: url) {
            store.notifications.showingInbox = false
            store.pendingActivityLink = link
        }
    }.onChange(of: scenePhase) { _, phase in
        if phase == .active { store.resumePhotoSharing(); Task { await store.language.refresh(); await store.refreshIfStale() } }
        else { store.suspendPhotoSharing() }
    } } }
}

struct FamilyRoot: View {
    @EnvironmentObject private var language: AgentIdentityLanguageStore
    @ObservedObject var store: FamilyStore
    @ObservedObject var identity: AgentIdentitySession
    @ObservedObject var notifications: MomentNotifications
    @State private var selectedTab = 0
    @AppStorage("moment.sections.dining") private var diningEnabled = true
    @AppStorage("moment.sections.growth") private var growthEnabled = false
    @AppStorage("moment.sections.activities") private var activitiesEnabled = true
    @AppStorage("moment.sections.exercise") private var exerciseEnabled = true
    var body: some View {
        Group {
            if !identity.isAuthenticated { login }
            else { main }
        }
        .environment(\.locale, language.locale)
        .environmentObject(store)
        .onChange(of: identity.accountIdentifier) { _, account in
            store.language.accountDidChange(account)
            Task { await store.language.refresh() }
        }
        .task(id: identity.isAuthenticated) {
            store.language.accountDidChange(identity.isAuthenticated ? identity.accountIdentifier : nil)
            await store.language.refresh()
            if identity.isAuthenticated { await store.load(); store.resumePhotoSharing() }
        }
        .sheet(isPresented: Binding(get: { identity.isAuthenticated && notifications.showingInbox }, set: { notifications.showingInbox = $0 })) {
            MomentNotificationInbox(store: store, notifications: notifications)
        }
        .alert(String(localized: "操作提示", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button(String(localized: "知道了", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .cancel) { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var login: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer()
                    Image("LoginBrand")
                        .resizable()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel(String(localized: "Linko Moment 图标", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    Text(String(localized: "一起记录生活里的\n重要时刻", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "和家人朋友共建活动、分享照片与打卡；家长还可管理孩子的成长和积分。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if identity.isBusy {
                        HStack { ProgressView(); Text(identity.status).font(.subheadline); Spacer(); Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { identity.cancelLogin() }.buttonStyle(.bordered) }
                    }
                    if let code = identity.displayCode { Text(String(localized: "本次登录验证码：\(code)", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.title3.monospacedDigit()).textSelection(.enabled) }
                    Button { signIn(false) } label: { HStack { Spacer(); if identity.isBusy { ProgressView() }; Text(String(localized: "用户中心登录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).bold(); Spacer() }.padding(.vertical, 8) }.buttonStyle(.borderedProminent).disabled(identity.isBusy)
                    Button(String(localized: "注册用户中心账号", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { signIn(true) }.frame(maxWidth: .infinity).disabled(identity.isBusy)
                    Text(String(localized: "登录和注册在系统认证窗口中完成。登录后自动返回 App。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.navigationTitle("Linko Moment")
        }
    }
    private func signIn(_ register: Bool) {
        Task { do { try await identity.login(register: register) } catch {
            if !(error is CancellationError) && (error as NSError).code != NSURLErrorCancelled && ((error as NSError).domain != "com.apple.AuthenticationServices.WebAuthenticationSession" || (error as NSError).code != 1) { store.error = momentDisplayError(error) }
        } }
    }
    private var growthUnavailable: some View {
                NavigationStack {
                    VStack(spacing: 24) {
                        Image(systemName: "person.2.circle.fill").font(.system(size: 64)).foregroundStyle(.teal)
                        Text(String(localized: "欢迎使用 Linko Moment", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.title2.bold())
                        if store.loading { ProgressView(String(localized: "正在读取家长资料…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                        else {
                            Text(String(localized: "家长资料暂时无法读取。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                            Button(String(localized: "重新加载", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.load() } }.buttonStyle(.borderedProminent)
                        }
                        Button(String(localized: "退出登录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { store.logout() }
                    }.padding().navigationTitle("Linko Moment")
                }
    }
    private var main: some View {
        TabView(selection: $selectedTab) {
            if diningEnabled {
            DiningModesView(userID: identity.accountIdentifier ?? "", family: store).id(identity.accountIdentifier ?? "").tabItem { Label(String(localized: "干饭", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "fork.knife") }.tag(0)
            }
            if growthEnabled {
            Group { if store.ready { FamilyHome(store: store) } else { growthUnavailable } }.tabItem { Label(String(localized: "带娃", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "person.3.fill") }
                .badge(store.requests.filter { $0.text("status") == "pending" }.count).tag(1)
            }
            if activitiesEnabled {
            DearSocialView(store: store).tabItem { Label(String(localized: "活动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "photo.on.rectangle.angled") }.tag(2)
            }
            if exerciseEnabled {
            Group { if store.ready { ExerciseView(userID: store.profile?.text("unifiedUserId") ?? "").id(store.profile?.text("unifiedUserId") ?? "") } else { growthUnavailable } }.tabItem { Label(String(localized: "运动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "figure.walk") }.tag(3)
            }
            AccountView(store: store).tabItem { Label(String(localized: "我的", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "person.crop.circle") }.badge(notifications.unreadCount).tag(4)
        }
        .onChange(of: store.pendingExerciseContinuation) { _, value in if value != nil { exerciseEnabled = true; selectedTab = 3 } }
        .onChange(of: store.pendingExerciseActivity) { _, value in if value != nil { exerciseEnabled = true; selectedTab = 3 } }
        .onAppear { if store.pendingActivityLink != nil { activitiesEnabled = true; selectedTab = 2 } }
        .onChange(of: store.pendingActivityLink?.id) { _, id in if id != nil { activitiesEnabled = true; selectedTab = 2 } }
        .onChange(of: [diningEnabled, growthEnabled, activitiesEnabled, exerciseEnabled]) { _, enabled in
            if selectedTab < 4 && !enabled[selectedTab] { selectedTab = 4 }
        }
        .onAppear {
            let enabled = [diningEnabled, growthEnabled, activitiesEnabled, exerciseEnabled]
            if selectedTab < 4 && !enabled[selectedTab] { selectedTab = 4 }
        }
    }
}

struct FamilyHome: View {
    @ObservedObject var store: FamilyStore
    private var pendingRequests: Int { store.requests.filter { $0.text("status") == "pending" }.count }
    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "我的孩子", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    ForEach(store.homeChildren) { child in
                        NavigationLink { ChildDetail(store: store, child: child) } label: { ChildRow(child: child) }
                    }
                    if store.homeChildren.isEmpty && !store.loading {
                        Text(String(localized: "还没有孩子", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary)
                    }
                }
                Section(String(localized: "孩子成长总结", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    ForEach(store.growthReports) { report in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(report.text("subjectName")).font(.headline)
                            Text(report.text("periodStart") + " — " + report.text("periodEnd")).font(.caption).foregroundStyle(.secondary)
                            Text(report.text("praise"))
                            Text(report.text("changeSummary"))
                            Text(report.text("nextStep")).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                    if let error = store.growthReportError { Text(error).foregroundStyle(.secondary) }
                    else if store.growthReports.isEmpty && !store.loading {
                        Text(String(localized: "暂无孩子成长报告", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary)
                    }
                }
                Section(String(localized: "明细台账", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    ForEach(store.transactions.prefix(5)) { row in LedgerRow(row: row) }
                    if store.transactions.isEmpty && !store.loading {
                        Text(String(localized: "还没有记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary)
                    }
                    NavigationLink { LedgerView(store: store) } label: {
                        LabeledContent(String(localized: "积分与奖励记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: String(localized: "共 \(store.ledgerTotal) 条", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    }
                }
                if store.loading { ProgressView() }
            }
            .listStyle(.insetGrouped).readablePage()
            .navigationTitle(String(localized: "带娃", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink { FamilyManagement(store: store) } label: { Label(String(localized: "家庭组与孩子管理", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "person.3") }
                        NavigationLink { RulesView(store: store) } label: { Label(String(localized: "奖励与行为规则", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "star.square") }
                        NavigationLink { GrowthView(store: store) } label: { Label(String(localized: "成长足迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "chart.xyaxis.line") }
                        NavigationLink { FamilyConnectionsView(store: store) } label: { Label(String(localized: "亲子互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "heart.text.square") }
                        Button { Task { await store.load() } } label: { Label(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "arrow.clockwise") }
                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(String(localized: "带娃管理菜单", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    MomentNotificationButton(notifications: store.notifications, pendingRequests: pendingRequests)
                }
            }
            .refreshable { await store.load() }
            .task { await store.refreshIfStale() }
        }
    }
}
struct FamilyManagement: View {
    @ObservedObject var store: FamilyStore
    @State private var editor: EditorSpec?
    var body: some View {
        List {
            Section {
                if store.groups.isEmpty { Text(String(localized: "创建或加入一个群组，开始共同记录成长。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
                else {
                    Picker(String(localized: "当前群组", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: Binding(get: { store.groupID }, set: { value in Task { await store.chooseGroup(value) } })) {
                        ForEach(store.groups) { Text($0.text("name")).tag($0.id) }
                    }.disabled(store.loading)
                }
                HStack {
                    Button(String(localized: "创建群组", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "plus.circle") { editor = EditorSpec(title: String(localized: "创建群组", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/family-groups", fields: [.init(key: "name", title: String(localized: "群组名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))), .init(key: "description", title: String(localized: "群组简介", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), required: false)]) }
                    Spacer()
                    Button(String(localized: "加入群组", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "person.badge.plus") { editor = EditorSpec(title: String(localized: "加入群组", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/family-groups/join", fields: [.init(key: "inviteCode", title: String(localized: "邀请码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))]) }
                }.buttonStyle(.borderless)
            } header: { Text(String(localized: "虚拟群组 · 一起成长", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            Section {
                ForEach(store.children) { child in
                    NavigationLink { ChildDetail(store: store, child: child) } label: { ChildRow(child: child) }
                }
                if store.children.isEmpty && !store.loading { Text(String(localized: "还没有孩子", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
                Button(String(localized: "添加孩子", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "plus") {
                    editor = EditorSpec(title: String(localized: "添加孩子", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/children", fields: [.init(key: "name", title: String(localized: "孩子姓名", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))), .init(key: "note", title: String(localized: "备注", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), required: false)], fixed: store.groupID == 0 ? [:] : ["familyGroupId": store.groupID])
                }
            } header: { Text(String(localized: "孩子 · \(store.children.count)", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            Section(String(localized: "群组成长", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                NavigationLink { RulesView(store: store) } label: { Label(String(localized: "奖励与行为规则", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "star.square.fill") }
                NavigationLink { GrowthView(store: store) } label: { Label(String(localized: "成长足迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "chart.xyaxis.line") }
                NavigationLink { FamilyConnectionsView(store: store) } label: { Label(String(localized: "亲子互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "heart.text.square") }
            }
            if store.groupID != 0 { Section(String(localized: "群组协作", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { NavigationLink { RemoteRecords(store: store, title: String(localized: "群组邀请码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/family-groups/\(store.groupID)/invite", mode: .invite) } label: { Label(String(localized: "邀请组员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "qrcode") } } }
            if store.loading { ProgressView(String(localized: "正在更新…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            }.listStyle(.insetGrouped).readablePage().navigationTitle(String(localized: "带娃管理", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).refreshable { await store.load() }
            .sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
    }
}
struct ChildRow: View {
    let child: Record
    var body: some View {
        HStack(spacing: 14) {
            Text(String(child.text("name").prefix(1))).font(.title2.bold()).frame(width: 48, height: 48).background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 5) { Text(child.text("name")).font(.headline); Text(String(localized: "\(child.amount("score")) 积分 · ¥\(child.amount("cash"))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.subheadline).foregroundStyle(.secondary)
                Text(String(localized: "守约信用分：\(child.flag("creditUnavailable") ? String(localized: "暂不可用", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : child.flag("creditEnabled") ? child.amount("creditScore") + " / 100" : String(localized: "未开通", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.subheadline.weight(.medium)).foregroundStyle(.teal)
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
    var current: Record { (store.homeChildren + store.children).first(where: { $0.id == child.id }) ?? child }
    var body: some View {
        List {
            Section { ChildRow(child: current); Button(String(localized: "记录奖励 / 扣分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "plus.circle.fill") { rewarding = true } }
            Section(String(localized: "孩子资料", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                LabeledContent(String(localized: "积分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: current.amount("score")); LabeledContent(String(localized: "零用钱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: "¥" + current.amount("cash")); LabeledContent(String(localized: "物品", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: current.amount("items"))
                NavigationLink(String(localized: "守约信用分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { CreditView(store: store, child: current) }
                Button(String(localized: "修改姓名与备注", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { editor = EditorSpec(title: String(localized: "修改孩子资料", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/children/\(child.id)", method: "PUT", fields: [.init(key: "name", title: String(localized: "姓名", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), initial: current.text("name")), .init(key: "note", title: String(localized: "备注", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), initial: current.text("note"), required: false)]) }
            }
            Section(String(localized: "手表与成长", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                NavigationLink(String(localized: "手表设备", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { RemoteRecords(store: store, title: String(localized: "手表设备", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/children/\(child.id)/devices?\(store.scope)", mode: .devices, childID: child.id) }
                Button(String(localized: "连接手表", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { editor = EditorSpec(title: String(localized: "连接孩子手表", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/children/\(child.id)/pair-device", fields: [.init(key: "code", title: String(localized: "手表上显示的配对码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))], scansWatchCode: true) }
                Button(String(localized: "生成孩子授权码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { editor = EditorSpec(title: String(localized: "生成孩子授权码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/children/\(child.id)/auth-code", fields: [], fixed: ["familyGroupId": store.groupID, "expiresInMinutes": 10], showsReceipt: true) }
                NavigationLink(String(localized: "温暖瞬间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { RemoteRecords(store: store, title: String(localized: "温暖瞬间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/warm-moments?childId=\(child.id)&limit=30", mode: .moments) }
                NavigationLink(String(localized: "成长周报", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { RemoteRecords(store: store, title: String(localized: "成长周报", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/growth-reports?childId=\(child.id)&audience=child&period=weekly&ai=false", mode: .reports) }
                NavigationLink(String(localized: "好友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { RemoteRecords(store: store, title: String(localized: "孩子的好友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/children/\(child.id)/friends?\(store.scope)", mode: .friends) }
            }
        }.readablePage().navigationTitle(current.text("name")).refreshable { await store.load() }
            .task {
                let group = child.int("familyGroupId")
                if group != store.groupID && store.groups.contains(where: { $0.id == group }) { await store.chooseGroup(group) }
                else { await store.refreshIfStale() }
            }
            .sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
            .sheet(isPresented: $rewarding) { RewardEditor(store: store, child: current) }
    }
}

struct ApprovalList: View {
    @ObservedObject var store: FamilyStore
    @State private var editor: EditorSpec?
    var body: some View {
        List {
            if store.requests.isEmpty { ContentUnavailableView(String(localized: "暂无申请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "checkmark.bubble", description: Text(String(localized: "孩子从手表提交的奖励申请会显示在这里。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))) }
            ForEach(store.requests) { row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(row.text("childName")).font(.headline); Spacer(); Text(row.text("statusText")).font(.caption).foregroundStyle(.secondary) }
                    Text(row.text("title")); Text(String(localized: "\(row.amount("points")) 积分 · \(row.text("category"))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.teal)
                    if !row.text("note").isEmpty { Text(row.text("note")).font(.subheadline) }
                    Text(localDateText(row.text("requestedAt"))).font(.caption).foregroundStyle(.secondary)
                    if row.text("status") == "pending" {
                        Button(String(localized: "批准申请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { editor = EditorSpec(title: String(localized: "批准 \(row.text("childName")) 的申请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/reward-requests/\(row.id)/approve", fields: [.init(key: "reviewNote", title: String(localized: "给孩子的话", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), required: false)], fixed: ["familyGroupId": row.int("familyGroupId")]) }.buttonStyle(.bordered)
                    }
                }.padding(.vertical, 6)
            }
        }.listStyle(.insetGrouped).readablePage().navigationTitle(String(localized: "奖励审批", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).refreshable { await store.load() }.sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
    }
}
struct LedgerRow: View {
    let row: Record
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(row.text("childName")).font(.headline); Spacer(); Text(row.amount("amount") + (row.text("type") == "cash" ? String(localized: " 元", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : row.text("type") == "item" ? String(localized: " 件", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: " 分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))).foregroundStyle(row.number("amount") >= 0 ? .teal : .orange).font(.headline.monospacedDigit()) }
            Text(row.text("description")); Text("\(row.text("date")) · \(row.text("category"))").font(.caption).foregroundStyle(.secondary)
            if !row.text("notes").isEmpty { Text(row.text("notes")).font(.caption) }
                }.padding(.vertical, 4)
    }
}
struct LedgerView: View {
    @ObservedObject var store: FamilyStore
    @State private var filter = ""
    @State private var more = false
    var body: some View {
        List {
            Section { Text(String(localized: "我的孩子 · 共 \(store.ledgerTotal) 条", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
            ForEach(store.transactions.filter { filter.isEmpty || ($0.text("childName") + $0.text("description") + $0.text("category")).localizedCaseInsensitiveContains(filter) }) { row in
                LedgerRow(row: row)
            }
            if store.transactions.isEmpty { ContentUnavailableView(String(localized: "还没有记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "list.bullet.rectangle", description: Text(String(localized: "从孩子详情中记录奖励与扣分。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))) }
            if store.transactions.count < store.ledgerTotal {
                Button(more ? String(localized: "正在加载…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "加载更多", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { more = true; defer { more = false }; do { try await store.loadLedger(page: store.ledgerPage + 1) } catch { store.error = momentDisplayError(error) } } }.disabled(more)
            }
        }.listStyle(.insetGrouped).readablePage().navigationTitle(String(localized: "积分与奖励记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).searchable(text: $filter, prompt: String(localized: "搜索已加载的孩子、内容、类别", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).refreshable { await store.load() }
    }
}
struct GrowthView: View {
    @ObservedObject var store: FamilyStore
    var body: some View {
        NavigationStack {
            List {
                Section { Text(store.selectedFamily).font(.headline); Text(String(localized: "本周成长 · 北京时间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(store.growth.enumerated()), id: \.offset) { _, row in
                    Section(row.text("childName")) {
                        HStack { metric(String(localized: "本周记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), row.amount("currentWeekRecords")); Spacer(); metric(String(localized: "活跃天数", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), row.amount("activeDays")); Spacer(); metric(String(localized: "连续天数", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), row.amount("streakDays")) }
                        let trend = (row.fields["trend"] as? [[String: Any]] ?? []).map { Record(fields: $0) }
                        Chart(Array(trend.enumerated()), id: \.offset) { _, day in
                            BarMark(x: .value(String(localized: "日期", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), String(day.text("date").suffix(5))), y: .value(String(localized: "记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), day.number("records"))).foregroundStyle(.teal.gradient)
                        }.frame(height: 150).accessibilityLabel(String(localized: "每日成长记录数量", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        Text(String(localized: "比上周\(row.number("change") >= 0 ? String(localized: "增加", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "减少", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) \(abs(row.int("change"))) 条记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if store.growth.isEmpty { ContentUnavailableView(String(localized: "暂无成长统计", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "chart.bar", description: Text(String(localized: "记录孩子的日常进步，积累成长轨迹。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))) }
            }.readablePage().navigationTitle(String(localized: "成长足迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).refreshable { await store.load() }
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
                    HStack { Text(rule.text("name")).font(.headline); Spacer(); Text(String(localized: "\(rule.amount("points")) 分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(rule.number("points") >= 0 ? .teal : .orange) }
                    Text(rule.text("description")).font(.subheadline)
                    HStack { Text(rule.text("category")); Text(rule.flag("isPublic") ? String(localized: "公共规则", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "我的规则", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }.font(.caption).foregroundStyle(.secondary)
                    if !rule.flag("isPublic") { Button(String(localized: "编辑", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { edit(rule) } }
                }.padding(.vertical, 5)
            }
        }.readablePage().navigationTitle(String(localized: "奖励与行为规则", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).searchable(text: $search)
            .toolbar { Button(String(localized: "添加", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "plus") { edit(nil) } }.sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
    }
    private func edit(_ row: Record?) {
        editor = EditorSpec(title: row == nil ? String(localized: "添加规则", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "编辑规则", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: row.map { "/api/rules/\($0.id)" } ?? "/api/rules", method: row == nil ? "POST" : "PUT", fields: [.init(key: "name", title: String(localized: "规则名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), initial: row?.text("name") ?? ""), .init(key: "points", title: String(localized: "积分（负数表示扣分）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), initial: row?.amount("points") ?? "", numeric: true), .init(key: "category", title: String(localized: "类别", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), initial: row?.text("category") ?? String(localized: "日常", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))), .init(key: "description", title: String(localized: "说明", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), initial: row?.text("description") ?? "", required: false)], fixed: ["cash_cny": row?.number("cash_cny") ?? 0])
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
            Section { Text(String(localized: "这里记录真实家庭成员。可明确关联族谱中的同一人；不会按姓名自动合并或改写亲属关系。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                .font(.subheadline).foregroundStyle(.secondary) }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section(String(localized: "成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                ForEach(store.members) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(row.text("displayName")).font(.headline)
                        if !row.text("note").isEmpty { Text(row.text("note")).foregroundStyle(.secondary) }
                        ForEach(Array(links.filter { $0.int("householdMemberId") == row.id }.enumerated()), id: \.offset) { _, link in
                            HStack {
                                Label("\(link.text("treeName")) · \(link.text("personName"))", systemImage: "person.line.dotted.person")
                                    .font(.caption)
                                Spacer()
                                Button(String(localized: "解除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await unlink(row.id, link.int("treeId")) } }
                                    .font(.caption).disabled(busy)
                            }
                        }
                        Button(String(localized: "关联族谱人物", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { selectedMember = row; treeID = 0; personID = 0; people = []; query = "" }
                            .font(.subheadline)
                    }.padding(.vertical, 4)
                }
                Button(String(localized: "添加家庭成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "person.badge.plus") { editor = EditorSpec(title: String(localized: "添加家庭成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/family-members", fields: [.init(key: "displayName", title: String(localized: "称呼", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))), .init(key: "note", title: String(localized: "备注", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), required: false)], fixed: ["role":"other"]) }
            }
        }.readablePage().navigationTitle(String(localized: "家庭成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .task { await load() }
            .refreshable { await store.load(); await load() }
            .sheet(item: $editor) { NativeEditor(store: store, spec: $0) }
            .sheet(item: $selectedMember) { member in
                NavigationStack {
                    Form {
                        Section { Text(String(localized: "为 \(member.text("displayName")) 选择族谱中的同一人。本人只能关联已绑定自己账号的人物。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                            .font(.subheadline).foregroundStyle(.secondary) }
                        Section(String(localized: "族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                            Picker(String(localized: "选择族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $treeID) {
                                Text(String(localized: "请选择", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag(0)
                                ForEach(trees) { tree in Text(tree.text("name")).tag(tree.id) }
                            }.onChange(of: treeID) { _, _ in personID = 0; people = []; Task { await loadPeople() } }
                        }
                        if treeID > 0 { Section(String(localized: "对应人物", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                            HStack { TextField(String(localized: "按姓名或支系查找", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $query)
                                Button(String(localized: "查找", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await loadPeople() } } }
                            Picker(String(localized: "族谱人物", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $personID) {
                                Text(String(localized: "请选择", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag(0)
                                ForEach(people) { person in Text("\(person.text("displayName")) #\(person.id)").tag(person.id) }
                            }
                        } }
                        if let error { Section { Text(error).foregroundStyle(.red) } }
                    }
                    .navigationTitle(String(localized: "关联族谱人物", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { selectedMember = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button(String(localized: "保存", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await link(member.id) } }
                            .disabled(busy || treeID == 0 || personID == 0) } }
                }
            }
    }
    private func load() async {
        do {
            trees = try Record.list(await store.call("/api/genealogies"))
            links = try Record.list(await store.call("/api/family-members/genealogy-links"))
            error = nil
        } catch { self.error = momentDisplayError(error) }
    }
    private func loadPeople() async {
        guard treeID > 0 else { return }
        do {
            let encoded = query.trimmingCharacters(in: .whitespacesAndNewlines)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))) ?? ""
            people = try Record.list(await store.call("/api/genealogies/\(treeID)/people?q=\(encoded)"), key: "people")
            error = nil
        } catch { self.error = momentDisplayError(error) }
    }
    private func link(_ memberID: Int) async {
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await store.call("/api/family-members/\(memberID)/genealogy-links/\(treeID)", method: "PUT", body: ["personId": personID])
            links = try Record.list(await store.call("/api/family-members/genealogy-links"))
            selectedMember = nil
        } catch { self.error = momentDisplayError(error) }
    }
    private func unlink(_ memberID: Int, _ treeID: Int) async {
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await store.call("/api/family-members/\(memberID)/genealogy-links/\(treeID)", method: "DELETE")
            links = try Record.list(await store.call("/api/family-members/genealogy-links"))
        } catch { self.error = momentDisplayError(error) }
    }
}
struct FamilyInvitationHub: View {
    @ObservedObject var store: FamilyStore
    @State private var trees: [Record] = []
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text(String(localized: "请先在族谱中选择对应的人物，再生成专属邀请链接。对方登录并确认后会绑定该人物。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section(String(localized: "选择族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                ForEach(trees) { tree in
                    NavigationLink(tree.text("name")) { GenealogyDetailView(store: store, treeID: tree.id) }
                }
                if trees.isEmpty { Text(String(localized: "尚未加入族谱，可先到“家族族谱”创建或加入。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.readablePage().navigationTitle(String(localized: "邀请家人", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .task { do { trees = try Record.list(await store.call("/api/genealogies")); error = nil } catch { self.error = momentDisplayError(error) } }
    }
}
struct AccountView: View {
    @EnvironmentObject private var language: AgentIdentityLanguageStore
    @ObservedObject var store: FamilyStore
    @State private var logout = false
    @State private var deleteAccount = false
    @State private var userInfo: AgentIdentityUserInfo?
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
                Section(String(localized: "用户与权益", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    AgentIdentityAccountRow(iconEmoji: userInfo?.iconEmoji,
                                            username: userInfo?.username ?? store.profile?.text("username") ?? String(localized: "账号", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)),
                                            displayName: userInfo?.displayName,
                                            logoutTitle: String(localized: "退出登录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { label in
                        Link(destination: URL(string: "https://auth.ai.xmkurt.com/personal/info")!) { label }
                    } onLogout: { logout = true }
                    Link(destination: URL(string: "https://auth.ai.xmkurt.com/personal/info?section=password")!) {
                        Label(String(localized: "修改密码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "key")
                    }
                    Button { deleteAccount = true } label: {
                        Label(String(localized: "账号注销", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "person.crop.circle.badge.xmark")
                    }
                    NavigationLink { RemoteRecords(store: store, title: String(localized: "套餐权益", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), path: "/api/subscription", mode: .subscription) } label: {
                        Label(String(localized: "套餐权益", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "checkmark.seal")
                    }
                    Button { store.notifications.open() } label: {
                        Label(store.language.text("messages.title"), systemImage: "bell.badge")
                    }
                    NavigationLink { AgentIdentityLanguageSettingsView(store: store.language) } label: {
                        Label(store.language.text("language.settings"), systemImage: "character.bubble")
                    }
                }
                Section(String(localized: "应用与设置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    NavigationLink { MomentSectionSettings() } label: { Label(String(localized: "栏目启用", bundle: AgentIdentityLanguage.appBundle()), systemImage: "square.grid.2x2") }
                    NavigationLink { FamilyChatView(store: store) } label: {
                        Label(String(localized: "AI 对话", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    NavigationLink { GenealogyView(store: store) } label: { Label(String(localized: "家族族谱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "person.3.sequence.fill") }
                    NavigationLink { MembersView(store: store) } label: { Label(String(localized: "家庭成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "person.3.fill") }
                    NavigationLink { FamilyInvitationHub(store: store) } label: { Label(String(localized: "邀请家人", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "envelope.open.fill") }
                    Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                        Label(String(localized: "通知、照片与位置权限", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "gearshape.fill")
                    }
                }
                Section(String(localized: "帮助与隐私", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    if let url = resources?.privacyPolicyUrl, url.scheme == "https" {
                        Link(destination: url) { Label(String(localized: "隐私政策", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "hand.raised.fill") }
                    } else {
                        Label(String(localized: "隐私政策未配置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "hand.raised.fill").foregroundStyle(.secondary)
                    }
                    if let url = resources?.termsUrl, url.scheme == "https" {
                        Link(destination: url) { Label(String(localized: "用户协议", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "doc.text") }
                    } else { Label(String(localized: "用户协议未配置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "doc.text").foregroundStyle(.secondary) }
                    NavigationLink { MomentHelpView() } label: {
                        Label(String(localized: "使用帮助", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "book.closed.fill")
                    }
                    if let url = resources?.userManualUrl, url.scheme == "https" {
                        Link(destination: url) { Label(String(localized: "详细使用手册", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "book") }
                    }
                    if let url = resources?.supportUrl, url.scheme == "https" { Link(String(localized: "联系支持", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: url) }
                    if let resourceError {
                        Text(resourceError).font(.footnote).foregroundStyle(.red)
                        Button(String(localized: "重试读取应用资料", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await loadResources() } }
                    }
                    NavigationLink { MomentAboutView(store: store) } label: {
                        HStack {
                            Label(String(localized: "关于我们", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "info.circle")
                            Spacer()
                            Text(MomentAboutView.version).foregroundStyle(.secondary)
                        }
                    }
                }

            }.readablePage().navigationTitle(String(localized: "我的", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                .task { await loadResources() }
                .task(id: store.identity.isAuthenticated) {
                    if store.identity.isAuthenticated {
                        userInfo = try? await store.identity.userInfo(authority: URL(string: "https://auth.ai.xmkurt.com")!)
                    } else { userInfo = nil }
                }
                .confirmationDialog(String(localized: "退出 Linko Moment？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: $logout, titleVisibility: .visible) { Button(String(localized: "退出登录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { store.logout() } } message: { Text(String(localized: "本机登录凭据将清除。用户中心的浏览器登录状态由用户中心管理。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                .confirmationDialog(String(localized: "前往用户中心注销账号？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: $deleteAccount, titleVisibility: .visible) {
                    Link(String(localized: "继续注销", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: URL(string: "https://auth.ai.xmkurt.com/personal/info?deleteAccount=1")!)
                } message: { Text(String(localized: "账号注销会影响同一用户中心账号使用的其他应用。用户中心还会要求进一步确认。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        }
    }

    private func loadResources() async {
        do {
            var request = URLRequest(url: URL(string: "https://home.ai.impx.net/api/capabilities/apps/linko-family-ios/resources")!)
            request.setValue(AgentIdentityLanguage.current, forHTTPHeaderField: "Accept-Language")
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.message(String(localized: "应用资料暂不可用。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            let result = try JSONDecoder().decode(MomentResources.self, from: data)
            guard result.appCode == "linko-family-ios" else { throw APIError.message(String(localized: "应用资料来源不正确。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            resources = result; resourceError = nil
        } catch { resourceError = momentDisplayError(error) }
    }
}

private struct MomentTestInvitationView: View {
    @StateObject private var atlasIdentity = AgentIdentitySession(
        origin: URL(string: "https://home.ai.impx.net")!,
        callback: URL(string: "linkofamily://login-complete/")!,
        keychainService: "net.impx.happylife.atlasShareIdentity")
    @State private var invitation: Invitation?
    @State private var details: Details?
    @State private var busy = false
    @State private var error: String?
    @State private var copied = false

    private struct Invitation: Decodable { let url: URL; let title: String }
    private struct Details: Decodable { let title: String; let description: String }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 30)).foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(.teal.gradient, in: RoundedRectangle(cornerRadius: 18))
                Text(details?.title ?? String(localized: "专属测试邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.title2.bold())
                Text(details?.description ?? String(localized: "正在读取邀请活动…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

                if let invitation {
                    VStack(spacing: 10) {
                        if let image = qrImage(invitation.url) {
                            Image(uiImage: image).interpolation(.none).resizable()
                                .frame(width: 184, height: 184).padding(8)
                                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                                .accessibilityLabel(String(localized: "邀请链接二维码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        }
                        Text(String(localized: "扫码打开邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.headline)
                        Link(destination: invitation.url) {
                            Text(invitation.url.absoluteString).font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.accessibilityIdentifier("invitationLink")
                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.url = invitation.url
                                copied = true
                            } label: { Label(copied ? String(localized: "已复制", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "复制链接", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: copied ? "checkmark" : "doc.on.doc") }
                                .buttonStyle(.bordered)
                            ShareLink(item: invitation.url, subject: Text(String(localized: "\(invitation.title) 测试邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))) {
                                Label(String(localized: "分享邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                } else if busy { ProgressView(String(localized: "正在生成邀请链接…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }

                Button(invitation == nil ? (atlasIdentity.isAuthenticated ? String(localized: "生成邀请链接", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "登录并生成邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) : String(localized: "生成新链接", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    Task { await create() }
                }.disabled(busy).buttonStyle(.bordered)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding(14).frame(maxWidth: 500).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color.teal.opacity(0.06))
        .navigationTitle(String(localized: "专属测试邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
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
                throw APIError.message(String(localized: "此应用暂未配置测试邀请。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            details = try JSONDecoder().decode(Details.self, from: data)
        } catch { self.error = momentDisplayError(error) }
    }

    private func create() async {
        guard !busy else { return }
        busy = true; error = nil; copied = false
        defer { busy = false }
        do {
            if !atlasIdentity.isAuthenticated { try await atlasIdentity.login() }
            guard let token = try await atlasIdentity.validAccessToken() else {
                throw APIError.message(String(localized: "请先登录用户中心。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            var request = URLRequest(url: URL(string: "https://home.ai.impx.net/api/marketplace/apps/linko-family-ios/share-links")!)
            request.setValue(AgentIdentityLanguage.current, forHTTPHeaderField: "Accept-Language")
            request.httpMethod = "POST"; request.timeoutInterval = 20
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw APIError.message(String(localized: "生成邀请失败，请稍后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            let result = try JSONDecoder().decode(Invitation.self, from: data)
            guard result.url.scheme == "https", result.url.host == "home.ai.impx.net",
                  result.url.path.range(of: "^/invite/[A-Za-z0-9_-]{16,48}$", options: .regularExpression) != nil,
                  result.url.query == nil, result.url.fragment == nil else {
                throw APIError.message(String(localized: "邀请地址无效。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            invitation = result
        } catch { self.error = momentDisplayError(error) }
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
            Section(String(localized: "活动与照片", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                Text(String(localized: "在“活动”创建或加入共同活动，收藏到自己的空间，并与成员分享照片和打卡。访问别人分享的原图时，提供照片的成员需要打开 App 完成传输。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            Section(String(localized: "家庭与成长", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                Text(String(localized: "在“群组”管理家庭成员、奖励审批和积分记录；在“我的”维护族谱、家庭成员及设备权限。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            Section(String(localized: "账号与支持", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                Text(String(localized: "登录由用户中心提供。遇到问题可在“我的”中的“心愿墙与意见墙”提交反馈。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
        }
        .navigationTitle(String(localized: "使用帮助", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
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
            if loading && roster == nil { ProgressView(String(localized: "正在读取成员…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            if let roster {
                Section(String(localized: "人类成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    ForEach(roster.humans) { member($0, symbol: "person.crop.circle.fill") }
                    if roster.humans.isEmpty { Text(String(localized: "暂无公开成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
                }
                Section(String(localized: "智能体成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    ForEach(roster.agents) { member($0, symbol: "cpu.fill") }
                    if roster.agents.isEmpty { Text(String(localized: "暂无公开成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
                }
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button(String(localized: "重试", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await refresh() } }
                }
            }
        }
        .navigationTitle(String(localized: "同行共创成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            var request = URLRequest(url: URL(string: "https://home.ai.impx.net/api/projects/family-reward/members")!)
            request.setValue(AgentIdentityLanguage.current, forHTTPHeaderField: "Accept-Language")
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw APIError.message(String(localized: "成员资料暂不可用。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            let value = try JSONDecoder().decode(Roster.self, from: data)
            guard value.projectCode == "family-reward" else { throw APIError.message(String(localized: "成员资料来源不正确。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            roster = value
        } catch { self.error = momentDisplayError(error) }
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
                    Section(String(localized: "授权码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Text(receipt.text("code")).font(.largeTitle.monospacedDigit()).textSelection(.enabled); Text(String(localized: "有效期至 ", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) + localDateText(receipt.text("expiresAt"))).font(.caption); Text(String(localized: "仅向你要绑定的孩子提供此授权码。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.footnote) }
                } else if saved { Section { Label(String(localized: "已保存", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "checkmark.circle.fill").foregroundStyle(.teal) } }
                else {
                    ForEach(spec.fields) { field in
                        TextField(field.title, text: Binding(get: { values[field.key] ?? field.initial }, set: { values[field.key] = $0 }))
                            .keyboardType(field.numeric ? .numbersAndPunctuation : .default)
                    }
                    if spec.scansWatchCode {
                        Button(String(localized: "扫描手表二维码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "qrcode.viewfinder") { scanning = true }.disabled(saving)
                    }
                    if spec.fields.isEmpty { Text(String(localized: "确认后生成临时授权码，有效期 10 分钟。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button(saving ? String(localized: "正在提交…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "确认", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await save() } }.disabled(saving || !valid)
                }
            }.readablePage(maxWidth: 720).sheet(isPresented: $scanning) {
                WatchCodeScanner { code in values["code"] = code; error = nil }
            }.navigationTitle(spec.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(saved ? String(localized: "完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { dismiss() }.disabled(saving) } }.interactiveDismissDisabled(saving)
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
            guard let code = WatchPairingCode.parse(values["code"] ?? "") else { error = String(localized: "请输入手表上显示的 8 位设备码。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return }
            body["code"] = code
        }
        do {
            let result = try await store.call(spec.path, method: spec.method, body: body)
            saved = true
            if spec.showsReceipt { receipt = Record(fields: result as? [String: Any] ?? [:]) }
            await store.load()
            if !spec.showsReceipt { dismiss() }
        } catch { self.error = momentDisplayError(error) + String(localized: " 如网络中断，请先检查记录再重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }
}
struct RewardEditor: View {
    @ObservedObject var store: FamilyStore
    let child: Record
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var description = ""
    @State private var category = String(localized: "日常", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
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
                    Picker(String(localized: "类型", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $kind) { Text(String(localized: "积分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("points"); Text(String(localized: "零用钱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("cash"); Text(String(localized: "物品", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("items") }
                    Picker(String(localized: "方向", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $direction) { Text(String(localized: "奖励", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("+"); Text(String(localized: "扣除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("-") }.pickerStyle(.segmented)
                    if kind == "items" { TextField(String(localized: "物品名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $item) } else { TextField(String(localized: "数量（大于 0）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $amount).keyboardType(.decimalPad) }
                    TextField(String(localized: "记录内容", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $description); TextField(String(localized: "类别", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $category)
                    DatePicker(String(localized: "日期（当地日历）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $date, displayedComponents: .date).environment(\.timeZone, TimeZone.current)
                    if kind == "points" {
                        Menu(String(localized: "使用现有规则", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { ForEach(store.rules) { rule in Button(rule.text("name")) { amount = String(abs(rule.number("points"))); direction = rule.number("points") < 0 ? "-" : "+"; description = rule.text("name"); category = rule.text("category") } } }
                    }
                }.disabled(attempted || saving)
                if let error { Text(error).foregroundStyle(.red) }
                Button(saving ? String(localized: "正在保存…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : attempted ? String(localized: "核对并重试同一笔记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "保存记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await save() } }.disabled(saving || !valid)
                Text(String(localized: "重试会使用同一个记录编号，避免重复记分。提交后请以服务端记录为准。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.footnote).foregroundStyle(.secondary)
            }.readablePage(maxWidth: 720).navigationTitle(String(localized: "记录奖励", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "关闭", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { dismiss() }.disabled(saving) } }.interactiveDismissDisabled(saving)
        }
    }
    private var valid: Bool { !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !category.isEmpty && (kind == "items" ? !item.isEmpty : (Double(amount)?.isFinite == true && (Double(amount) ?? 0) > 0)) }
    private func save() async {
        saving = true; error = nil
        defer { saving = false }
        if requestBody == nil {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = .current; formatter.locale = Locale(identifier: "en_US_POSIX")
            requestBody = ["child_id": child.id, "type": kind, "direction": direction, "points": kind == "points" ? Double(amount) ?? 0 : 0, "cash_cny": kind == "cash" ? Double(amount) ?? 0 : 0, "items": item, "description": description, "category": category, "date": formatter.string(from: date), "idempotency_key": idempotency]
        }
        attempted = true
        do { _ = try await store.call("/api/transactions", method: "POST", body: requestBody); try await store.refreshBalancesAndLedger(); dismiss() }
        catch { self.error = momentDisplayError(error) + String(localized: " 可重试同一笔记录，或关闭后在记录页核对。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
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
            if loading { ProgressView(String(localized: "正在加载…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            if let error { Text(error).foregroundStyle(.red); Button(String(localized: "重试", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await load() } } }
            if let object {
                if mode == .invite {
                    Text(object.text("familyGroupName")).font(.headline)
                    Text(object.text("inviteCode")).font(.title.monospacedDigit()).textSelection(.enabled)
                    if let url = URL(string: object.text("inviteUrl")), url.scheme == "https" {
                        let label = String(localized: "分享家庭邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
                        MomentShareLink(url: url, title: label, label: label)
                    }
                } else if mode == .subscription {
                    Section(String(localized: "当前权益", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        if let fields = object.fields["subscription"] as? [String: Any] {
                            let current = Record(fields: fields)
                            Text(current.text("planCode") == "vip-home-plus" ? String(localized: "VIP 家庭+", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : current.text("planCode"))
                                .font(.headline)
                            Text(String(localized: "有效至 \(String(current.text("expiresAt").prefix(10)))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "标准版 · 基础功能已包含", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        }
                    }
                    Section(String(localized: "套餐功能", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        Label(String(localized: "基础功能", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) + (object.flag("standardIncluded") ? String(localized: " · 已包含", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: " · 未开通", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))), systemImage: "checkmark.circle")
                        Label(String(localized: "VIP 表盘", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) + (object.flag("vipWatchFaces") ? String(localized: " · 已开通", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: " · 未开通", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))), systemImage: "checkmark.seal")
                    }
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 8) {
                    switch mode {
                    case .devices:
                        Text(row.text("deviceName")).font(.headline); Text(row.flag("active") ? String(localized: "已连接", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "已解绑", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary)
                        Text(String(localized: "最近在线：", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) + localDateText(row.text("lastSeenAt"))).font(.caption)
                        if row.flag("active") && childID != nil {
                            Button(String(localized: "解除绑定", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { deviceToUnbind = row }
                                .disabled(unbinding)
                        }
                    case .moments:
                        Text(row.text("content")); Text(row.text("parentDisplayName") + " · " + localDateText(row.text("createdAt"))).font(.caption).foregroundStyle(.secondary)
                    case .reports:
                        Text(row.text("subjectName")).font(.headline); Text(row.text("periodStart") + " — " + row.text("periodEnd")).font(.caption)
                        Text(row.text("praise")); Text(row.text("changeSummary")); Text(row.text("nextStep")).foregroundStyle(.secondary)
                    case .friends:
                        Text(row.text("name")).font(.headline); Text(row.amount("score") + String(localized: " 积分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    default: EmptyView()
                    }
                }.padding(.vertical, 5)
            }
            if !loading && error == nil && rows.isEmpty && mode != .invite && mode != .subscription { Text(String(localized: "暂无记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
        }.readablePage().navigationTitle(title).task { await load() }.refreshable { await load() }
            .confirmationDialog(String(localized: "解除这只手表与当前孩子的绑定？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(
                get: { deviceToUnbind != nil }, set: { if !$0 { deviceToUnbind = nil } }), titleVisibility: .visible) {
                Button(String(localized: "解除绑定", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) {
                    guard let device = deviceToUnbind else { return }
                    deviceToUnbind = nil
                    Task { await unbind(device) }
                }
                Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .cancel) { deviceToUnbind = nil }
            } message: { Text(String(localized: "解绑后手表将退出当前孩子，需重新扫码才能使用。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
    }
    private func unbind(_ device: Record) async {
        guard let childID else { return }
        unbinding = true; defer { unbinding = false }
        do {
            _ = try await store.call("/api/children/\(childID)/devices/\(device.id)?\(store.scope)", method: "DELETE")
            await load()
        } catch { self.error = momentDisplayError(error) }
    }
    private func load() async {
        loading = true; error = nil; rows = []; object = nil
        defer { loading = false }
        do {
            guard let result = try await store.call(path) as? [String: Any] else { throw APIError.message(String(localized: "响应格式不正确。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            object = Record(fields: result)
            let key: String? = switch mode { case .devices: "devices"; case .moments: "moments"; case .reports: "reports"; case .friends: "friends"; default: nil }
            if let key { rows = try Record.list(result[key] as Any) }
        } catch { self.error = momentDisplayError(error) }
    }
}
func localDateText(_ raw: String) -> String {
    let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    guard let date else { return raw }
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: AgentIdentityLanguage.current); formatter.timeZone = .current; formatter.dateStyle = .medium; formatter.timeStyle = .short
    return String(localized: "\(formatter.string(from: date))（当地时间）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
}

private var connectionKinds: [(String, String)] { [
    ("special_time", String(localized: "孩子决定的十分钟", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))), ("listen", String(localized: "先听我说", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))),
    ("reconnect", String(localized: "吵架后的重连", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))), ("meeting", String(localized: "家庭小会议", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
] }

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
                Text(String(localized: "听见彼此，留出陪伴时间。互动记录不计积分、不评分。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    .font(.footnote).foregroundStyle(.secondary)
                Picker(String(localized: "孩子", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $childID) {
                    Text(String(localized: "请选择", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag(0)
                    ForEach(store.children) { child in Text(child.text("name")).tag(child.id) }
                }
                Picker(String(localized: "互动方式", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $kind) {
                    ForEach(connectionKinds, id: \.0) { item in Text(item.1).tag(item.0) }
                }
                if kind == "listen" {
                    Picker(String(localized: "希望怎样被倾听", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $intent) {
                        Text(String(localized: "只想说说", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("share")
                        Text(String(localized: "想要安慰", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("comfort")
                        Text(String(localized: "一起想办法", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("ideas")
                    }
                }
                TextField(String(localized: "这次想聊什么或一起做什么", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $title).onChange(of: title) { _, _ in requestID = UUID() }
                Button(String(localized: "发起互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    Task { await write("/api/family-connections", [
                        "childId": childID, "kind": kind, "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                        "intent": kind == "listen" ? intent : "", "requestId": requestID.uuidString
                    ]) { title = ""; requestID = UUID() } }
                }.disabled(busy || childID == 0 || title.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            } header: { Text(String(localized: "开始一段互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            Section(String(localized: "互动记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                if threads.isEmpty { Text(String(localized: "暂无记录，孩子也可以从手表发起。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
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
        }.readablePage().navigationTitle(String(localized: "亲子互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).refreshable { await load() }
            .task { if childID == 0 { childID = store.children.first?.id ?? 0 }; await load() }
            .disabled(busy)
            .alert(String(localized: "操作提示", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(String(localized: "知道了", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { error = nil }
            } message: { Text(error ?? "") }
    }
    private func load() async {
        do {
            let response = try await store.call("/api/family-connections")
            threads = try Record.list(response, key: "threads")
            entries = try Record.list(response, key: "entries")
        } catch { self.error = momentDisplayError(error) }
    }
    private func write(_ path: String, _ body: [String: Any], done: @escaping () -> Void) async {
        busy = true; defer { busy = false }
        do { _ = try await store.call(path, method: "POST", body: body); done(); await load() }
        catch { self.error = momentDisplayError(error) }
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
                    Text(String(localized: "孩子希望：\(["share": String(localized: "只想说说", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), "comfort": String(localized: "想要安慰", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), "ideas": String(localized: "一起想办法", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))][current.text("intent")] ?? String(localized: "先听听", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                }
                if current.has("scheduledAt") { Text(String(localized: "约定时间：\(localDateText(current.text("scheduledAt")))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                if !current.text("trialPlan").isEmpty { Text(String(localized: "本周试行：\(current.text("trialPlan"))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            }
            Section(String(localized: "彼此说的话", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                ForEach(shownEntries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(localized: "\(entry.text("authorRole") == "child" ? String(localized: "孩子", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "家长", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) · \(entry.text("type"))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(entry.text("content"))
                    }
                }
            }
            if active {
                Section(String(localized: "记录想法", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    Picker(String(localized: "内容", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $type) {
                        Text(String(localized: "想说的话", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("message")
                        if current.text("kind") == "reconnect" { Text(String(localized: "我的感受", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("feeling"); Text(String(localized: "我的期待", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("hope") }
                        if current.text("kind") == "meeting" { Text(String(localized: "我的提议", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("proposal") }
                        if current.text("status") == "trial" || current.text("kind") == "special_time" { Text(String(localized: "复盘", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("reflection") }
                    }
                    TextField(String(localized: "温和地写下想表达的内容", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $content, axis: .vertical)
                        .lineLimit(2...5).onChange(of: content) { _, _ in requestID = UUID() }
                    Button(String(localized: "发送", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await write("entries", ["type": type, "content": content, "requestId": requestID.uuidString]) { content = ""; requestID = UUID() } } }
                        .disabled(busy || content.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                Section(String(localized: "下一步", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    if current.text("kind") == "special_time" && current.text("status") == "open" {
                        DatePicker(String(localized: "专心陪伴时间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $schedule, in: Date()...Date().addingTimeInterval(90 * 86400))
                        Button(String(localized: "约定时间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await write("transition", ["action": "schedule", "scheduledAt": ISO8601DateFormatter().string(from: schedule)]) {} } }
                    }
                    if current.text("kind") == "meeting" && current.text("status") == "open" {
                        TextField(String(localized: "双方提出想法后，写下本周试行安排", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $plan, axis: .vertical)
                        Button(String(localized: "开始一周试行", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await write("transition", ["action": "start_trial", "plan": plan]) {} } }
                            .disabled(plan.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    }
                    if current.text("kind") == "meeting" && current.text("status") == "trial" {
                        Button(String(localized: "七天后完成复盘", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await write("transition", ["action": "review"]) {} } }
                    } else if current.text("kind") != "meeting" && (current.text("kind") != "special_time" || current.text("status") == "scheduled") {
                        Button(String(localized: "完成互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await write("transition", ["action": "complete"]) {} } }
                    }
                    Button(String(localized: "取消互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { Task { await write("transition", ["action": "cancel"]) {} } }
                }
            }
        }.readablePage().navigationTitle(String(localized: "亲子互动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).disabled(busy).task { await loadLocal() }
            .alert(String(localized: "操作提示", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(String(localized: "知道了", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { error = nil }
            } message: { Text(error ?? "") }
    }
    private func loadLocal() async {
        do {
            let response = try await store.call("/api/family-connections")
            let threads = try Record.list(response, key: "threads")
            let entries = try Record.list(response, key: "entries")
            latest = threads.first { $0.id == thread.id }
            latestEntries = entries.filter { $0.int("connectionId") == thread.id }
        } catch { self.error = momentDisplayError(error) }
    }
    private func write(_ endpoint: String, _ body: [String: Any], done: @escaping () -> Void) async {
        busy = true; defer { busy = false }
        do {
            _ = try await store.call("/api/family-connections/\(current.id)/\(endpoint)", method: "POST", body: body)
            done(); await loadLocal(); await reload()
        } catch { self.error = momentDisplayError(error) }
    }
}

private struct MomentAboutView: View {
    @ObservedObject var store: FamilyStore
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }

    var body: some View {
        List {
            Section(String(localized: "应用介绍", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                Text(String(localized: "Linko Moment 帮助家庭记录生活、分享照片与活动，并一起管理孩子的成长和日常事务。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            Section(String(localized: "版本信息", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                LabeledContent(String(localized: "当前版本", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: Self.version)
                LabeledContent(String(localized: "构建号", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: build)
                NavigationLink { MomentVersionView() } label: {
                    Label(String(localized: "版本升级", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "arrow.up.circle")
                }
            }
            Section(String(localized: "APP 备案号", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                Link(destination: URL(string: "https://beian.miit.gov.cn/")!) { Text(verbatim: "\u{95FD}ICP\u{5907}2024055146\u{53F7}-4A") }
            }
            Section {
                NavigationLink { MomentTeamMembersView() } label: {
                    Label(String(localized: "同行共创", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "person.3")
                }
                NavigationLink { MomentTestInvitationView() } label: {
                    Label(String(localized: "测试邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "square.and.arrow.up")
                }
                NavigationLink {
                    FeedbackWallView(identity: store.identity)
                } label: {
                    Label(String(localized: "意见反馈", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "bubble.left.and.bubble.right")
                }
            }
        }.navigationTitle(String(localized: "关于我们", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
    }
}

private struct MomentVersionView: View {
    var body: some View {
        AppleApplicationUpdateView(testFlight: URL(string: "https://testflight.apple.com/join/dAHHKXM7"))
    }
}

func momentDisplayError(_ error: Error) -> String {
    let locale = Locale(identifier: AgentIdentityLanguage.current)
    if case APIError.invalidData(let key) = error {
        if let key { return String(localized: "服务返回的\(key)数据格式不正确。", bundle: AgentIdentityLanguage.appBundle(), locale: locale) }
        return String(localized: "服务返回的数据格式不正确。", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
    }
    if error is CancellationError { return String(localized: "操作已取消。", bundle: AgentIdentityLanguage.appBundle(), locale: locale) }
    if error is URLError { return String(localized: "网络连接失败，请检查网络后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: locale) }
    if let known = error as? LocalizedError, let message = known.errorDescription { return message }
    return String(localized: "操作未能完成，请稍后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
}

@MainActor private func momentSyncLanguage(_ language: AgentIdentityLanguageStore, identity: AgentIdentitySession) async {
    if identity.isAuthenticated && identity.accountIdentifier == nil {
        _ = try? await identity.userInfo(authority: URL(string: "https://auth.ai.xmkurt.com")!)
    }
    guard !Task.isCancelled else { return }
    language.accountDidChange(identity.isAuthenticated ? identity.accountIdentifier : nil)
    await language.refresh()
}

private struct MomentSectionSettings: View {
    @AppStorage("moment.sections.dining") private var dining = true
    @AppStorage("moment.sections.growth") private var growth = false
    @AppStorage("moment.sections.activities") private var activities = true
    @AppStorage("moment.sections.exercise") private var exercise = true
    var body: some View {
        Form {
            Toggle(String(localized: "干饭", bundle: AgentIdentityLanguage.appBundle()), isOn: $dining)
            Toggle(String(localized: "带娃", bundle: AgentIdentityLanguage.appBundle()), isOn: $growth)
            Toggle(String(localized: "活动", bundle: AgentIdentityLanguage.appBundle()), isOn: $activities)
            Toggle(String(localized: "运动", bundle: AgentIdentityLanguage.appBundle()), isOn: $exercise)
        }.navigationTitle(String(localized: "栏目启用", bundle: AgentIdentityLanguage.appBundle()))
    }
}
