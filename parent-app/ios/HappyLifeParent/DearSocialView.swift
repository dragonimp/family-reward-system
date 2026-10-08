import SwiftUI

private struct DearRecord: Identifiable {
    let data: [String: Any]
    var id: String { text("id") }
    func text(_ key: String) -> String { data[key] as? String ?? "" }
    func flag(_ key: String) -> Bool { data[key] as? Bool ?? false }
    static func list(_ value: Any) throws -> [DearRecord] {
        guard let values = value as? [[String: Any]] else { throw APIError.message("Linko Social 返回的数据格式不正确。") }
        return values.map { DearRecord(data: $0) }
    }
}

struct DearSocialView: View {
    @ObservedObject var store: FamilyStore
    var showLogout = false
    @State private var spaces: [DearRecord] = []
    @State private var activities: [DearRecord] = []
    @State private var photos: [DearRecord] = []
    @State private var invitations: [DearRecord] = []
    @State private var spaceId = ""
    @State private var activityId = ""
    @State private var spaceName = ""
    @State private var activityName = ""
    @State private var inviteUsername = ""
    @State private var inviteLink = ""
    @State private var error = ""
    @State private var notice = ""
    @State private var busy = false

    private var base: String { "/api/dear/social/" }
    private var selectedSpace: DearRecord? { spaces.first { $0.id == spaceId } }
    private var selectedActivity: DearRecord? { activities.first { $0.id == activityId } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("亲近的人，日常的事").font(.headline)
                    Text("和孩子一起成长，和家人保持联系，和朋友分享相聚时刻。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                    if !notice.isEmpty { Text(notice).foregroundStyle(.teal) }
                }
                if store.ready {
                    Section("亲密关系") {
                        NavigationLink { FamilyConnectionsView(store: store) } label: { Label("和孩子 · 倾听与陪伴", systemImage: "heart") }
                        NavigationLink { GenealogyView(store: store) } label: { Label("和家人 · 家族族谱", systemImage: "person.3") }
                    }
                }
                Section("共同生活空间") {
                    if spaces.isEmpty { Text("创建一个空间，邀请家人或朋友参加活动。").foregroundStyle(.secondary) }
                    else {
                        Picker("当前空间", selection: $spaceId) {
                            ForEach(spaces) { item in Text(item.text("name")).tag(item.id) }
                        }
                    }
                    HStack {
                        TextField("新空间名称", text: $spaceName).textInputAutocapitalization(.never)
                        Button("创建") { run { try await createSpace() } }
                            .disabled(busy || spaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("加入同一空间不等于建立好友关系；活动邀请需对方确认。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if selectedSpace != nil {
                    Section("共同活动") {
                        if activities.isEmpty { Text("还没有活动").foregroundStyle(.secondary) }
                        else {
                            Picker("选择活动", selection: $activityId) {
                                ForEach(activities) { item in Text(item.text("title")).tag(item.id) }
                            }
                        }
                        HStack {
                            TextField("例如：周末野餐", text: $activityName)
                            Button("添加") { run { try await createActivity() } }
                                .disabled(busy || activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                if let selectedActivity {
                    Section("邀请参加 · \(selectedActivity.text("title"))") {
                        HStack {
                            TextField("用户中心用户名", text: $inviteUsername).textInputAutocapitalization(.never)
                            Button("邀请") { run { try await inviteByName() } }
                                .disabled(busy || inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Button("生成七天有效的邀请链接") { run { try await createInviteLink() } }.disabled(busy)
                        if !inviteLink.isEmpty {
                            ShareLink(item: URL(string: inviteLink)!) { Label("分享邀请链接", systemImage: "square.and.arrow.up") }
                        }
                        Text("对方确认加入后，才能看到活动中分享的照片。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("共同相册") {
                        if photos.isEmpty { Text("还没有分享的照片").foregroundStyle(.secondary) }
                        ForEach(photos) { photo in
                            HStack(spacing: 12) {
                                if photo.flag("thumbnailAvailable") {
                                    DearPhotoPreview(store: store, path: base + "tenants/\(spaceId)/activities/\(activityId)/native-photos/\(photo.id)/thumbnail")
                                } else {
                                    Image(systemName: "photo").frame(width: 64, height: 64).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading) {
                                    Text(photo.text("sourceDisplayName")).font(.subheadline.bold())
                                    Text(photo.text("originalFileName")).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("刷新相册") { run { try await loadPhotos() } }.disabled(busy)
                        Link("分享照片与获取原图", destination: URL(string: "https://linko.ai.impx.net/")!)
                    }
                }
                if invitations.contains(where: { !$0.flag("joined") }) {
                    Section("收到的邀请") {
                        ForEach(invitations.filter { !$0.flag("joined") }) { invitation in
                            HStack {
                                Text(invitation.text("activityTitle"))
                                Spacer()
                                Button("确认加入") { run { try await accept(invitation) } }.disabled(busy)
                            }
                        }
                    }
                }
                if showLogout {
                    Section { Link("隐私政策与支持", destination: URL(string: "https://happylife.ai.impx.net/legal/linko-family-privacy.html")!) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Linko Dear")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("刷新", systemImage: "arrow.clockwise") { run { try await load() } }.disabled(busy) }
                if showLogout { ToolbarItem(placement: .topBarLeading) { Button("退出") { store.logout() } } }
            }
            .refreshable { try? await load() }
            .task { try? await load() }
            .onChange(of: spaceId) { _, _ in activityId = ""; activities = []; photos = []; run { try await loadActivities() } }
            .onChange(of: activityId) { _, _ in photos = []; run { try await loadPhotos() } }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task { busy = true; error = ""; notice = ""; defer { busy = false }
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }
    private func load() async throws {
        async let found = store.call(base + "tenants")
        async let pending = store.call(base + "invites/username/pending")
        let loaded = try DearRecord.list(await found)
        invitations = try DearRecord.list(await pending)
        spaces = loaded
        if !loaded.contains(where: { $0.id == spaceId }) { spaceId = loaded.first?.id ?? "" }
        if !spaceId.isEmpty { try await loadActivities() }
    }
    private func loadActivities() async throws {
        guard !spaceId.isEmpty else { return }
        let loaded = try DearRecord.list(await store.call(base + "tenants/\(spaceId)/activities"))
        activities = loaded
        if !loaded.contains(where: { $0.id == activityId }) { activityId = loaded.first?.id ?? "" }
        if !activityId.isEmpty { try await loadPhotos() }
    }
    private func loadPhotos() async throws {
        guard !spaceId.isEmpty, !activityId.isEmpty else { return }
        photos = try DearRecord.list(await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/live/photos"))
    }
    private func createSpace() async throws {
        let value = try await store.call(base + "tenants", method: "POST", body: ["name": spaceName.trimmingCharacters(in: .whitespacesAndNewlines)])
        let item = DearRecord(data: value as? [String: Any] ?? [:])
        spaceName = ""; try await load(); spaceId = item.id; notice = "空间已创建。"
    }
    private func createActivity() async throws {
        let value = try await store.call(base + "tenants/\(spaceId)/activities", method: "POST", body: ["title": activityName.trimmingCharacters(in: .whitespacesAndNewlines), "description": ""])
        let item = DearRecord(data: value as? [String: Any] ?? [:])
        activityName = ""; try await loadActivities(); activityId = item.id; notice = "活动已创建。"
    }
    private func inviteByName() async throws {
        _ = try await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/invites/username", method: "POST", body: ["username": inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines)])
        inviteUsername = ""; notice = "邀请已发出，等待对方确认。"
    }
    private func createInviteLink() async throws {
        let value = try await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/invites/link", method: "POST", body: [:])
        guard let token = (value as? [String: Any])?["token"] as? String,
              let safe = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw APIError.message("邀请链接无效。") }
        inviteLink = "https://happylife.ai.impx.net/dear?invite=\(safe)"
    }
    private func accept(_ invitation: DearRecord) async throws {
        let me = try await store.call(base + "me") as? [String: Any] ?? [:]
        guard let username = me["username"] as? String,
              let safe = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw APIError.message("无法确认用户名。") }
        _ = try await store.call(base + "tenants/\(invitation.text("tenantId"))/activities/\(invitation.text("activityId"))/invites/username/\(safe)/accept", method: "POST", body: [:])
        try await load(); notice = "已加入共同活动。"
    }
}

private struct DearPhotoPreview: View {
    @ObservedObject var store: FamilyStore
    let path: String
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .frame(width: 64, height: 64).clipped().background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: path) { image = try? await store.authenticatedImage(path) }
    }
}
