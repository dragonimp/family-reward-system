import SwiftUI

private struct DearRecord: Identifiable {
    let data: [String: Any]
    var id: String { text("id") }
    var subject: String { text("subject") }
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
    @State private var moments: [DearRecord] = []
    @State private var activityMembers: [DearRecord] = []
    @State private var relationships: [DearRecord] = []
    @State private var invitations: [DearRecord] = []
    @State private var spaceId = ""
    @State private var activityId = ""
    @State private var showingActivity = false
    @State private var spaceName = ""
    @State private var activityName = ""
    @State private var inviteUsername = ""
    @State private var momentDraft = ""
    @State private var momentRequestID = UUID()
    @State private var inviteLink = ""
    @State private var error = ""
    @State private var activityError = ""
    @State private var activityLoading = false
    @State private var notice = ""
    @State private var busy = false

    private var base: String { "/api/dear/social/" }
    private var selectedSpace: DearRecord? { spaces.first { $0.id == spaceId } }
    private var selectedActivity: DearRecord? { activities.first { $0.id == activityId } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("相聚时刻").font(.title2.bold())
                    Text("空间收纳一组活动；点开活动再查看邀请、相册、日常与成员。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                    if !notice.isEmpty { Text(notice).foregroundStyle(.teal) }
                }
                if invitations.contains(where: { !$0.flag("joined") }) {
                    Section("待确认的活动邀请") {
                        ForEach(invitations.filter { !$0.flag("joined") }) { invitation in
                            HStack {
                                Text(invitation.text("activityTitle"))
                                Spacer()
                                Button("确认加入") { run { try await accept(invitation) } }.disabled(busy)
                            }
                        }
                    }
                }
                Section("生活空间") {
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
                    Text("空间只用于归拢活动；参加活动和建立好友关系都需分别确认。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if selectedSpace != nil {
                    Section("活动 · \(selectedSpace?.text("name") ?? "")") {
                        if activityLoading { Text("正在读取已有活动…").foregroundStyle(.secondary) }
                        if !activityError.isEmpty { Text(activityError).foregroundStyle(.red) }
                        if activities.isEmpty && !activityLoading && activityError.isEmpty { Text("还没有活动").foregroundStyle(.secondary) }
                        else {
                            ForEach(activities) { item in
                                Button {
                                    activityId = item.id
                                    showingActivity = true
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.text("title")).font(.body.weight(.medium))
                                            if !item.text("description").isEmpty {
                                                Text(item.text("description")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                        HStack {
                            TextField("例如：周末野餐", text: $activityName)
                            Button("添加") { run { try await createActivity() } }
                                .disabled(busy || activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                Section("好友关系 · 跨空间") {
                    DisclosureGroup("查看好友与申请") {
                        if relationships.isEmpty { Text("还没有好友关系或申请。") .foregroundStyle(.secondary) }
                        ForEach(relationships) { relation in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(relation.text("peerName"))
                                    Text(relation.text("status") == "accepted" ? "朋友" : relation.text("direction") == "incoming" ? "邀请你成为朋友" : "等待对方确认")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if relation.text("status") == "pending" && relation.text("direction") == "incoming" {
                                    Button("接受") { run { try await acceptFriend(relation) } }.disabled(busy)
                                }
                                Button(relation.text("status") == "accepted" ? "解除" : "移除", role: .destructive) {
                                    run { try await removeFriend(relation) }
                                }.disabled(busy)
                            }
                        }
                    }
                }
                if showLogout {
                    Section { Link("隐私政策与支持", destination: URL(string: "https://happylife.ai.impx.net/legal/linko-family-privacy.html")!) }
                }
            }
            .listStyle(.insetGrouped)
            .readablePage()
            .navigationTitle("活动与分享")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("刷新", systemImage: "arrow.clockwise") { run { try await load() } }.disabled(busy) }
                if showLogout { ToolbarItem(placement: .topBarLeading) { Button("退出") { store.logout() } } }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
            .onChange(of: spaceId) { _, _ in activityId = ""; showingActivity = false; activities = []; photos = []; activityError = ""; activityLoading = true; run { try await loadActivities() } }
            .navigationDestination(isPresented: $showingActivity) { activityDetail }
            .onChange(of: activityId) { _, _ in photos = []; moments = []; activityMembers = []; run { try await loadPhotos(); try await loadMoments(); try await loadMembers() } }
        }
    }

    private var activityDetail: some View {
        List {
            if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
            if !notice.isEmpty { Section { Text(notice).foregroundStyle(.teal) } }
            Section {
                Text(selectedSpace?.text("name") ?? "生活空间").font(.caption).foregroundStyle(.teal)
                Text(selectedActivity?.text("title") ?? "活动详情").font(.title2.bold())
                Text("邀请、照片、日常和成员仅属于这场活动。")
                    .font(.caption).foregroundStyle(.secondary)
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
                    Section("照片分享 · \(selectedActivity.text("title"))") {
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
                    Section("生活分享 · \(selectedActivity.text("title"))") {
                        Text("只向这场活动的成员展示。")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $momentDraft).frame(minHeight: 76)
                            .accessibilityLabel("写下生活日常")
                            .onChange(of: momentDraft) { _, _ in momentRequestID = UUID() }
                        Button("发布日常") { run { try await publishMoment() } }
                            .disabled(busy || momentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || momentDraft.count > 1000)
                        ForEach(moments) { moment in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(moment.text("authorName")).font(.subheadline.bold())
                                Text(moment.text("text")).textSelection(.enabled)
                                if moment.flag("canDelete") {
                                    Button("删除我的记录", role: .destructive) { run { try await deleteMoment(moment) } }.font(.caption)
                                }
                            }.padding(.vertical, 4)
                        }
                        if moments.isEmpty { Text("还没有分享的日常。") .foregroundStyle(.secondary) }
                        Button("刷新日常") { run { try await loadMoments() } }.disabled(busy)
                    }
                    Section("活动成员与好友") {
                        Text("同一活动不会自动建立好友关系，需要对方确认。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(activityMembers.filter { !$0.flag("isSelf") }, id: \.subject) { member in
                            HStack {
                                Text(member.text("displayName"))
                                Spacer()
                                if let relation = relationships.first(where: { $0.text("peerSubject") == member.subject }) {
                                    Text(relation.text("status") == "accepted" ? "已是朋友" : "待确认")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Button("申请好友") { run { try await requestFriend(member) } }.disabled(busy)
                                }
                            }
                        }
                        if activityMembers.filter({ !$0.flag("isSelf") }).isEmpty {
                            Text("邀请其他人参加活动后，可以互相申请好友。") .foregroundStyle(.secondary)
                        }
                    }
                }
        }
        .listStyle(.insetGrouped)
        .readablePage()
        .navigationTitle(selectedActivity?.text("title") ?? "活动详情")
        .refreshable {
            do { try await loadDetails(); try await loadRelationships() }
            catch { self.error = error.localizedDescription }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task { busy = true; error = ""; notice = ""; defer { busy = false }
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }
    private func refresh() async {
        do { try await load() }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func load() async throws {
        error = ""
        let loaded = try DearRecord.list(await store.call(base + "tenants"))
        spaces = loaded
        let previousSpace = spaceId
        if !loaded.contains(where: { $0.id == spaceId }) { spaceId = loaded.first?.id ?? "" }
        if spaceId == previousSpace && !spaceId.isEmpty { try await loadActivities() }
        do { invitations = try DearRecord.list(await store.call(base + "invites/username/pending")) }
        catch { self.error = "活动邀请暂时无法读取：\(error.localizedDescription)" }
        do { try await loadRelationships() }
        catch { self.error = "好友关系暂时无法读取：\(error.localizedDescription)" }
    }
    private func loadActivities() async throws {
        guard !spaceId.isEmpty else { activityLoading = false; return }
        activityLoading = true
        defer { activityLoading = false }
        let requestedSpace = spaceId
        let loaded: [DearRecord]
        do { loaded = try DearRecord.list(await store.call(base + "tenants/\(requestedSpace)/activities")) }
        catch {
            activityError = "活动读取失败：\(error.localizedDescription)"
            throw error
        }
        guard requestedSpace == spaceId else { return }
        activities = loaded
        activityError = ""
        let previousActivity = activityId
        if !loaded.contains(where: { $0.id == activityId }) { activityId = ""; showingActivity = false }
        if activityId == previousActivity && !activityId.isEmpty {
            do { try await loadDetails() }
            catch { self.error = "活动内容暂时无法读取：\(error.localizedDescription)" }
        }
    }
    private func loadDetails() async throws {
        try await loadPhotos(); try await loadMoments(); try await loadMembers()
    }
    private func loadPhotos() async throws {
        guard !spaceId.isEmpty, !activityId.isEmpty else { return }
        photos = try DearRecord.list(await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/live/photos"))
    }
    private func loadMoments() async throws {
        guard !spaceId.isEmpty, !activityId.isEmpty else { return }
        moments = try DearRecord.list(await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/moments"))
    }
    private func loadMembers() async throws {
        guard !spaceId.isEmpty, !activityId.isEmpty else { return }
        activityMembers = try DearRecord.list(await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/members"))
    }
    private func loadRelationships() async throws {
        relationships = try DearRecord.list(await store.call(base + "relationships"))
    }
    private func requestFriend(_ member: DearRecord) async throws {
        _ = try await store.call(base + "relationships/requests", method: "POST", body: ["targetSubject": member.subject, "tenantId": spaceId, "activityId": activityId])
        try await loadRelationships(); notice = "好友申请已发出。"
    }
    private func acceptFriend(_ relation: DearRecord) async throws {
        _ = try await store.call(base + "relationships/\(relation.id)/accept", method: "POST", body: [:])
        try await loadRelationships(); notice = "已确认好友关系。"
    }
    private func removeFriend(_ relation: DearRecord) async throws {
        _ = try await store.call(base + "relationships/\(relation.id)", method: "DELETE")
        try await loadRelationships(); notice = "关系已移除。"
    }
    private func publishMoment() async throws {
        let body = momentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 1000 else { throw APIError.message("请填写 1 至 1000 字的日常内容。") }
        _ = try await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/moments", method: "POST", body: ["text": body, "requestId": momentRequestID.uuidString])
        momentDraft = ""; momentRequestID = UUID(); try await loadMoments(); notice = "日常已发布。"
    }
    private func deleteMoment(_ moment: DearRecord) async throws {
        _ = try await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/moments/\(moment.id)", method: "DELETE")
        try await loadMoments(); notice = "日常已删除。"
    }
    private func createSpace() async throws {
        let value = try await store.call(base + "tenants", method: "POST", body: ["name": spaceName.trimmingCharacters(in: .whitespacesAndNewlines)])
        let item = DearRecord(data: value as? [String: Any] ?? [:])
        spaceName = ""; try await load(); spaceId = item.id; notice = "空间已创建。"
    }
    private func createActivity() async throws {
        let value = try await store.call(base + "tenants/\(spaceId)/activities", method: "POST", body: ["title": activityName.trimmingCharacters(in: .whitespacesAndNewlines), "description": ""])
        let item = DearRecord(data: value as? [String: Any] ?? [:])
        activityName = ""; try await loadActivities(); activityId = item.id; showingActivity = true; notice = "活动已创建。"
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
        try await load(); spaceId = invitation.text("tenantId"); notice = "已加入共同活动，可在所属空间点开查看。"
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
