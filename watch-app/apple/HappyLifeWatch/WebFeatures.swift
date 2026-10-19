import SwiftUI
import CoreLocation
import PhotosUI

enum WatchTheme {
    static func colors(_ face: String) -> Color {
        switch face {
        case "hellokitty", "flowers": return Color(red: 0.35, green: 0.08, blue: 0.22)
        case "starlight", "snow": return Color(red: 0.08, green: 0.22, blue: 0.38)
        case "space", "night", "meteor": return Color(red: 0.15, green: 0.10, blue: 0.32)
        case "rainbow", "pixel": return Color(red: 0.32, green: 0.20, blue: 0.08)
        default: return Color(red: 0.06, green: 0.23, blue: 0.13)
        }
    }
}

struct WatchSocialSpacesView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var name = ""
    @State private var editing: WatchSocialSpace?
    @State private var deleting: WatchSocialSpace?
    @State private var actionError: String?
    @State private var invitations: [[String: Any]] = []
    var body: some View {
        List {
            Text("通过配对的 iPhone 使用已登录账号管理活动。")
                .font(.footnote).foregroundStyle(.secondary)
            if store.socialLoading { ProgressView("读取中") }
            if let error = store.socialError { Text(error).foregroundStyle(.red).font(.footnote) }
            if let actionError { Text(actionError).foregroundStyle(.red).font(.footnote) }
            if !invitations.isEmpty {
                Section("待确认邀请") {
                    ForEach(invitations.indices, id: \.self) { index in
                        let item = invitations[index]
                        Button("加入 \(item["title"] as? String ?? "活动")") {
                            Task {
                                await run("acceptInvitation", spaceID: item["tenantId"] as? String,
                                          activityID: item["activityId"] as? String)
                            }
                        }
                    }
                }
            }
            Section("生活空间") {
            ForEach(store.socialSpaces) { space in
                NavigationLink(space.name, destination: WatchSocialActivitiesView(space: space))
                if space.owner {
                    Button("修改“\(space.name)”名称") { name = space.name; editing = space }
                    Button("删除“\(space.name)”", role: .destructive) { deleting = space }
                }
            }
            if store.socialSpaces.isEmpty && !store.socialLoading && store.socialError == nil {
                Text("暂无空间")
            }
            TextField("新空间名称", text: $name)
            Button("创建空间") { Task { await run("createSpace", fields: ["name": name]) } }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button("刷新") { Task { await store.loadSocialSpaces() } }
        }
        .navigationTitle("活动空间")
        .task { await refresh() }
        .alert("修改空间名称", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("空间名称", text: $name)
            Button("保存") {
                guard let space = editing else { return }
                Task { await run("renameSpace", spaceID: space.id, fields: ["name": name]) }
            }
            Button("取消", role: .cancel) { editing = nil }
        }
        .confirmationDialog("确认删除空间？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("确认删除", role: .destructive) {
                guard let space = deleting else { return }
                Task { await run("deleteSpace", spaceID: space.id) }
            }
        } message: { Text("仅可删除没有活动、其他成员或分享记录的空间。") }
    }

    private func refresh() async {
        await store.loadSocialSpaces()
        do {
            let reply = try await store.socialRequest("invitations")
            invitations = reply["items"] as? [[String: Any]] ?? []
        } catch { actionError = error.localizedDescription }
    }

    private func run(_ action: String, spaceID: String? = nil, activityID: String? = nil,
                     fields: [String: Any] = [:]) async {
        actionError = nil
        do {
            _ = try await store.socialRequest(action, spaceID: spaceID, activityID: activityID, fields: fields)
            name = ""; editing = nil; deleting = nil
            await refresh()
        } catch { actionError = error.localizedDescription }
    }
}

