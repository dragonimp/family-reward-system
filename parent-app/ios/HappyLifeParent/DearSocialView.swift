import SwiftUI
import CoreLocation
import PhotosUI

private struct DearRecord: Identifiable {
    let data: [String: Any]
    var id: String { text("id") }
    var subject: String { text("subject") }
    func text(_ key: String) -> String { data[key] as? String ?? "" }
    func dateText(_ key: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let raw = text(key)
        let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        return date?.formatted(date: .abbreviated, time: .shortened) ?? raw
    }
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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var moments: [DearRecord] = []
    @State private var checkIns: [DearRecord] = []
    @StateObject private var checkInLocator = DearCheckInLocator()
    @State private var showingCheckIn = false
    @State private var checkInNote = ""
    @State private var checkInRequestID = UUID()
    @State private var activityMembers: [DearRecord] = []
    @State private var relationships: [DearRecord] = []
    @State private var invitations: [DearRecord] = []
    @State private var spaceId = ""
    @State private var activityId = ""
    @State private var showingActivity = false
    @State private var showingActivityManagement = false
    @State private var spaceName = ""
    @State private var activityName = ""
    @State private var editedSpaceName = ""
    @State private var editedActivityName = ""
    @State private var showingSpaceRename = false
    @State private var showingActivityRename = false
    @State private var showingSpaceDelete = false
    @State private var showingActivityDelete = false
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
                        if selectedSpace?.text("role") == "owner" {
                            Button("修改空间名称", systemImage: "pencil") {
                                editedSpaceName = selectedSpace?.text("name") ?? ""
                                showingSpaceRename = true
                            }.disabled(busy)
                            Button("删除空间", systemImage: "trash", role: .destructive) {
                                showingSpaceDelete = true
                            }.disabled(busy)
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
                    Section { Link("隐私政策与支持", destination: URL(string: "https://happylife.ai.xmkurt.com/legal/linko-family-privacy.html")!) }
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
            .onChange(of: spaceId) { _, _ in activityId = ""; showingActivity = false; showingActivityManagement = false; activities = []; photos = []; activityError = ""; activityLoading = true; run { try await loadActivities() } }
            .navigationDestination(isPresented: $showingActivity) { activityDetail }
            .onChange(of: activityId) { _, _ in photos = []; moments = []; checkIns = []; activityMembers = []; run { try await loadDetails() } }
            .alert("修改空间名称", isPresented: $showingSpaceRename) {
                TextField("空间名称", text: $editedSpaceName)
                Button("取消", role: .cancel) { }
                Button("保存") { run { try await renameSpace() } }
            } message: { Text("新名称会同步给空间成员。") }
            .confirmationDialog("删除空间「\(selectedSpace?.text("name") ?? "")」？", isPresented: $showingSpaceDelete, titleVisibility: .visible) {
                Button("确认删除空间", role: .destructive) { run { try await deleteSpace() } }
                Button("取消", role: .cancel) { }
            } message: { Text("仅可删除没有活动、其他成员或分享记录的空间。") }
        }
    }

    private var activityDetail: some View {
        List {
            if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
            if !notice.isEmpty { Section { Text(notice).foregroundStyle(.teal) } }
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedSpace?.text("name") ?? "生活空间").font(.caption).foregroundStyle(.teal)
                        Text(selectedActivity?.text("title") ?? "活动详情").font(.title2.bold())
                        Text("邀请、照片、日常和成员仅属于这场活动。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showingActivityManagement = true } label: {
                        Label("管理", systemImage: "ellipsis.circle")
                            .font(.subheadline)
                    }.disabled(selectedActivity == nil)
                }
            }
                if let selectedActivity {
                    Section("照片分享 · \(selectedActivity.text("title"))") {
                        PhotosPicker("共享 iPhone 照片", selection: $selectedPhoto, matching: .images)
                            .disabled(busy)
                        Text("原图留在此 iPhone；对方获取原图时，请保持 Linko Moment 打开。")
                            .font(.caption).foregroundStyle(.secondary)
                        if photos.isEmpty { Text("还没有分享的照片").foregroundStyle(.secondary) }
                        ForEach(photos) { photo in
                            NavigationLink {
                                DearPhotoDetailView(store: store, photo: photo,
                                    spaceID: spaceId, activityID: activityId,
                                    path: base + "tenants/\(spaceId)/activities/\(activityId)/native-photos/\(photo.id)/thumbnail")
                            } label: {
                                HStack(spacing: 14) {
                                    DearPhotoPreview(store: store, path: base + "tenants/\(spaceId)/activities/\(activityId)/native-photos/\(photo.id)/thumbnail")
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(photo.text("originalFileName")).font(.subheadline.bold()).lineLimit(2)
                                        Text(photo.text("sourceDisplayName")).font(.caption).foregroundStyle(.secondary)
                                        if !photo.flag("thumbnailAvailable") {
                                            Text("预览尚未就绪，点开可重试").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        Button("刷新相册") { run { try await loadPhotos() } }.disabled(busy)
                    }
                    Section("生活分享 · \(selectedActivity.text("title"))") {
                        Text("只向这场活动的成员展示。")
                            .font(.caption).foregroundStyle(.secondary)
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
                    Section("活动打卡") {
                        Button { checkInNote = ""; checkInRequestID = UUID(); showingCheckIn = true; checkInLocator.locate() } label: {
                            Label("在当前位置打卡", systemImage: "location.circle")
                        }.disabled(busy)
                        ForEach(checkIns) { checkIn in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(checkIn.text("authorName")).font(.subheadline.bold())
                                    Spacer()
                                    Text(checkIn.dateText("createdAt")).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(checkIn.text("note")).textSelection(.enabled)
                                Text("海拔 \(String(format: "%.1f", checkIn.data["altitudeMeters"] as? Double ?? 0)) 米 · \(checkIn.text("address"))")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let latitude = checkIn.data["latitude"] as? Double,
                                   let longitude = checkIn.data["longitude"] as? Double {
                                    Text(String(format: "%.6f, %.6f", latitude, longitude))
                                        .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }.padding(.vertical, 4)
                        }
                        if checkIns.isEmpty { Text("还没有打卡记录。") .foregroundStyle(.secondary) }
                    }
                    Section("活动成员") {
                        Text("同一活动不会自动建立好友关系，需要对方确认。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(activityMembers.filter { !$0.flag("isSelf") }, id: \.subject) { member in
                            HStack {
                                Text(member.text("displayName"))
                                Spacer()
                                if let relation = relationships.first(where: { $0.text("peerSubject") == member.subject }) {
                                    Text(relation.text("status") == "accepted" ? "已是朋友" : "待确认")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else { Text("尚未成为好友").font(.caption).foregroundStyle(.secondary) }
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
        .sheet(isPresented: $showingActivityManagement) { activityManagement }
        .sheet(isPresented: $showingCheckIn) { checkInSheet }
        .onChange(of: activityId) { _, _ in showingActivityManagement = false; inviteLink = ""; inviteUsername = ""; momentDraft = ""; momentRequestID = UUID() }
        .onChange(of: selectedPhoto) { _, selected in
            guard let selected else { return }
            let targetSpace = spaceId, targetActivity = activityId
            run {
                defer { selectedPhoto = nil }
                guard let data = try await selected.loadTransferable(type: Data.self),
                      let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else {
                    throw APIError.message("无法读取所选照片。")
                }
                try await store.photoSource.publish(jpeg, spaceID: targetSpace, activityID: targetActivity,
                                                    name: "iPhone照片.jpg")
                try await loadPhotos()
                notice = "照片已共享；请保持此 iPhone 可以响应原图请求。"
            }
        }
        .refreshable {
            do { try await loadDetails(); try await loadRelationships() }
            catch { self.error = error.localizedDescription }
        }
    }

    private var checkInSheet: some View {
        NavigationStack {
            Form {
                Section("当前位置") {
                    if checkInLocator.fetching { ProgressView("正在获取位置和地址…") }
                    if !checkInLocator.error.isEmpty { Text(checkInLocator.error).foregroundStyle(.red) }
                    if let location = checkInLocator.location, !checkInLocator.fetching {
                        Text(checkInLocator.address)
                        Text(String(format: "纬度 %.6f，经度 %.6f", location.coordinate.latitude, location.coordinate.longitude))
                        Text(String(format: "海拔 %.1f 米", location.altitude))
                    }
                    Button("重新定位") { checkInLocator.locate() }.disabled(checkInLocator.fetching)
                }
                Section("备注") {
                    TextField("默认填写当前位置地址", text: $checkInNote, axis: .vertical)
                        .lineLimit(2...5)
                    Text("留空时使用上方地址作为备注。") .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("活动打卡")
            .onChange(of: checkInLocator.address) { _, address in
                if checkInNote.isEmpty { checkInNote = address }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showingCheckIn = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { run { try await createCheckIn() } }
                        .disabled(checkInLocator.location == nil || checkInLocator.fetching || busy || checkInNote.count > 1000)
                }
            }
        }
    }

    private var activityManagement: some View {
        NavigationStack {
            Form {
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
                if !notice.isEmpty { Section { Text(notice).foregroundStyle(.teal) } }
                if selectedActivity?.flag("canEdit") == true {
                    Section("活动设置") {
                        Button("修改活动名称", systemImage: "pencil") {
                            editedActivityName = selectedActivity?.text("title") ?? ""
                            showingActivityRename = true
                        }.disabled(busy)
                        Button("删除活动", systemImage: "trash", role: .destructive) {
                            showingActivityDelete = true
                        }.disabled(busy)
                    }
                }
                Section("邀请参加") {
                    HStack {
                        TextField("用户中心用户名", text: $inviteUsername).textInputAutocapitalization(.never)
                        Button("邀请") { run { try await inviteByName() } }
                            .disabled(busy || inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button("生成七天有效的邀请链接") { run { try await createInviteLink() } }.disabled(busy)
                    if let url = URL(string: inviteLink), url.scheme == "https" {
                        ShareLink(item: url) { Label("分享邀请链接", systemImage: "square.and.arrow.up") }
                    }
                    Text("对方确认加入后才能查看这场活动的分享。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("发布日常") {
                    TextEditor(text: $momentDraft).frame(minHeight: 90)
                        .accessibilityLabel("写下生活日常")
                        .onChange(of: momentDraft) { _, _ in momentRequestID = UUID() }
                    Button("发布日常") { run { try await publishMoment() } }
                        .disabled(busy || momentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || momentDraft.count > 1000)
                }
                Section("活动成员与好友") {
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
            .navigationTitle("管理 · \(selectedActivity?.text("title") ?? "活动")")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showingActivityManagement = false } } }
            .alert("修改活动名称", isPresented: $showingActivityRename) {
                TextField("活动名称", text: $editedActivityName)
                Button("取消", role: .cancel) { }
                Button("保存") { run { try await renameActivity() } }
            } message: { Text("新名称会同步给活动成员。") }
            .confirmationDialog("删除活动「\(selectedActivity?.text("title") ?? "")」？", isPresented: $showingActivityDelete, titleVisibility: .visible) {
                Button("确认删除活动", role: .destructive) { run { try await deleteActivity() } }
                Button("取消", role: .cancel) { }
            } message: { Text("仅可删除没有其他成员、照片或日常记录的活动；已发出的邀请会失效。") }
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
        try await loadPhotos(); try await loadMoments(); try await loadCheckIns(); try await loadMembers()
    }
    private func loadPhotos() async throws {
        guard !spaceId.isEmpty, !activityId.isEmpty else { return }
        var loaded = try DearRecord.list(await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/live/photos"))
        if loaded.contains(where: { !$0.flag("thumbnailAvailable") }) {
            await store.photoSource.refreshPreviews(spaceID: spaceId, activityID: activityId, rows: loaded.map(\.data))
            loaded = try DearRecord.list(await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/live/photos"))
        }
        photos = loaded
    }
    private func loadMoments() async throws {
        guard !spaceId.isEmpty, !activityId.isEmpty else { return }
        moments = try DearRecord.list(await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/moments"))
    }
    private func loadCheckIns() async throws {
        guard !spaceId.isEmpty, !activityId.isEmpty else { return }
        checkIns = try DearRecord.list(await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/checkins"))
    }
    private func createCheckIn() async throws {
        guard let location = checkInLocator.location, !checkInLocator.fetching else { throw APIError.message("请先获取当前位置。") }
        let note = checkInNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= 1000 else { throw APIError.message("备注不能超过 1000 字。") }
        _ = try await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/checkins", method: "POST", body: [
            "requestId": checkInRequestID.uuidString,
            "latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude,
            "altitudeMeters": location.altitude, "address": checkInLocator.address,
            "note": note.isEmpty ? checkInLocator.address : note
        ])
        showingCheckIn = false; checkInRequestID = UUID(); try await loadCheckIns(); notice = "打卡已保存。"
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
    private func renameSpace() async throws {
        guard selectedSpace?.text("role") == "owner" else { throw APIError.message("只有空间所有者可以修改名称。") }
        let name = editedSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && name.count <= 200 else { throw APIError.message("请填写不超过 200 字的空间名称。") }
        _ = try await store.call(base + "tenants/\(spaceId)", method: "PATCH", body: ["name": name])
        try await load(); notice = "空间名称已更新。"
    }
    private func deleteSpace() async throws {
        guard selectedSpace?.text("role") == "owner" else { throw APIError.message("只有空间所有者可以删除空间。") }
        _ = try await store.call(base + "tenants/\(spaceId)", method: "DELETE")
        spaceId = ""; activityId = ""; activities = []
        try await load(); notice = "空间已删除。"
    }
    private func createActivity() async throws {
        let value = try await store.call(base + "tenants/\(spaceId)/activities", method: "POST", body: ["title": activityName.trimmingCharacters(in: .whitespacesAndNewlines), "description": ""])
        let item = DearRecord(data: value as? [String: Any] ?? [:])
        activityName = ""; try await loadActivities(); activityId = item.id; showingActivity = true; notice = "活动已创建。"
    }
    private func renameActivity() async throws {
        guard selectedActivity?.flag("canEdit") == true else { throw APIError.message("只有活动组织者可以修改名称。") }
        let name = editedActivityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && name.count <= 200 else { throw APIError.message("请填写不超过 200 字的活动名称。") }
        _ = try await store.call(base + "tenants/\(spaceId)/activities/\(activityId)", method: "PATCH", body: ["title": name])
        try await loadActivities(); notice = "活动名称已更新。"
    }
    private func deleteActivity() async throws {
        guard selectedActivity?.flag("canEdit") == true else { throw APIError.message("只有活动组织者可以删除活动。") }
        _ = try await store.call(base + "tenants/\(spaceId)/activities/\(activityId)", method: "DELETE")
        showingActivityManagement = false; showingActivity = false; activityId = ""
        try await loadActivities(); notice = "活动已删除。"
    }
    private func inviteByName() async throws {
        _ = try await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/invites/username", method: "POST", body: ["username": inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines)])
        inviteUsername = ""; notice = "邀请已发出，等待对方确认。"
    }
    private func createInviteLink() async throws {
        let value = try await store.call(base + "tenants/\(spaceId)/activities/\(activityId)/invites/link", method: "POST", body: [:])
        guard let token = (value as? [String: Any])?["token"] as? String,
              let safe = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw APIError.message("邀请链接无效。") }
        inviteLink = "https://happylife.ai.xmkurt.com/dear?invite=\(safe)"
    }
    private func accept(_ invitation: DearRecord) async throws {
        let me = try await store.call(base + "me") as? [String: Any] ?? [:]
        guard let username = me["username"] as? String,
              let safe = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw APIError.message("无法确认用户名。") }
        _ = try await store.call(base + "tenants/\(invitation.text("tenantId"))/activities/\(invitation.text("activityId"))/invites/username/\(safe)/accept", method: "POST", body: [:])
        try await load(); spaceId = invitation.text("tenantId"); notice = "已加入共同活动，可在所属空间点开查看。"
    }
}

private final class DearCheckInLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var address = ""
    @Published private(set) var error = ""
    @Published private(set) var fetching = false
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func locate() {
        location = nil; address = ""; error = ""; fetching = true
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: fetching = false; error = "请在系统设置中允许此 App 使用位置后重试。"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard fetching else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: fetching = false; error = "位置访问未获授权，请在系统设置中开启。"
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard fetching else { return }
        guard let current = locations.last(where: { $0.horizontalAccuracy >= 0 && $0.verticalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 120 }) else {
            fetching = false; error = "没有获取到有效的位置与海拔，请重试。"; return
        }
        geocoder.reverseGeocodeLocation(current) { [weak self] placemarks, _ in
            guard let self else { return }
            let fallback = String(format: "%.6f, %.6f", current.coordinate.latitude, current.coordinate.longitude)
            self.address = placemarks?.first?.name ?? fallback
            self.location = current
            self.fetching = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fetching = false; self.error = "定位失败：\(error.localizedDescription)"
    }
}

private struct DearPhotoPreview: View {
    @ObservedObject var store: FamilyStore
    let path: String
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if failed {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("预览失败").font(.caption2)
                }.foregroundStyle(.secondary)
            }
            else { ProgressView() }
        }
        .frame(width: 104, height: 104).clipped().background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: path) {
            do { image = try await store.authenticatedImage(path); failed = false }
            catch { image = nil; failed = true }
        }
    }
}

private struct DearPhotoDetailView: View {
    @ObservedObject var store: FamilyStore
    let photo: DearRecord
    let spaceID: String
    let activityID: String
    let path: String
    @State private var image: UIImage?
    @State private var error: String?
    @State private var originalURL: URL?
    @State private var originalImage: UIImage?
    @State private var originalError: String?
    @State private var fetchingOriginal = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let image = originalImage ?? image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let error {
                    ContentUnavailableView("无法显示照片预览", systemImage: "photo.badge.exclamationmark",
                                           description: Text(error))
                    Button("重试") { Task { await load() } }
                } else { ProgressView("正在加载照片") }
                Text(photo.text("originalFileName")).font(.headline)
                Text("分享者：\(photo.text("sourceDisplayName"))").font(.subheadline).foregroundStyle(.secondary)
                if let originalURL {
                    ShareLink(item: originalURL) { Label("分享原图", systemImage: "square.and.arrow.up") }
                } else {
                    Button {
                        Task { await fetchOriginal() }
                    } label: {
                        Label(fetchingOriginal ? "正在等待源设备传图…" : "获取原图", systemImage: "arrow.down.circle")
                    }.disabled(fetchingOriginal)
                }
                if let originalError { Text(originalError).font(.footnote).foregroundStyle(.red) }
                Text("原图从分享者设备传来，获取时请保持对方的分享应用打开。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle("照片")
        .task(id: path) { await load() }
    }

    private func load() async {
        image = nil; error = nil
        do { image = try await store.authenticatedImage(path) }
        catch {
            if let local = await store.photoSource.localOriginal(photoID: photo.id, spaceID: spaceID, activityID: activityID),
               let localImage = UIImage(contentsOfFile: local.path) { image = localImage }
            else { self.error = error.localizedDescription }
        }
    }

    private func fetchOriginal() async {
        fetchingOriginal = true; originalError = nil
        defer { fetchingOriginal = false }
        do {
            let url = try await store.photoSource.downloadOriginal(photoID: photo.id, spaceID: spaceID, activityID: activityID)
            guard let decoded = UIImage(contentsOfFile: url.path) else { throw APIError.message("原图无法显示。") }
            originalImage = decoded
            originalURL = url
        } catch { originalError = error.localizedDescription }
    }
}
