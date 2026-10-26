import SwiftUI
import CoreLocation
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import AVKit
import ImageIO
import Photos
import MapKit

enum DearPhotoLocation {
    static func label(for item: PhotosPickerItem, data: Data) -> String? {
        if let embedded = label(in: data) { return embedded }
        guard let identifier = item.itemIdentifier,
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized || PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited,
              let location = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject?.location else { return nil }
        return coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    static func label(in data: Data) -> String? {
        if let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           let latitude = (gps[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue,
           let longitude = (gps[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue {
            let signedLatitude = (gps[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased() == "S" ? -latitude : latitude
            let signedLongitude = (gps[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased() == "W" ? -longitude : longitude
            return coordinates(latitude: signedLatitude, longitude: signedLongitude)
        }
        return nil
    }

    private static func coordinates(latitude: Double, longitude: Double) -> String? {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        return String(format: "%@ %.5f，%@ %.5f", latitude < 0 ? "南纬" : "北纬", abs(latitude), longitude < 0 ? "西经" : "东经", abs(longitude))
    }
}

private struct DearPickedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let ext = received.file.pathExtension.lowercased() == "mp4" ? "mp4" : "mov"
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

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
    func number(_ key: String) -> Double { data[key] as? Double ?? 0 }
    static func list(_ value: Any) throws -> [DearRecord] {
        guard let values = value as? [[String: Any]] else { throw APIError.message("Linko Social 返回的数据格式不正确。") }
        return values.map { DearRecord(data: $0) }
    }
}

private struct DearActivityMapPoint: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let systemImage: String

    static func points(checkIns: [DearRecord], photos: [DearRecord]) -> [Self] {
        let visits = checkIns.compactMap { item -> Self? in
            guard let coordinate = coordinate(latitude: item.data["latitude"], longitude: item.data["longitude"]) else { return nil }
            let address = item.text("address")
            let subtitle = "\(address.isEmpty ? item.dateText("createdAt") : address) · 海拔 \(String(format: "%.1f", item.number("altitudeMeters"))) 米"
            return Self(id: "checkin-\(item.id)", title: item.text("authorName").isEmpty ? "活动打卡" : "\(item.text("authorName"))的打卡",
                        subtitle: subtitle, coordinate: coordinate, systemImage: "mappin.circle.fill")
        }
        let pictures = photos.compactMap { item -> Self? in
            guard let coordinate = photoCoordinate(item.text("locationName")) else { return nil }
            let title = item.text("originalFileName").isEmpty ? "活动照片" : item.text("originalFileName")
            return Self(id: "photo-\(item.id)", title: title,
                        subtitle: "\(item.text("sourceDisplayName")) · \(item.dateText("createdAt"))",
                        coordinate: coordinate, systemImage: item.text("contentType").hasPrefix("video/") ? "video.fill" : "photo.fill")
        }
        return visits + pictures
    }

    private static func coordinate(latitude: Any?, longitude: Any?) -> CLLocationCoordinate2D? {
        guard let latitude = (latitude as? NSNumber)?.doubleValue,
              let longitude = (longitude as? NSNumber)?.doubleValue,
              latitude.isFinite, longitude.isFinite,
              abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func photoCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.components(separatedBy: "，")
        guard parts.count == 2 else { return nil }
        let latitudeText = parts[0].trimmingCharacters(in: .whitespaces)
        let longitudeText = parts[1].trimmingCharacters(in: .whitespaces)
        let south = latitudeText.hasPrefix("南纬")
        let west = longitudeText.hasPrefix("西经")
        guard (south || latitudeText.hasPrefix("北纬")), (west || longitudeText.hasPrefix("东经")),
              let latitude = Double(latitudeText.dropFirst(2).trimmingCharacters(in: .whitespaces)),
              let longitude = Double(longitudeText.dropFirst(2).trimmingCharacters(in: .whitespaces)) else { return nil }
        return coordinate(latitude: NSNumber(value: south ? -latitude : latitude),
                          longitude: NSNumber(value: west ? -longitude : longitude))
    }
}

private struct DearActivityMapView: View {
    let title: String
    let points: [DearActivityMapPoint]
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedPointID: String?

    private var selectedPoint: DearActivityMapPoint? { points.first { $0.id == selectedPointID } }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                ForEach(points) { point in
                    Annotation(point.title, coordinate: point.coordinate) {
                        Button { selectedPointID = point.id } label: {
                            Image(systemName: point.systemImage)
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(9)
                                .background(point.id == selectedPointID ? Color.orange : Color.teal, in: Circle())
                        }
                        .accessibilityLabel("\(point.title)，\(point.subtitle)")
                    }
                }
            }
            .mapControls { MapCompass(); MapScaleView() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let selectedPoint {
                Label(selectedPoint.title, systemImage: selectedPoint.systemImage).font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 12)
                Text(selectedPoint.subtitle)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
            List(points) { point in
                Button {
                    selectedPointID = point.id
                    cameraPosition = .region(MKCoordinateRegion(center: point.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.title).lineLimit(1)
                            Text(point.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    } icon: { Image(systemName: point.systemImage) }
                }
            }
            .frame(height: min(CGFloat(points.count) * 70 + 16, 220))
        }
        .navigationTitle("\(title) · 地图")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fitAllPoints() }
    }

    private func fitAllPoints() {
        guard let first = points.first else { return }
        let latitudes = points.map(\.coordinate.latitude)
        let longitudes = points.map(\.coordinate.longitude)
        let minLat = latitudes.min() ?? first.coordinate.latitude
        let maxLat = latitudes.max() ?? first.coordinate.latitude
        let minLon = longitudes.min() ?? first.coordinate.longitude
        let maxLon = longitudes.max() ?? first.coordinate.longitude
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.02),
                                   longitudeDelta: max((maxLon - minLon) * 1.5, 0.02))))
    }
}

struct DearSocialView: View {
    @ObservedObject var store: FamilyStore
    var showLogout = false
    @State private var spaces: [DearRecord] = []
    @State private var joinedActivities: [DearRecord] = []
    @State private var activities: [DearRecord] = []
    @State private var photos: [DearRecord] = []
    @State private var selectedPhoto: DearRecord?
    @State private var showingPhoto = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @AppStorage("dearPhotoViewMode") private var photoViewMode = "grid"
    @State private var photoLocationName = ""
    @State private var selectingPhotoDownloads = false
    @State private var selectedPhotoIDs = Set<String>()
    @State private var batchOriginalURLs: [URL] = []
    @State private var batchDownloadProgress = 0.0
    @State private var batchDownloading = false
    @State private var batchDownloadError = ""
    @State private var moments: [DearRecord] = []
    @State private var checkIns: [DearRecord] = []
    @StateObject private var checkInLocator = DearCheckInLocator()
    @State private var showingCheckIn = false
    @State private var selectedCheckIn: DearRecord?
    @State private var pendingCheckIn = false
    @State private var checkInNote = ""
    @State private var checkInRequestID = UUID()
    @State private var activityMembers: [DearRecord] = []
    @State private var spaceMembers: [DearRecord] = []
    @State private var showingSpaceMembers = false
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
    @State private var editedActivityDescription = ""
    @State private var editedActivityDate = Date()
    @State private var showingSpaceRename = false
    @State private var showingSpaceCreate = false
    @State private var showingSpaceDelete = false
    @State private var showingActivityDelete = false
    @State private var memberToRemove: DearRecord?
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
    private var allActivities: [DearRecord] { activities + joinedActivities.filter { joined in !activities.contains { $0.id == joined.id } } }
    private var selectedActivity: DearRecord? { allActivities.first { $0.id == activityId } }
    private var visibleSpaces: [DearRecord] { spaces.filter { $0.text("role") == "owner" || $0.text("role") == "member" } }
    private var activityTenantId: String { selectedActivity?.text("sourceTenantId") ?? spaceId }
    private var isActivityCreator: Bool {
        guard let creator = selectedActivity?.text("createdBySubject"), !creator.isEmpty else { return false }
        return activityMembers.contains { $0.flag("isSelf") && $0.subject == creator }
    }
    private func activityDate(_ item: DearRecord) -> String {
        let key = item.text("startsAt").isEmpty ? "createdAt" : "startsAt"
        return (key == "createdAt" ? "创建于 " : "活动日期 ") + item.dateText(key)
    }
    private func activityDateValue(_ item: DearRecord) -> Date {
        let value = item.text("startsAt").isEmpty ? item.text("createdAt") : item.text("startsAt")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? Date()
    }

