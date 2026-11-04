import AgentIdentityLocalization
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
            Text(String(localized: "通过配对的 iPhone 使用已登录账号管理活动。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                .font(.footnote).foregroundStyle(.secondary)
            if store.socialLoading { ProgressView(String(localized: "读取中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            if let error = store.socialError { Text(error).foregroundStyle(.red).font(.footnote) }
            if let actionError { Text(actionError).foregroundStyle(.red).font(.footnote) }
            if !invitations.isEmpty {
                Section(String(localized: "待确认邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    ForEach(invitations.indices, id: \.self) { index in
                        let item = invitations[index]
                        Button(String(localized: "加入 \(item["title"] as? String ?? String(localized: "活动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                            Task {
                                await run("acceptInvitation", spaceID: item["tenantId"] as? String,
                                          activityID: item["activityId"] as? String)
                            }
                        }
                    }
                }
            }
            Section(String(localized: "生活空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
            ForEach(store.socialSpaces) { space in
                NavigationLink(space.name, destination: WatchSocialActivitiesView(space: space))
                if space.owner {
                    Button(String(localized: "修改“\(space.name)”名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { name = space.name; editing = space }
                    Button(String(localized: "删除“\(space.name)”", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { deleting = space }
                }
            }
            if store.socialSpaces.isEmpty && !store.socialLoading && store.socialError == nil {
                Text(String(localized: "暂无空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            TextField(String(localized: "新空间名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $name)
            Button(String(localized: "创建空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await run("createSpace", fields: ["name": name]) } }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.loadSocialSpaces() } }
        }
        .navigationTitle(String(localized: "活动空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        .task { await refresh() }
        .alert(String(localized: "修改空间名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField(String(localized: "空间名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $name)
            Button(String(localized: "保存", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                guard let space = editing else { return }
                Task { await run("renameSpace", spaceID: space.id, fields: ["name": name]) }
            }
            Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .cancel) { editing = nil }
        }
        .confirmationDialog(String(localized: "确认删除空间？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(String(localized: "确认删除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) {
                guard let space = deleting else { return }
                Task { await run("deleteSpace", spaceID: space.id) }
            }
        } message: { Text(String(localized: "仅可删除没有活动、其他成员或分享记录的空间。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
    }

    private func refresh() async {
        await store.loadSocialSpaces()
        do {
            let reply = try await store.socialRequest("invitations")
            invitations = reply["items"] as? [[String: Any]] ?? []
        } catch { actionError = watchDisplayError(error) }
    }

    private func run(_ action: String, spaceID: String? = nil, activityID: String? = nil,
                     fields: [String: Any] = [:]) async {
        actionError = nil
        do {
            _ = try await store.socialRequest(action, spaceID: spaceID, activityID: activityID, fields: fields)
            name = ""; editing = nil; deleting = nil
            await refresh()
        } catch { actionError = watchDisplayError(error) }
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
            if store.socialLoading { ProgressView(String(localized: "读取中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            if let error = store.socialError { Text(error).foregroundStyle(.red).font(.footnote) }
            if let actionError { Text(actionError).foregroundStyle(.red).font(.footnote) }
            ForEach(store.socialActivities) { activity in
                NavigationLink(activity.title, destination: WatchSocialPhotosView(spaceID: activity.sourceTenantId, activity: activity))
                if activity.canEdit {
                    Button(String(localized: "修改“\(activity.title)”名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { title = activity.title; editing = activity }
                    Button(String(localized: "删除“\(activity.title)”", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { deleting = activity }
                }
            }
            if store.socialActivities.isEmpty && !store.socialLoading && store.socialError == nil {
                Text(String(localized: "这个空间暂无活动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            TextField(String(localized: "新活动名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $title)
            Button(String(localized: "创建活动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await run("createActivity", fields: ["title": title]) } }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.loadSocialActivities(spaceID: space.id) } }
        }
        .navigationTitle(space.name)
        .task { await store.loadSocialActivities(spaceID: space.id) }
        .alert(String(localized: "修改活动名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField(String(localized: "活动名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $title)
            Button(String(localized: "保存", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                guard let activity = editing else { return }
                Task { await run("renameActivity", spaceID: activity.sourceTenantId, activityID: activity.id, fields: ["title": title]) }
            }
            Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .cancel) { editing = nil }
        }
        .confirmationDialog(String(localized: "确认删除活动？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(String(localized: "确认删除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) {
                guard let activity = deleting else { return }
                Task { await run("deleteActivity", spaceID: activity.sourceTenantId, activityID: activity.id) }
            }
        } message: { Text(String(localized: "仅可删除没有其他成员、照片或日常记录的活动。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
    }

    private func run(_ action: String, spaceID: String? = nil, activityID: String? = nil, fields: [String: Any] = [:]) async {
        actionError = nil
        do {
            _ = try await store.socialRequest(action, spaceID: spaceID ?? space.id, activityID: activityID, fields: fields)
            title = ""; editing = nil; deleting = nil
            await store.loadSocialActivities(spaceID: space.id)
        } catch { actionError = watchDisplayError(error) }
    }
}

struct WatchSocialPhotosView: View {
    let spaceID: String
    let activity: WatchSocialActivity
    var body: some View {
        List {
            NavigationLink(String(localized: "共享照片", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: WatchSocialAlbumView(spaceID: spaceID, activity: activity))
            NavigationLink(String(localized: "生活分享", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: WatchSocialMomentsView(spaceID: spaceID, activity: activity))
            NavigationLink(String(localized: "活动打卡", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: WatchSocialCheckInsView(spaceID: spaceID, activity: activity))
            NavigationLink(String(localized: "成员与邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: WatchSocialMembersView(spaceID: spaceID, activity: activity))
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
            PhotosPicker(String(localized: "共享手表照片", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $selectedPhoto, matching: .images)
                .disabled(sharing)
            Text(String(localized: "照片会以配对 iPhone 的账号共享；原图留在 iPhone，获取原图时请保持 iPhone 上的 Linko Moment 打开。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                .font(.footnote).foregroundStyle(.secondary)
            if sharing { ProgressView(String(localized: "共享中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            if store.socialLoading { ProgressView(String(localized: "读取中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
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
                        Text(String(localized: "暂无预览，请在 iPhone 查看", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if photo.canDelete {
                    Button(String(localized: "删除我的“\(photo.name)”", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { deleting = photo }
                }
            }
            if store.socialPhotos.isEmpty && !store.socialLoading && store.socialError == nil {
                Text(String(localized: "这场活动还没有照片", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            if store.socialPhotosHasMore {
                Button(String(localized: "加载更多照片", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    Task { await store.loadSocialPhotos(spaceID: spaceID, activityID: activity.id, more: true) }
                }.disabled(store.socialLoading)
            }
            Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.loadSocialPhotos(spaceID: spaceID, activityID: activity.id) } }
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
                        throw APIError(status: 0, message: String(localized: "无法读取所选照片。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    }
                    try await store.shareSocialPhoto(jpeg, spaceID: spaceID, activityID: activity.id)
                    await store.loadSocialPhotos(spaceID: spaceID, activityID: activity.id)
                } catch { actionError = watchDisplayError(error) }
            }
        }
        .confirmationDialog(String(localized: "删除共享照片？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(String(localized: "确认删除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) {
                guard let photo = deleting else { return }
                Task {
                    do {
                        _ = try await store.socialRequest("deletePhoto", spaceID: spaceID, activityID: activity.id,
                                                          fields: ["photoId": photo.id])
                        deleting = nil
                        await store.loadSocialPhotos(spaceID: spaceID, activityID: activity.id)
                    } catch { actionError = watchDisplayError(error) }
                }
            }
        } message: { Text(String(localized: "照片会从此活动撤销共享。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
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
            if loading { ProgressView(String(localized: "处理中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            TextField(String(localized: "分享今天的事", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $draft)
            Button(String(localized: "发布日常", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await publish() } }
                .disabled(loading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 1000)
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                VStack(alignment: .leading) {
                    Text(row["author"] as? String ?? "").font(.footnote).foregroundStyle(.secondary)
                    Text(row["text"] as? String ?? "")
                }
                if row["canDelete"] as? Bool == true {
                    Button(String(localized: "删除我的记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { deleting = row["id"] as? String }
                }
            }
            if rows.isEmpty && !loading && error == nil { Text(String(localized: "还没有分享的日常", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await load() } }
        }
        .navigationTitle(String(localized: "生活分享", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        .task { await load() }
        .confirmationDialog(String(localized: "删除这条日常？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(String(localized: "确认删除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) {
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
        } catch { self.error = watchDisplayError(error) }
    }
    private func publish() async {
        loading = true; error = nil; defer { loading = false }
        do {
            _ = try await store.socialRequest("createMoment", spaceID: spaceID, activityID: activity.id,
                                              fields: ["text": draft, "requestId": requestID.uuidString])
            draft = ""; requestID = UUID()
            let reply = try await store.socialRequest("moments", spaceID: spaceID, activityID: activity.id)
            rows = reply["items"] as? [[String: Any]] ?? []
        } catch { self.error = watchDisplayError(error) }
    }
    private func delete(_ id: String) async {
        loading = true; error = nil; defer { loading = false }
        do {
            _ = try await store.socialRequest("deleteMoment", spaceID: spaceID, activityID: activity.id,
                                              fields: ["itemId": id])
            deleting = nil
            let reply = try await store.socialRequest("moments", spaceID: spaceID, activityID: activity.id)
            rows = reply["items"] as? [[String: Any]] ?? []
        } catch { self.error = watchDisplayError(error) }
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
            if loading { ProgressView(String(localized: "处理中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            if let error = locator.error { Text(error).foregroundStyle(.red).font(.footnote) }
            if locator.fetching { ProgressView(String(localized: "定位中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            if let location = locator.location {
                Text(locator.address).font(.footnote)
                Label(String(format: String(localized: "海拔 %.1f 米", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), location.altitude), systemImage: "mountain.2.fill")
                    .font(.headline)
                TextField(String(localized: "备注（默认地址）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $note)
                Button(String(localized: "确认打卡", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await create() } }
                    .disabled(loading || note.count > 1000)
            }
            Button(String(localized: "获取当前位置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { locator.locate() }.disabled(locator.fetching || loading)
            if let latest = rows.first {
                Label(String(format: String(localized: "最近打卡海拔 %.1f 米", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), latest["altitudeMeters"] as? Double ?? 0), systemImage: "mountain.2.fill")
                    .font(.footnote.weight(.semibold))
            }
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                VStack(alignment: .leading) {
                    Text(row["author"] as? String ?? "").font(.footnote)
                    Text(row["note"] as? String ?? "")
                    Label(String(format: String(localized: "海拔 %.1f 米", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), row["altitudeMeters"] as? Double ?? 0), systemImage: "mountain.2")
                        .font(.footnote)
                    Text(row["address"] as? String ?? "").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if rows.isEmpty && !loading && error == nil { Text(String(localized: "还没有打卡记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await load() } }
        }
        .navigationTitle(String(localized: "活动打卡", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        .task { await load() }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let reply = try await store.socialRequest("checkins", spaceID: spaceID, activityID: activity.id)
            rows = reply["items"] as? [[String: Any]] ?? []
        } catch { self.error = watchDisplayError(error) }
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
        } catch { self.error = watchDisplayError(error) }
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
            if loading { ProgressView(String(localized: "处理中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            if let notice { Text(notice).font(.footnote) }
            Section(String(localized: "邀请参加", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                TextField(String(localized: "用户中心用户名", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $username)
                Button(String(localized: "发送邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await invite() } }
                    .disabled(loading || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(String(localized: "生成邀请链接", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await link() } }.disabled(loading)
                if let inviteURL { ShareLink(String(localized: "分享邀请链接", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), item: inviteURL) }
            }
            Section(String(localized: "活动成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                ForEach(members.indices, id: \.self) { index in
                    Text(members[index]["name"] as? String ?? "")
                }
                if members.isEmpty && !loading && error == nil { Text(String(localized: "暂无成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            }
            Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await load() } }
        }
        .navigationTitle(String(localized: "成员与邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        .task { await load() }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let reply = try await store.socialRequest("members", spaceID: spaceID, activityID: activity.id)
            members = reply["items"] as? [[String: Any]] ?? []
        } catch { self.error = watchDisplayError(error) }
    }
    private func invite() async {
        loading = true; error = nil; notice = nil; defer { loading = false }
        do {
            _ = try await store.socialRequest("inviteUsername", spaceID: spaceID, activityID: activity.id,
                                              fields: ["username": username])
            username = ""; notice = String(localized: "邀请已发送，等待对方确认。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        } catch { self.error = watchDisplayError(error) }
    }
    private func link() async {
        loading = true; error = nil; notice = nil; defer { loading = false }
        do {
            let reply = try await store.socialRequest("inviteLink", spaceID: spaceID, activityID: activity.id)
            guard let value = reply["url"] as? String, let url = URL(string: value) else {
                throw APIError(status: 0, message: String(localized: "邀请链接无效。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            }
            inviteURL = url; notice = String(localized: "链接七天内有效，请只分享给要邀请的人。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        } catch { self.error = watchDisplayError(error) }
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
        default: fetching = false; error = String(localized: "请在手表设置中允许位置访问。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard fetching else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: fetching = false; error = String(localized: "位置访问未获授权。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard fetching else { return }
        guard let current = locations.last(where: { $0.horizontalAccuracy >= 0 && $0.verticalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 120 }) else {
            fetching = false; error = String(localized: "没有获取到有效的位置和海拔，请重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return
        }
        geocoder.reverseGeocodeLocation(current) { [weak self] placemarks, _ in
            guard let self else { return }
            self.address = placemarks?.first?.name ?? String(format: "%.6f, %.6f", current.coordinate.latitude, current.coordinate.longitude)
            self.location = current
            self.fetching = false
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fetching = false; self.error = String(localized: "定位失败：\(watchDisplayError(error))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
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
                } else { ProgressView(String(localized: "读取照片", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                Text(photo.name).font(.footnote).multilineTextAlignment(.center)
            }
        }
        .navigationTitle(String(localized: "照片预览", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        .task {
            do { preview = try await store.socialPreview(spaceID: spaceID, activityID: activityID, photoID: photo.id) }
            catch { self.error = watchDisplayError(error) }
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
                Button(String(localized: "生成好友码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.makeFriendCode() } }
                if let friendCode = store.friendCode {
                    Text(friendCode.code).font(.title2.monospacedDigit()).privacySensitive()
                    Text(String(localized: "有效期至 \(localTime(friendCode.expiresAt))（当地时间）", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        .font(.footnote)
                }
                TextField(String(localized: "好友的认证码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $code)
                Button(String(localized: "添加好友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    Task { await store.addFriend(code: code); code = "" }
                }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let rows = leaderboard ? (store.friends?.leaderboard ?? []) : (store.friends?.friends ?? [])
            if rows.isEmpty { Text(leaderboard ? String(localized: "暂无排行", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "暂无好友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            ForEach(rows) { friend in
                VStack(alignment: .leading) {
                    Text(String(localized: "\(friend.rank.map { "\($0). " } ?? "")\(friend.name)\(friend.isSelf == true ? String(localized: " · 我", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : "")", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    Text(String(localized: "\(friend.score.formatted()) 分", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.green)
                }
            }
            Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.loadSection("friends") } }
        }.disabled(store.busy).navigationTitle(leaderboard ? String(localized: "好友积分榜", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "我的好友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .task { await store.loadSection("friends") }
    }

    private func localTime(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return String(localized: "请重新生成好友码", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AgentIdentityLanguage.current)
        formatter.timeZone = TimeZone.current
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
            Text(String(localized: "爸爸妈妈的闪光时刻", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.headline)
            if store.parents.isEmpty {
                Text(String(localized: "请家长先配置家庭成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                Button(String(localized: "重新加载", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.loadSection("parents") } }
            } else {
                Picker(String(localized: "想记录谁", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $parentID) {
                    Text(String(localized: "请选择", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag(0)
                    ForEach(store.parents) { Text($0.roleLabel).tag($0.id) }
                }
                TextField(String(localized: "发生了什么", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $content)
                Text(String(localized: "可使用手表系统听写输入，最多 500 字。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(String(localized: "保存暖心时刻", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    Task {
                        if await store.saveWarmMoment(parentID: parentID, content: content) { content = "" }
                    }
                }.disabled(parentID == 0 || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.count > 500)
            }
        }.disabled(store.busy).navigationTitle(String(localized: "暖心时刻", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
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
                Text(String(localized: "继续加油，每一点进步都值得被看见。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    .font(.footnote).foregroundStyle(.secondary)
            } else { Text(store.busy ? String(localized: "正在准备今天的鼓励…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "今天也要开心成长。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.loadSection("growth") } }
        }.disabled(store.busy).navigationTitle(String(localized: "今日鼓励", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .task { await store.loadSection("growth") }
    }
}

struct FaceSettingsView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            Text(String(localized: "设置 Linko Moment App 内的主题外观。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
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
            Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await store.loadSection("settings") } }
        }.disabled(store.busy).navigationTitle(String(localized: "表盘设置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .task { await store.loadSection("settings") }
    }
}