struct WatchSocialActivitiesView: View {
    @EnvironmentObject private var store: WatchStore
    let space: WatchSocialSpace
    @State private var title = ""
    @State private var editing: WatchSocialActivity?
    @State private var deleting: WatchSocialActivity?
    @State private var actionError: String?
    var body: some View {
        List {
            if store.socialLoading { ProgressView("读取中") }
            if let error = store.socialError { Text(error).foregroundStyle(.red).font(.footnote) }
            if let actionError { Text(actionError).foregroundStyle(.red).font(.footnote) }
            ForEach(store.socialActivities) { activity in
                NavigationLink(activity.title, destination: WatchSocialPhotosView(spaceID: activity.sourceTenantId, activity: activity))
                if activity.canEdit {
                    Button("修改“\(activity.title)”名称") { title = activity.title; editing = activity }
                    Button("删除“\(activity.title)”", role: .destructive) { deleting = activity }
                }
            }
            if store.socialActivities.isEmpty && !store.socialLoading && store.socialError == nil {
                Text("这个空间暂无活动")
            }
            TextField("新活动名称", text: $title)
            Button("创建活动") { Task { await run("createActivity", fields: ["title": title]) } }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("刷新") { Task { await store.loadSocialActivities(spaceID: space.id) } }
        }
        .navigationTitle(space.name)
        .task { await store.loadSocialActivities(spaceID: space.id) }
        .alert("修改活动名称", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("活动名称", text: $title)
            Button("保存") {
                guard let activity = editing else { return }
                Task { await run("renameActivity", spaceID: activity.sourceTenantId, activityID: activity.id, fields: ["title": title]) }
            }
            Button("取消", role: .cancel) { editing = nil }
        }
        .confirmationDialog("确认删除活动？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("确认删除", role: .destructive) {
                guard let activity = deleting else { return }
                Task { await run("deleteActivity", spaceID: activity.sourceTenantId, activityID: activity.id) }
            }
        } message: { Text("仅可删除没有其他成员、照片或日常记录的活动。") }
    }

    private func run(_ action: String, spaceID: String? = nil, activityID: String? = nil, fields: [String: Any] = [:]) async {
        actionError = nil
        do {
            _ = try await store.socialRequest(action, spaceID: spaceID ?? space.id, activityID: activityID, fields: fields)
            title = ""; editing = nil; deleting = nil
            await store.loadSocialActivities(spaceID: space.id)
        } catch { actionError = error.localizedDescription }
    }
}

struct WatchSocialPhotosView: View {
    let spaceID: String
    let activity: WatchSocialActivity
    var body: some View {
        List {
            NavigationLink("共享照片", destination: WatchSocialAlbumView(spaceID: spaceID, activity: activity))
            NavigationLink("生活分享", destination: WatchSocialMomentsView(spaceID: spaceID, activity: activity))
            NavigationLink("活动打卡", destination: WatchSocialCheckInsView(spaceID: spaceID, activity: activity))
            NavigationLink("成员与邀请", destination: WatchSocialMembersView(spaceID: spaceID, activity: activity))
        }
        .navigationTitle(activity.title)
    }
}