    var body: some View {
        NavigationStack {
            List {
                if !error.isEmpty || !notice.isEmpty {
                    Section {
                        if !error.isEmpty { Text(error).foregroundStyle(.red) }
                        if !notice.isEmpty { Text(notice).foregroundStyle(.teal) }
                    }
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
                Section("我的空间") {
                    if visibleSpaces.isEmpty { Text("请用右上角“…”新增个人空间。") .foregroundStyle(.secondary) }
                    else {
                        HStack {
                            Picker("", selection: $spaceId) {
                                ForEach(visibleSpaces) { item in Text(item.text("name")).tag(item.id) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Menu {
                                if selectedSpace?.text("role") == "owner" {
                                    Button("编辑基本信息", systemImage: "pencil") {
                                        editedSpaceName = selectedSpace?.text("name") ?? ""
                                        showingSpaceRename = true
                                    }
                                }
                                Button("查看空间成员", systemImage: "person.2") { run { try await loadSpaceMembers() } }
                                if selectedSpace?.text("role") == "owner" {
                                    Button("删除空间", systemImage: "trash", role: .destructive) { showingSpaceDelete = true }
                                }
                            } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("管理当前空间") }
                            .disabled(busy)
                        }
                    }
                    Text("每个人管理自己的空间，同一活动可收藏到多个空间。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if selectedSpace?.text("role") == "owner" || !joinedActivities.isEmpty {
                    Section("活动列表") {
                        if activityLoading { Text("正在读取已有活动…").foregroundStyle(.secondary) }
                        if !activityError.isEmpty { Text(activityError).foregroundStyle(.red) }
                        if allActivities.isEmpty && !activityLoading && activityError.isEmpty { Text("还没有活动").foregroundStyle(.secondary) }
                        else {
                            ForEach(allActivities) { item in
                                HStack {
                                    Button {
                                        activityId = item.id
                                        showingActivity = true
                                    } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.text("title")).font(.body.weight(.medium))
                                            Text(activityDate(item)).font(.caption).foregroundStyle(.secondary)
                                            if !item.text("description").isEmpty {
                                                Text(item.text("description")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            }
                                        }
                                        Spacer()
                                    }
                                    }.buttonStyle(.plain)
                                    Menu {
                                        Button("活动管理", systemImage: "gearshape") {
                                            activityId = item.id
                                            editedActivityName = item.text("title")
                                            editedActivityDescription = item.text("description")
                                            editedActivityDate = activityDateValue(item)
                                            showingActivityManagement = true
                                        }
                                        if item.flag("isBookmarked") {
                                            Button("取消收藏", systemImage: "bookmark.slash", role: .destructive) { run { try await removeBookmark(item) } }
                                        } else if selectedSpace?.text("role") == "owner" && item.text("sourceTenantId") != spaceId && !activities.contains(where: { $0.id == item.id }) {
                                            Button("收藏到当前空间", systemImage: "bookmark") { run { try await addBookmark(item) } }
                                        }
                                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("管理\(item.text("title"))") }
                                    .disabled(busy)
                                }
                            }
                        }
                        if selectedSpace?.text("role") == "owner" {
                            HStack {
                                TextField("例如：周末野餐", text: $activityName)
                                Button("添加") { run { try await createActivity() } }
                                    .disabled(busy || activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("新增空间", systemImage: "plus") { spaceName = ""; showingSpaceCreate = true }
                        if selectedSpace?.text("role") == "owner" {
                            Button("修改空间名称", systemImage: "pencil") { editedSpaceName = selectedSpace?.text("name") ?? ""; showingSpaceRename = true }
                            Button("删除空间", systemImage: "trash", role: .destructive) { showingSpaceDelete = true }
                        }
                        Button("刷新", systemImage: "arrow.clockwise") { run { try await load() } }
                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("空间菜单") }
                    .disabled(busy)
                }
                if showLogout { ToolbarItem(placement: .topBarLeading) { Button("退出") { store.logout() } } }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
            .onChange(of: spaceId) { _, _ in activityId = ""; showingActivity = false; showingPhoto = false; selectedPhoto = nil; showingActivityManagement = false; activities = []; photos = []; activityError = ""; activityLoading = true; run { try await loadActivities() } }
            .navigationDestination(isPresented: $showingActivity) { activityDetail }
            .sheet(isPresented: $showingActivityManagement) { activityManagement }
            .sheet(isPresented: $showingSpaceMembers) {
                NavigationStack {
                    List {
                        if selectedSpace?.text("role") == "owner" {
                            Text("先邀请对方加入本空间的活动，再从活动访客设为空间成员。空间成员可查看本空间的所有原生活动；收藏活动仍遵循原活动权限。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(spaceMembers) { member in
                            HStack {
                                Text(member.text("displayName"))
                                Spacer()
                                Text(member.text("role") == "owner" ? "空间主人" : member.text("role") == "member" ? "空间成员" : "活动访客")
                                    .foregroundStyle(.secondary)
                                if selectedSpace?.text("role") == "owner" && member.text("role") != "owner" {
                                    Menu {
                                        Button(member.text("role") == "member" ? "改为活动访客" : "设为空间成员") {
                                            run { try await setSpaceMemberRole(member,
                                                role: member.text("role") == "member" ? "guest" : "member") }
                                        }
                                    } label: { Image(systemName: "ellipsis.circle") }
                                }
                            }
                        }
                    }
                    .navigationTitle("空间成员")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showingSpaceMembers = false } } }
                }
            }
            .onChange(of: activityId) { _, _ in photos = []; moments = []; checkIns = []; activityMembers = []; run { try await loadDetails() } }
            .alert("新增空间", isPresented: $showingSpaceCreate) {
                TextField("空间名称", text: $spaceName)
                Button("取消", role: .cancel) { }
                Button("创建") { run { try await createSpace() } }
            } message: { Text("此空间由你管理，可收藏参加过的活动。") }
            .alert("修改空间名称", isPresented: $showingSpaceRename) {
                TextField("空间名称", text: $editedSpaceName)
                Button("取消", role: .cancel) { }
                Button("保存") { run { try await renameSpace() } }
            } message: { Text("更新你的空间名称。") }
            .confirmationDialog("删除空间「\(selectedSpace?.text("name") ?? "")」？", isPresented: $showingSpaceDelete, titleVisibility: .visible) {
                Button("确认删除空间", role: .destructive) { run { try await deleteSpace() } }
                Button("取消", role: .cancel) { }
            } message: { Text("仅可删除没有活动、其他成员或分享记录的空间。") }
        }
    }

    @ViewBuilder private func photoLink(_ photo: DearRecord) -> some View {
        let path = base + "tenants/\(activityTenantId)/activities/\(activityId)/native-photos/\(photo.id)/thumbnail"
        if selectingPhotoDownloads {
            Button {
                if !selectedPhotoIDs.insert(photo.id).inserted { selectedPhotoIDs.remove(photo.id) }
                batchOriginalURLs = []
            } label: {
                photoCard(photo, path: path)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: selectedPhotoIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(selectedPhotoIDs.contains(photo.id) ? .teal : .white)
                            .padding(7)
                    }
            }.buttonStyle(.plain).disabled(batchDownloading)
        } else {
            Button {
                selectedPhoto = photo
                showingPhoto = true
            } label: { photoCard(photo, path: path) }
            .buttonStyle(.plain)
        }
    }

    private func photoCard(_ photo: DearRecord, path: String) -> some View {
        let isGrid = photoViewMode == "grid"
        return HStack(alignment: .top, spacing: 10) {
                DearPhotoPreview(store: store, path: path)
                    .frame(width: isGrid ? nil : 112, height: isGrid ? 145 : 112)
                    .frame(maxWidth: isGrid ? .infinity : nil)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(photo.text("sourceDisplayName").isEmpty ? "活动成员" : photo.text("sourceDisplayName"))
                            Text(photo.text("createdAt").isEmpty ? "正在分享" : photo.dateText("createdAt"))
                            Text(photo.text("locationName").isEmpty ? "地点未记录" : photo.text("locationName"))
                                .lineLimit(2).minimumScaleFactor(0.8)
                        }
                        .font(.system(size: 10)).foregroundStyle(.white)
                        .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if !isGrid {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(photo.text("originalFileName")).font(.subheadline.bold()).lineLimit(2)
                        if photo.text("contentType").hasPrefix("video/") { Label("视频", systemImage: "play.rectangle.fill").font(.caption) }
                        if !photo.flag("thumbnailAvailable") { Text("预览尚未就绪，点开可重试").font(.caption).foregroundStyle(.secondary) }
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(photo.text("originalFileName"))，\(photo.text("sourceDisplayName"))，\(photo.dateText("createdAt"))，\(photo.text("locationName").isEmpty ? "地点未记录" : photo.text("locationName"))")
    }

    private var activityDetail: some View {
        List {
            if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
            if !notice.isEmpty { Section { Text(notice).foregroundStyle(.teal) } }
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activities.contains(where: { $0.id == activityId }) ? (selectedSpace?.text("name") ?? "我的空间") : "已参加的活动")
                            .font(.caption).foregroundStyle(.teal)
                        Text(selectedActivity?.text("title") ?? "活动详情").font(.title2.bold())
                        Text("邀请、照片、日常和成员仅属于这场活动。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            Section {
                let points = DearActivityMapPoint.points(checkIns: checkIns, photos: photos)
                NavigationLink {
                    DearActivityMapView(title: selectedActivity?.text("title") ?? "活动", points: points)
                } label: {
                    Label("活动地图", systemImage: "map")
                }
                .disabled(points.isEmpty)
                if points.isEmpty {
                    Text("暂无带坐标的打卡或照片。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("显示 \(checkIns.count) 条打卡中的定位记录，以及带照片定位的共享内容。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
                if let selectedActivity {
                    Section("照片与视频 · \(selectedActivity.text("title"))") {
                        PhotosPicker("多选共享 iPhone 照片或视频", selection: $selectedPhotos, maxSelectionCount: 50,
                                     matching: .any(of: [.images, .videos]), preferredItemEncoding: .current)
                            .disabled(busy)
                        TextField("照片地点（可选，供活动成员查看）", text: $photoLocationName)
                            .textInputAutocapitalization(.sentences)
                        Text("优先显示照片自带的定位；无定位时使用填写地点。")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("显示方式", selection: $photoViewMode) {
                            Text("网格").tag("grid")
                            Text("列表").tag("list")
                        }.pickerStyle(.segmented)
                        Button(selectingPhotoDownloads ? "完成多选" : "多选下载原文件") {
                            selectingPhotoDownloads.toggle()
                            selectedPhotoIDs.removeAll(); batchOriginalURLs = []; batchDownloadError = ""; batchDownloadProgress = 0
                        }.disabled(batchDownloading)
                        if selectingPhotoDownloads {
                            Text("已选 \(selectedPhotoIDs.count) 项") .font(.caption).foregroundStyle(.secondary)
                            Button(batchDownloading ? "正在获取原文件…" : "获取选中原文件") {
                                Task { await downloadSelectedPhotos() }
                            }.disabled(selectedPhotoIDs.isEmpty || batchDownloading)
                            if batchDownloading || batchDownloadProgress > 0 && batchDownloadProgress < 1 {
                                ProgressView(value: batchDownloadProgress).accessibilityLabel("多选原文件接收进度")
                            }
                            if !batchOriginalURLs.isEmpty {
                                ShareLink(items: batchOriginalURLs) {
                                    Label("保存或分享已获取的 \(batchOriginalURLs.count) 项", systemImage: "square.and.arrow.up")
                                }
                            }
                            if !batchDownloadError.isEmpty { Text(batchDownloadError).font(.caption).foregroundStyle(.red) }
                        }
                        Text("原图留在此 iPhone；对方获取原图时，请保持 Linko Moment 打开。")
                            .font(.caption).foregroundStyle(.secondary)
                        if photos.isEmpty { Text("还没有分享的照片或视频").foregroundStyle(.secondary) }
                        if photoViewMode == "grid" {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(photos) { photo in photoLink(photo) }
                            }.listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        } else {
                            ForEach(photos) { photo in photoLink(photo) }
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
                        Button {
                            checkInNote = ""; checkInRequestID = UUID(); pendingCheckIn = true
                            checkInLocator.locate()
                        } label: {
                            Label(pendingCheckIn ? "正在定位并打卡…" : "在当前位置打卡", systemImage: "location.circle")
                        }.disabled(busy || pendingCheckIn)
                        if let latest = checkIns.first {
                            Label(String(format: "最近打卡海拔 %.1f 米", latest.number("altitudeMeters")), systemImage: "mountain.2.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        ForEach(checkIns) { checkIn in
                            Button {
                                pendingCheckIn = false
                                selectedCheckIn = checkIn
                                checkInNote = checkIn.text("note")
                                error = ""
                                checkInLocator.clear()
                                showingCheckIn = true
                            } label: { VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(checkIn.text("authorName")).font(.subheadline.bold())
                                    Spacer()
                                    Text(checkIn.dateText("createdAt")).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(checkIn.text("note"))
                                Label(String(format: "海拔 %.1f 米", checkIn.number("altitudeMeters")), systemImage: "mountain.2")
                                    .font(.subheadline)
                                Text(checkIn.text("address")).font(.caption).foregroundStyle(.secondary)
                                if let latitude = checkIn.data["latitude"] as? Double,
                                   let longitude = checkIn.data["longitude"] as? Double {
                                    Text(String(format: "%.6f, %.6f", latitude, longitude))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }}.buttonStyle(.plain).padding(.vertical, 4).disabled(busy || pendingCheckIn)
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
        .navigationDestination(isPresented: $showingPhoto) {
            if let selectedPhoto {
                DearPhotoDetailView(store: store, photo: selectedPhoto, spaceID: activityTenantId, activityID: activityId,
                                    path: base + "tenants/\(activityTenantId)/activities/\(activityId)/native-photos/\(selectedPhoto.id)/thumbnail",
                                    canDelete: selectedPhoto.text("sourceSubject") == activityMembers.first(where: { $0.flag("isSelf") })?.subject,
                                    onDeleted: { localCopyRemoved in
                                        showingPhoto = false
                                        photos.removeAll { $0.id == selectedPhoto.id }
                                        if !localCopyRemoved { self.error = "分享已删除，本机副本暂未清理；App 会继续重试。" }
                                        Task {
                                            do { try await loadPhotos() }
                                            catch { self.error = "相册刷新失败：\(error.localizedDescription)" }
                                        }
                                    })
            }
        }
        .sheet(isPresented: $showingCheckIn) { checkInSheet }
        .onChange(of: checkInLocator.location?.timestamp) { _, value in
            guard pendingCheckIn, value != nil else { return }
            pendingCheckIn = false
            run { try await createCheckIn() }
        }
        .onChange(of: checkInLocator.error) { _, value in
            guard pendingCheckIn, !value.isEmpty else { return }
            pendingCheckIn = false
            error = value
        }
        .onDisappear { pendingCheckIn = false }
        .onChange(of: activityId) { _, _ in showingActivityManagement = false; showingPhoto = false; selectedPhoto = nil; inviteLink = ""; inviteUsername = ""; momentDraft = ""; momentRequestID = UUID(); photoLocationName = ""; selectingPhotoDownloads = false; selectedPhotoIDs.removeAll(); batchOriginalURLs = [] }
        .onChange(of: selectedPhotos) { _, selected in
            guard !selected.isEmpty else { return }
            let targetSpace = activityTenantId, targetActivity = activityId
            run {
                defer { selectedPhotos = [] }
                var completed = 0
                var failures: [String] = []
                for (index, item) in selected.enumerated() {
                    do {
                        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                            guard let video = try await item.loadTransferable(type: DearPickedVideo.self) else {
                                throw APIError.message("无法读取所选视频。")
                            }
                            defer { try? FileManager.default.removeItem(at: video.url) }
                            try await store.photoSource.publishVideo(at: video.url, spaceID: targetSpace, activityID: targetActivity, locationName: photoLocationName)
                        } else {
                            guard let data = try await item.loadTransferable(type: Data.self) else {
                                throw APIError.message("无法读取所选照片。")
                            }
                            let embedded = DearPhotoLocation.label(for: item, data: data)
                            try await store.photoSource.publish(data, spaceID: targetSpace, activityID: targetActivity,
                                                                name: "iPhone照片", locationName: embedded ?? photoLocationName)
                        }
                        completed += 1
                    } catch {
                        failures.append("第 \(index + 1) 项：\(error.localizedDescription)")
                    }
                }
                try await loadPhotos()
                notice = "已共享 \(completed) 项；请保持此 iPhone 可以响应原文件请求。"
                if !failures.isEmpty { error = failures.joined(separator: "；") }
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
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
                Section("当前位置") {
                    if checkInLocator.fetching { ProgressView("正在获取位置和地址…") }
                    if !checkInLocator.error.isEmpty { Text(checkInLocator.error).foregroundStyle(.red) }
                    if let selectedCheckIn {
                        Text(checkInLocator.location == nil ? selectedCheckIn.text("address") : checkInLocator.address)
                        Text(String(format: "纬度 %.6f，经度 %.6f", checkInLocator.location?.coordinate.latitude ?? selectedCheckIn.number("latitude"), checkInLocator.location?.coordinate.longitude ?? selectedCheckIn.number("longitude")))
                        Text(String(format: "海拔 %.1f 米", checkInLocator.location?.altitude ?? selectedCheckIn.number("altitudeMeters")))
                    }
                    if selectedCheckIn?.flag("canEdit") == true {
                        Button("重新定位") { checkInLocator.locate() }.disabled(checkInLocator.fetching)
                    }
                }
                Section("备注") {
                    TextField("默认填写当前位置地址", text: $checkInNote, axis: .vertical)
                        .lineLimit(2...5)
                        .disabled(selectedCheckIn?.flag("canEdit") != true)
                    Text("留空时使用上方地址作为备注。") .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(selectedCheckIn?.flag("canEdit") == true ? "修改打卡" : "打卡详情")
            .onChange(of: checkInLocator.address) { _, address in
                if checkInNote.isEmpty { checkInNote = address }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { showingCheckIn = false } }
                if selectedCheckIn?.flag("canEdit") == true {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { run { try await updateCheckIn() } }
                            .disabled(checkInLocator.fetching || busy || checkInNote.count > 1000)
                    }
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
                    Section("基本信息") {
                        TextField("活动名称", text: $editedActivityName)
                        TextField("活动介绍", text: $editedActivityDescription, axis: .vertical)
                            .lineLimit(2...5)
                        DatePicker("活动日期", selection: $editedActivityDate, displayedComponents: .date)
                        Button("保存基本信息") { run { try await updateActivity() } }
                            .disabled(busy || editedActivityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedActivityDescription.count > 2000)
                        Button("删除活动", systemImage: "trash", role: .destructive) {
                            showingActivityDelete = true
                        }.disabled(busy)
                    }
                }
                if selectedActivity?.flag("canEdit") == true {
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
                            if isActivityCreator {
                                Button("移出活动", role: .destructive) { memberToRemove = member }.disabled(busy)
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
            .confirmationDialog("删除活动「\(selectedActivity?.text("title") ?? "")」？", isPresented: $showingActivityDelete, titleVisibility: .visible) {
                Button("确认删除活动", role: .destructive) { run { try await deleteActivity() } }
                Button("取消", role: .cancel) { }
            } message: { Text("仅可删除没有其他成员、照片或日常记录的活动；已发出的邀请会失效。") }
            .confirmationDialog("将「\(memberToRemove?.text("displayName") ?? "")」移出活动？", isPresented: Binding(
                get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }), titleVisibility: .visible) {
                Button("确认移出", role: .destructive) {
                    guard let member = memberToRemove else { return }
                    memberToRemove = nil
                    run { try await removeActivityMember(member) }
                }
                Button("取消", role: .cancel) { memberToRemove = nil }
            } message: { Text("移出后，对方将无法查看这场活动的新内容；已有邀请链接仍可再次用于加入。") }
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
        joinedActivities = try DearRecord.list(await store.call(base + "activities/joined"))
        await store.photoSource.cacheShareActivities(joinedActivities.map(\.data))
        await store.photoSource.importSharedItems()
        spaces = loaded
        let previousSpace = spaceId
        if !loaded.contains(where: { $0.id == spaceId && ($0.text("role") == "owner" || $0.text("role") == "member") }) {
            spaceId = loaded.first(where: { $0.text("role") == "owner" || $0.text("role") == "member" })?.id ?? ""
        }
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
        do { loaded = try DearRecord.list(await store.call(base + "spaces/\(requestedSpace)/activities")) }
        catch {
            activityError = "活动读取失败：\(error.localizedDescription)"
            throw error
        }
        guard requestedSpace == spaceId else { return }
        activities = loaded
        activityError = ""
        let previousActivity = activityId
        if !loaded.contains(where: { $0.id == activityId }) && !joinedActivities.contains(where: { $0.id == activityId }) { activityId = ""; showingActivity = false }
        if activityId == previousActivity && !activityId.isEmpty {
            do { try await loadDetails() }
            catch { self.error = "活动内容暂时无法读取：\(error.localizedDescription)" }
        }
    }
    private func loadSpaceMembers() async throws {
        guard !spaceId.isEmpty else { return }
        spaceMembers = try DearRecord.list(await store.call(base + "tenants/\(spaceId)/members"))
        showingSpaceMembers = true
    }
    private func setSpaceMemberRole(_ member: DearRecord, role: String) async throws {
        guard selectedSpace?.text("role") == "owner",
              let encoded = member.subject.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        _ = try await store.call(base + "tenants/\(spaceId)/members/\(encoded)", method: "PATCH", body: ["role": role])
        try await loadSpaceMembers()
    }
    private func loadDetails() async throws {
        try await loadPhotos(); try await loadMoments(); try await loadCheckIns(); try await loadMembers()
    }
    private func loadPhotos() async throws {
        guard !activityTenantId.isEmpty, !activityId.isEmpty else { return }
        var loaded = try DearRecord.list(await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/live/photos"))
        if loaded.contains(where: { !$0.flag("thumbnailAvailable") }) {
            await store.photoSource.refreshPreviews(spaceID: activityTenantId, activityID: activityId, rows: loaded.map(\.data))
            loaded = try DearRecord.list(await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/live/photos"))
        }
        if await store.photoSource.refreshLocations(spaceID: activityTenantId, activityID: activityId, rows: loaded.map(\.data)) {
            loaded = try DearRecord.list(await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/live/photos"))
        }
        photos = loaded
    }
    private func downloadSelectedPhotos() async {
        let selected = photos.filter { selectedPhotoIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let targetSpace = activityTenantId, targetActivity = activityId
        batchDownloading = true; batchDownloadProgress = 0; batchDownloadError = ""; batchOriginalURLs = []
        defer { batchDownloading = false }
        var failures: [String] = []
        for (index, photo) in selected.enumerated() {
            do {
                let url = try await store.photoSource.downloadOriginal(photoID: photo.id,
                    spaceID: targetSpace, activityID: targetActivity) { fraction in
                    batchDownloadProgress = (Double(index) + fraction) / Double(selected.count)
                }
                batchOriginalURLs.append(url)
            } catch { failures.append("\(photo.text("originalFileName"))：\(error.localizedDescription)") }
            batchDownloadProgress = Double(index + 1) / Double(selected.count)
        }
        if !failures.isEmpty { batchDownloadError = failures.joined(separator: "；") }
    }
    private func loadMoments() async throws {
        guard !activityTenantId.isEmpty, !activityId.isEmpty else { return }
        moments = try DearRecord.list(await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/moments"))
    }
    private func loadCheckIns() async throws {
        guard !activityTenantId.isEmpty, !activityId.isEmpty else { return }
        checkIns = try DearRecord.list(await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/checkins"))
    }
    private func createCheckIn() async throws {
        guard let location = checkInLocator.location, !checkInLocator.fetching else { throw APIError.message("请先获取当前位置。") }
        let note = checkInNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= 1000 else { throw APIError.message("备注不能超过 1000 字。") }
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/checkins", method: "POST", body: [
            "requestId": checkInRequestID.uuidString,
            "latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude,
            "altitudeMeters": location.altitude, "address": checkInLocator.address,
            "note": note.isEmpty ? checkInLocator.address : note
        ])
        checkInRequestID = UUID(); try await loadCheckIns()
        notice = String(format: "打卡已保存，海拔 %.1f 米。", location.altitude)
    }
    private func updateCheckIn() async throws {
        guard let selectedCheckIn, selectedCheckIn.flag("canEdit") else { throw APIError.message("只能修改自己的打卡。") }
        let note = checkInNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= 1000 else { throw APIError.message("备注不能超过 1000 字。") }
        let location = checkInLocator.location
        let address = location == nil ? selectedCheckIn.text("address") : checkInLocator.address
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/checkins/\(selectedCheckIn.id)", method: "PATCH", body: [
            "latitude": location?.coordinate.latitude ?? selectedCheckIn.number("latitude"),
            "longitude": location?.coordinate.longitude ?? selectedCheckIn.number("longitude"),
            "altitudeMeters": location?.altitude ?? selectedCheckIn.number("altitudeMeters"),
            "address": address, "note": note.isEmpty ? address : note
        ])
        showingCheckIn = false; self.selectedCheckIn = nil; try await loadCheckIns(); notice = "打卡已更新。"
    }
    private func loadMembers() async throws {
        guard !activityTenantId.isEmpty, !activityId.isEmpty else { return }
        activityMembers = try DearRecord.list(await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/members"))
    }
    private func removeActivityMember(_ member: DearRecord) async throws {
        guard isActivityCreator, !member.flag("isSelf"),
              let encoded = member.subject.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { throw APIError.message("只有活动创建者可以移除其他成员。") }
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/members/\(encoded)", method: "DELETE")
        try await loadMembers()
        notice = "已将成员移出活动。"
    }
    private func loadRelationships() async throws {
        relationships = try DearRecord.list(await store.call(base + "relationships"))
    }
    private func requestFriend(_ member: DearRecord) async throws {
        _ = try await store.call(base + "relationships/requests", method: "POST", body: ["targetSubject": member.subject, "tenantId": activityTenantId, "activityId": activityId])
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
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/moments", method: "POST", body: ["text": body, "requestId": momentRequestID.uuidString])
        momentDraft = ""; momentRequestID = UUID(); try await loadMoments(); notice = "日常已发布。"
    }
    private func deleteMoment(_ moment: DearRecord) async throws {
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/moments/\(moment.id)", method: "DELETE")
        try await loadMoments(); notice = "日常已删除。"
    }
    private func createSpace() async throws {
        let value = try await store.call(base + "tenants", method: "POST", body: ["name": spaceName.trimmingCharacters(in: .whitespacesAndNewlines)])
        let item = DearRecord(data: value as? [String: Any] ?? [:])
        spaceName = ""; try await load(); spaceId = item.id; notice = "空间已创建。"
    }
    private func addBookmark(_ item: DearRecord) async throws {
        guard selectedSpace?.text("role") == "owner" else { throw APIError.message("请先选择自己的空间。") }
        _ = try await store.call(base + "spaces/\(spaceId)/bookmarks", method: "POST", body: ["sourceTenantId": item.text("sourceTenantId"), "activityId": item.id])
        try await loadActivities(); notice = "活动已收藏到空间。"
    }
    private func removeBookmark(_ item: DearRecord) async throws {
        guard selectedSpace?.text("role") == "owner" else { throw APIError.message("只有空间所有者可以取消收藏。") }
        _ = try await store.call(base + "spaces/\(spaceId)/bookmarks/\(item.text("sourceTenantId"))/\(item.id)", method: "DELETE")
        try await loadActivities(); notice = "已取消收藏，原活动仍在。"
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
        let value = try await store.call(base + "tenants/\(spaceId)/activities", method: "POST", body: [
            "title": activityName.trimmingCharacters(in: .whitespacesAndNewlines), "description": "",
            "startsAt": ISO8601DateFormatter().string(from: Date())
        ])
        let item = DearRecord(data: value as? [String: Any] ?? [:])
        activityName = ""; try await loadActivities(); activityId = item.id; showingActivity = true; notice = "活动已创建。"
    }
    private func updateActivity() async throws {
        guard selectedActivity?.flag("canEdit") == true else { throw APIError.message("只有活动组织者可以修改基本信息。") }
        let name = editedActivityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && name.count <= 200 else { throw APIError.message("请填写不超过 200 字的活动名称。") }
        guard editedActivityDescription.count <= 2000 else { throw APIError.message("活动介绍不能超过 2000 字。") }
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)", method: "PATCH", body: [
            "title": name, "description": editedActivityDescription,
            "startsAt": ISO8601DateFormatter().string(from: editedActivityDate)
        ])
        try await load(); notice = "活动基本信息已更新。"
    }
    private func deleteActivity() async throws {
        guard selectedActivity?.flag("canEdit") == true else { throw APIError.message("只有活动组织者可以删除活动。") }
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)", method: "DELETE")
        showingActivityManagement = false; showingActivity = false; activityId = ""
        try await load(); notice = "活动已删除。"
    }
    private func inviteByName() async throws {
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/invites/username", method: "POST", body: ["username": inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines)])
        inviteUsername = ""; notice = "邀请已发出，等待对方确认。"
    }
    private func createInviteLink() async throws {
        let value = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/invites/link", method: "POST", body: [:])
        guard let token = (value as? [String: Any])?["token"] as? String,
              let safe = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw APIError.message("邀请链接无效。") }
        inviteLink = "https://happylife.ai.xmkurt.com/dear?invite=\(safe)"
    }
    private func accept(_ invitation: DearRecord) async throws {
        let me = try await store.call(base + "me") as? [String: Any] ?? [:]
        guard let username = me["username"] as? String,
              let safe = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw APIError.message("无法确认用户名。") }
        _ = try await store.call(base + "tenants/\(invitation.text("tenantId"))/activities/\(invitation.text("activityId"))/invites/username/\(safe)/accept", method: "POST", body: [:])
        try await load(); activityId = invitation.text("activityId"); showingActivity = true; notice = "已加入共同活动，可收藏到自己的空间。"
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

    func clear() {
        geocoder.cancelGeocode()
        location = nil; address = ""; error = ""; fetching = false
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
            guard self.fetching else { return }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped().background(.quaternary)
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
    let canDelete: Bool
    let onDeleted: (Bool) -> Void
    @State private var image: UIImage?
    @State private var error: String?
    @State private var originalURL: URL?
    @State private var originalImage: UIImage?
    @State private var originalError: String?
    @State private var fetchingOriginal = false
    @State private var transferProgress = 0.0
    @State private var deleting = false
    @State private var showingDelete = false
    private var isVideo: Bool { photo.text("contentType").hasPrefix("video/") }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isVideo, let originalURL {
                    VideoPlayer(player: AVPlayer(url: originalURL)).frame(minHeight: 240)
                } else if let image = originalImage ?? image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let error {
                    ContentUnavailableView("无法显示照片预览", systemImage: "photo.badge.exclamationmark",
                                           description: Text(error))
                    Button("重试") { Task { await load() } }
                } else { ProgressView("正在加载照片") }
                Text(photo.text("originalFileName")).font(.headline)
                Text("分享者：\(photo.text("sourceDisplayName"))").font(.subheadline).foregroundStyle(.secondary)
                Text("分享时间：\(photo.dateText("createdAt"))").font(.subheadline).foregroundStyle(.secondary)
                Text("地点：\(photo.text("locationName").isEmpty ? "未记录" : photo.text("locationName"))")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let originalURL {
                    ShareLink(item: originalURL) { Label("分享原文件", systemImage: "square.and.arrow.up") }
                } else {
                    Button {
                        Task { await fetchOriginal() }
                    } label: {
                        Label(fetchingOriginal ? "正在实时接收：\(Int(transferProgress * 100))%" : originalError == nil ? "获取原文件" : "继续获取原文件", systemImage: "arrow.down.circle")
                    }.disabled(fetchingOriginal)
                }
                if fetchingOriginal || transferProgress > 0 && transferProgress < 1 {
                    ProgressView(value: transferProgress)
                        .accessibilityLabel("原文件接收进度")
                }
                if let originalError { Text(originalError).font(.footnote).foregroundStyle(.red) }
                if canDelete {
                    Button("删除分享", role: .destructive) { showingDelete = true }.disabled(deleting)
                }
                Text("原文件从分享者设备传来，获取时请保持对方的分享应用打开。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle(isVideo ? "视频" : "照片")
        .confirmationDialog("删除这项分享？", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("删除分享", role: .destructive) { Task { await deleteSharedMedia() } }
            Button("取消", role: .cancel) { }
        } message: { Text("活动成员将无法再获取此文件；iPhone 相册中的原文件不会删除。") }
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
        fetchingOriginal = true; transferProgress = 0; originalError = nil
        defer { fetchingOriginal = false }
        do {
            let url = try await store.photoSource.downloadOriginal(photoID: photo.id, spaceID: spaceID, activityID: activityID) {
                transferProgress = $0
            }
            if !isVideo {
                guard let decoded = UIImage(contentsOfFile: url.path) else { throw APIError.message("原图无法显示。") }
                originalImage = decoded
            }
            originalURL = url
        } catch { originalError = error.localizedDescription }
    }

    private func deleteSharedMedia() async {
        deleting = true; originalError = nil
        defer { deleting = false }
        do {
            let localCopyRemoved = try await store.photoSource.revoke(photoID: photo.id, spaceID: spaceID, activityID: activityID)
            onDeleted(localCopyRemoved)
        } catch { originalError = error.localizedDescription }
    }
}