struct WatchSocialAlbumView: View {
    @EnvironmentObject private var store: WatchStore
    let spaceID: String
    let activity: WatchSocialActivity
    @State private var deleting: WatchSocialPhoto?
    @State private var actionError: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var sharing = false
    var body: some View {
        List {
            PhotosPicker("共享手表照片", selection: $selectedPhoto, matching: .images)
                .disabled(sharing)
            Text("照片会以配对 iPhone 的账号共享；原图留在 iPhone，获取原图时请保持 iPhone 上的 Linko Moment 打开。")
                .font(.footnote).foregroundStyle(.secondary)
            if sharing { ProgressView("共享中") }
            if store.socialLoading { ProgressView("读取中") }
            if let error = store.socialError { Text(error).foregroundStyle(.red).font(.footnote) }
            if let actionError { Text(actionError).foregroundStyle(.red).font(.footnote) }
            ForEach(store.socialPhotos) { photo in
                if photo.available {
                    NavigationLink(destination: WatchSocialPreviewView(spaceID: spaceID,
                                                                        activityID: activity.id, photo: photo)) {
                        VStack(alignment: .leading) {
                            Text(photo.name).lineLimit(2)
                            if !photo.author.isEmpty { Text(photo.author).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                } else {
                    VStack(alignment: .leading) {
                        Text(photo.name).lineLimit(2)
                        Text("暂无预览，请在 iPhone 查看").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if photo.canDelete {
                    Button("删除我的“\(photo.name)”", role: .destructive) { deleting = photo }
                }
            }
            if store.socialPhotos.isEmpty && !store.socialLoading && store.socialError == nil {
                Text("这场活动还没有照片")
            }
            if store.socialPhotosHasMore {
                Button("加载更多照片") {
                    Task { await store.loadSocialPhotos(spaceID: spaceID, activityID: activity.id, more: true) }
                }.disabled(store.socialLoading)
            }
            Button("刷新") { Task { await store.loadSocialPhotos(spaceID: spaceID, activityID: activity.id) } }
        }
        .navigationTitle(activity.title)
        .task { await store.loadSocialPhotos(spaceID: spaceID, activityID: activity.id) }
        .onChange(of: selectedPhoto) { _, selected in
            guard let selected else { return }
            Task {
                sharing = true; actionError = nil
                defer { sharing = false; selectedPhoto = nil }
                do {
                    guard let data = try await selected.loadTransferable(type: Data.self),
                          let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else {
                        throw APIError(status: 0, message: "无法读取所选照片。")
                    }
                    try await store.shareSocialPhoto(jpeg, spaceID: spaceID, activityID: activity.id)
                    await store.loadSocialPhotos(spaceID: spaceID, activityID: activity.id)
                } catch { actionError = error.localizedDescription }
            }
        }
        .confirmationDialog("删除共享照片？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("确认删除", role: .destructive) {
                guard let photo = deleting else { return }
                Task {
                    do {
                        _ = try await store.socialRequest("deletePhoto", spaceID: spaceID, activityID: activity.id,
                                                          fields: ["photoId": photo.id])
                        deleting = nil
                        await store.loadSocialPhotos(spaceID: spaceID, activityID: activity.id)
                    } catch { actionError = error.localizedDescription }
                }
            }
        } message: { Text("照片会从此活动撤销共享。") }
    }
}

struct WatchSocialMomentsView: View {
    @EnvironmentObject private var store: WatchStore
    let spaceID: String
    let activity: WatchSocialActivity
    @State private var rows: [[String: Any]] = []
    @State private var draft = ""
    @State private var requestID = UUID()
    @State private var deleting: String?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            if loading { ProgressView("处理中") }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            TextField("分享今天的事", text: $draft)
            Button("发布日常") { Task { await publish() } }
                .disabled(loading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 1000)
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                VStack(alignment: .leading) {
                    Text(row["author"] as? String ?? "").font(.footnote).foregroundStyle(.secondary)
                    Text(row["text"] as? String ?? "")
                }
                if row["canDelete"] as? Bool == true {
                    Button("删除我的记录", role: .destructive) { deleting = row["id"] as? String }
                }
            }
            if rows.isEmpty && !loading && error == nil { Text("还没有分享的日常") }
            Button("刷新") { Task { await load() } }
        }
        .navigationTitle("生活分享")
        .task { await load() }
        .confirmationDialog("删除这条日常？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("确认删除", role: .destructive) {
                guard let id = deleting else { return }
                Task { await delete(id) }
            }
        }
    }

    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let reply = try await store.socialRequest("moments", spaceID: spaceID, activityID: activity.id)
            rows = reply["items"] as? [[String: Any]] ?? []
        } catch { self.error = error.localizedDescription }
    }
    private func publish() async {
        loading = true; error = nil; defer { loading = false }
        do {
            _ = try await store.socialRequest("createMoment", spaceID: spaceID, activityID: activity.id,
                                              fields: ["text": draft, "requestId": requestID.uuidString])
            draft = ""; requestID = UUID()
            let reply = try await store.socialRequest("moments", spaceID: spaceID, activityID: activity.id)
            rows = reply["items"] as? [[String: Any]] ?? []
        } catch { self.error = error.localizedDescription }
    }
    private func delete(_ id: String) async {
        loading = true; error = nil; defer { loading = false }
        do {
            _ = try await store.socialRequest("deleteMoment", spaceID: spaceID, activityID: activity.id,
                                              fields: ["itemId": id])
            deleting = nil
            let reply = try await store.socialRequest("moments", spaceID: spaceID, activityID: activity.id)
            rows = reply["items"] as? [[String: Any]] ?? []
        } catch { self.error = error.localizedDescription }
    }
}

struct WatchSocialCheckInsView: View {
    @EnvironmentObject private var store: WatchStore
    @StateObject private var locator = WatchSocialLocator()
    let spaceID: String
    let activity: WatchSocialActivity
    @State private var rows: [[String: Any]] = []
    @State private var note = ""
    @State private var requestID = UUID()
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            if loading { ProgressView("处理中") }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            if let error = locator.error { Text(error).foregroundStyle(.red).font(.footnote) }
            if locator.fetching { ProgressView("定位中") }
            if let location = locator.location {
                Text(locator.address).font(.footnote)
                Text(String(format: "海拔 %.1f 米", location.altitude)).font(.footnote)
                TextField("备注（默认地址）", text: $note)
                Button("确认打卡") { Task { await create() } }
                    .disabled(loading || note.count > 1000)
            }
            Button("获取当前位置") { locator.locate() }.disabled(locator.fetching || loading)
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                VStack(alignment: .leading) {
                    Text(row["author"] as? String ?? "").font(.footnote)
                    Text(row["note"] as? String ?? "")
                    Text("\(row["address"] as? String ?? "") · 海拔 \(String(format: "%.1f", row["altitudeMeters"] as? Double ?? 0)) 米")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if rows.isEmpty && !loading && error == nil { Text("还没有打卡记录") }
            Button("刷新") { Task { await load() } }
        }
        .navigationTitle("活动打卡")
        .task { await load() }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let reply = try await store.socialRequest("checkins", spaceID: spaceID, activityID: activity.id)
            rows = reply["items"] as? [[String: Any]] ?? []
        } catch { self.error = error.localizedDescription }
    }
    private func create() async {
        guard let location = locator.location, !locator.fetching else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            _ = try await store.socialRequest("createCheckIn", spaceID: spaceID, activityID: activity.id,
                fields: ["requestId": requestID.uuidString, "latitude": location.coordinate.latitude,
                         "longitude": location.coordinate.longitude, "altitudeMeters": location.altitude,
                         "address": locator.address, "note": note])
            requestID = UUID(); note = ""; locator.clear()
            let reply = try await store.socialRequest("checkins", spaceID: spaceID, activityID: activity.id)
            rows = reply["items"] as? [[String: Any]] ?? []
        } catch { self.error = error.localizedDescription }
    }
}

struct WatchSocialMembersView: View {
    @EnvironmentObject private var store: WatchStore
    let spaceID: String
    let activity: WatchSocialActivity
    @State private var members: [[String: Any]] = []
    @State private var username = ""
    @State private var inviteURL: URL?
    @State private var error: String?
    @State private var notice: String?
    @State private var loading = false
    var body: some View {
        List {
            if loading { ProgressView("处理中") }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            if let notice { Text(notice).font(.footnote) }
            Section("邀请参加") {
                TextField("用户中心用户名", text: $username)
                Button("发送邀请") { Task { await invite() } }
                    .disabled(loading || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("生成邀请链接") { Task { await link() } }.disabled(loading)
                if let inviteURL { ShareLink("分享邀请链接", item: inviteURL) }
            }
            Section("活动成员") {
                ForEach(members.indices, id: \.self) { index in
                    Text(members[index]["name"] as? String ?? "")
                }
                if members.isEmpty && !loading && error == nil { Text("暂无成员") }
            }
            Button("刷新") { Task { await load() } }
        }
        .navigationTitle("成员与邀请")
        .task { await load() }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let reply = try await store.socialRequest("members", spaceID: spaceID, activityID: activity.id)
            members = reply["items"] as? [[String: Any]] ?? []
        } catch { self.error = error.localizedDescription }
    }
    private func invite() async {
        loading = true; error = nil; notice = nil; defer { loading = false }
        do {
            _ = try await store.socialRequest("inviteUsername", spaceID: spaceID, activityID: activity.id,
                                              fields: ["username": username])
            username = ""; notice = "邀请已发送，等待对方确认。"
        } catch { self.error = error.localizedDescription }
    }
    private func link() async {
        loading = true; error = nil; notice = nil; defer { loading = false }
        do {
            let reply = try await store.socialRequest("inviteLink", spaceID: spaceID, activityID: activity.id)
            guard let value = reply["url"] as? String, let url = URL(string: value) else {
                throw APIError(status: 0, message: "邀请链接无效。")
            }
            inviteURL = url; notice = "链接七天内有效，请只分享给要邀请的人。"
        } catch { self.error = error.localizedDescription }
    }
}

private final class WatchSocialLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var address = ""
    @Published var fetching = false
    @Published var error: String?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    func clear() { location = nil; address = "" }
    func locate() {
        clear(); error = nil; fetching = true
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: fetching = false; error = "请在手表设置中允许位置访问。"
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard fetching else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: fetching = false; error = "位置访问未获授权。"
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard fetching else { return }
        guard let current = locations.last(where: { $0.horizontalAccuracy >= 0 && $0.verticalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 120 }) else {
            fetching = false; error = "没有获取到有效的位置和海拔，请重试。"; return
        }
        geocoder.reverseGeocodeLocation(current) { [weak self] placemarks, _ in
            guard let self else { return }
            self.address = placemarks?.first?.name ?? String(format: "%.6f, %.6f", current.coordinate.latitude, current.coordinate.longitude)
            self.location = current
            self.fetching = false
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fetching = false; self.error = "定位失败：\(error.localizedDescription)"
    }
}

struct WatchSocialPreviewView: View {
    @EnvironmentObject private var store: WatchStore
    let spaceID: String
    let activityID: String
    let photo: WatchSocialPhoto
    @State private var preview: Data?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let preview, let image = UIImage(data: preview) {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                } else { ProgressView("读取照片") }
                Text(photo.name).font(.footnote).multilineTextAlignment(.center)
            }
        }
        .navigationTitle("照片预览")
        .task {
            do { preview = try await store.socialPreview(spaceID: spaceID, activityID: activityID, photoID: photo.id) }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct FriendsView: View {
    @EnvironmentObject private var store: WatchStore
    var leaderboard = false
    @State private var code = ""
    var body: some View {
        List {
            if !leaderboard {
                Button("生成好友码") { Task { await store.makeFriendCode() } }
                if let friendCode = store.friendCode {
                    Text(friendCode.code).font(.title2.monospacedDigit()).privacySensitive()
                    Text("有效期至 \(beijingTime(friendCode.expiresAt))（北京时间）")
                        .font(.footnote)
                }
                TextField("好友的认证码", text: $code)
                Button("添加好友") {
                    Task { await store.addFriend(code: code); code = "" }
                }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let rows = leaderboard ? (store.friends?.leaderboard ?? []) : (store.friends?.friends ?? [])
            if rows.isEmpty { Text(leaderboard ? "暂无排行" : "暂无好友") }
            ForEach(rows) { friend in
                VStack(alignment: .leading) {
                    Text("\(friend.rank.map { "\($0). " } ?? "")\(friend.name)\(friend.isSelf == true ? " · 我" : "")")
                    Text("\(friend.score.formatted()) 分").foregroundStyle(.green)
                }
            }
            Button("刷新") { Task { await store.loadSection("friends") } }
        }.disabled(store.busy).navigationTitle(leaderboard ? "好友积分榜" : "我的好友")
            .task { await store.loadSection("friends") }
    }

    private func beijingTime(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return "请重新生成好友码" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

struct WarmMomentView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var parentID = 0
    @State private var content = ""
    var body: some View {
        List {
            Text("爸爸妈妈的闪光时刻").font(.headline)
            if store.parents.isEmpty {
                Text("请家长先配置家庭成员")
                Button("重新加载") { Task { await store.loadSection("parents") } }
            } else {
                Picker("想记录谁", selection: $parentID) {
                    Text("请选择").tag(0)
                    ForEach(store.parents) { Text($0.roleLabel).tag($0.id) }
                }
                TextField("发生了什么", text: $content)
                Text("可使用手表系统听写输入，最多 500 字。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("保存暖心时刻") {
                    Task {
                        if await store.saveWarmMoment(parentID: parentID, content: content) { content = "" }
                    }
                }.disabled(parentID == 0 || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.count > 500)
            }
        }.disabled(store.busy).navigationTitle("暖心时刻")
            .task { await store.loadSection("parents") }
    }
}

struct GrowthView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            if let report = store.growth {
                Text(report.praise).font(.headline)
                Text(report.nextStep)
                Text("继续加油，每一点进步都值得被看见。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else { Text(store.busy ? "正在准备今天的鼓励…" : "今天也要开心成长。") }
            Button("刷新") { Task { await store.loadSection("growth") } }
        }.disabled(store.busy).navigationTitle("今日鼓励")
            .task { await store.loadSection("growth") }
    }
}

struct FaceSettingsView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            Text("设置 Linko Moment App 内的主题外观。")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(store.settings?.availableFaces ?? []) { face in
                Button {
                    Task { await store.setFace(face) }
                } label: {
                    HStack {
                        Circle().fill(WatchTheme.colors(face.code)).frame(width: 16, height: 16)
                        Text(face.name + (face.vip ? " · VIP" : ""))
                        if face.code == store.face { Image(systemName: "checkmark") }
                        if !face.available { Image(systemName: "lock") }
                    }
                }.disabled(!face.available)
            }
            Button("刷新") { Task { await store.loadSection("settings") } }
        }.disabled(store.busy).navigationTitle("表盘设置")
            .task { await store.loadSection("settings") }
    }
}
