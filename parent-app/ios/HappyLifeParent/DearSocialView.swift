import SwiftUI
import AgentIdentity
import CoreLocation
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import AVKit
import ImageIO
import Photos
import MapKit

private struct DearCamera: UIViewControllerRepresentable {
    enum Mode: String, Identifiable {
        case photo, video
        var id: String { rawValue }
    }
    let mode: Mode
    let completion: (Result<(URL, Bool)?, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [mode == .video ? UTType.movie.identifier : UTType.image.identifier]
        picker.cameraCaptureMode = mode == .video ? .video : .photo
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 180
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (Result<(URL, Bool)?, Error>) -> Void
        init(completion: @escaping (Result<(URL, Bool)?, Error>) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(.success(nil)) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            do {
                let video = info[.mediaType] as? String == UTType.movie.identifier
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + (video ? ".mov" : ".jpg"))
                if video, let source = info[.mediaURL] as? URL {
                    // The camera's temporary URL is only valid during this callback.
                    try FileManager.default.copyItem(at: source, to: url)
                } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) {
                    try data.write(to: url, options: .atomic)
                } else { throw APIError.message("无法读取拍摄内容，请重试。") }
                completion(.success((url, video)))
            } catch { completion(.failure(error)) }
        }
    }
}

private struct DearCaptureTarget {
    let spaceID: String
    let activityID: String
    let locationName: String
    let sessionToken: String
}

private struct DearCapturedMedia {
    let url: URL
    let video: Bool
    let target: DearCaptureTarget
    var savedToLibrary = false
}

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
        return date.map { "\($0.formatted(date: .abbreviated, time: .shortened))（当地时间）" } ?? "时间未知"
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
    let photo: DearRecord?

    static func points(checkIns: [DearRecord], photos: [DearRecord]) -> [Self] {
        let visits = checkIns.compactMap { item -> Self? in
            guard let coordinate = coordinate(latitude: item.data["latitude"], longitude: item.data["longitude"]) else { return nil }
            let address = item.text("address")
            let subtitle = "\(address.isEmpty ? item.dateText("createdAt") : address) · 海拔 \(String(format: "%.1f", item.number("altitudeMeters"))) 米"
            return Self(id: "checkin-\(item.id)", title: item.text("authorName").isEmpty ? "活动打卡" : "\(item.text("authorName"))的打卡",
                        subtitle: subtitle, coordinate: coordinate, systemImage: "mappin.circle.fill", photo: nil)
        }
        let pictures = photos.compactMap { item -> Self? in
            guard let coordinate = photoCoordinate(item.text("locationName")) else { return nil }
            let title = item.text("originalFileName").isEmpty ? "活动照片" : item.text("originalFileName")
            return Self(id: "photo-\(item.id)", title: title,
                        subtitle: "\(item.text("sourceDisplayName")) · \(item.dateText("createdAt"))",
                        coordinate: coordinate, systemImage: item.text("contentType").hasPrefix("video/") ? "video.fill" : "photo.fill",
                        photo: item)
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
    @ObservedObject var store: FamilyStore
    let title: String
    let spaceID: String
    let activityID: String
    let points: [DearActivityMapPoint]
    let photos: [DearRecord]
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedPointID: String?
    @State private var selectedPhoto: DearRecord?
    @State private var showingPhoto = false

    private var selectedPoint: DearActivityMapPoint? { points.first { $0.id == selectedPointID } }
    private func thumbnailPath(_ photo: DearRecord) -> String {
        "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)/native-photos/\(photo.id)/thumbnail"
    }

    private func openPhoto(_ photo: DearRecord) {
        selectedPhoto = photo
        showingPhoto = true
    }

    var body: some View {
        VStack(spacing: 0) {
            if points.isEmpty {
                ContentUnavailableView("暂无地图位置", systemImage: "map",
                                       description: Text("照片没有记录坐标时仍可在下方查看，但无法固定到地图上。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Map(position: $cameraPosition) {
                    ForEach(points) { point in
                        Annotation(point.title, coordinate: point.coordinate) {
                            Button { selectedPointID = point.id } label: {
                                if let photo = point.photo {
                                    DearPhotoPreview(store: store, path: thumbnailPath(photo))
                                        .frame(width: 66, height: 66)
                                        .overlay(alignment: .bottomTrailing) {
                                            if point.systemImage == "video.fill" {
                                                Image(systemName: "play.circle.fill")
                                                    .font(.title3).foregroundStyle(.white)
                                                    .shadow(color: .black, radius: 2)
                                            }
                                        }
                                        .overlay(RoundedRectangle(cornerRadius: 10)
                                            .stroke(point.id == selectedPointID ? Color.orange : Color.white, lineWidth: 3))
                                        .shadow(radius: 3)
                                } else {
                                    Image(systemName: point.systemImage)
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .padding(9)
                                        .background(point.id == selectedPointID ? Color.orange : Color.teal, in: Circle())
                                }
                            }
                            .accessibilityLabel("\(point.title)，\(point.subtitle)")
                        }
                    }
                }
                .mapControls { MapCompass(); MapScaleView() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let selectedPoint {
                HStack(spacing: 10) {
                    if let photo = selectedPoint.photo {
                        DearPhotoPreview(store: store, path: thumbnailPath(photo))
                            .frame(width: 54, height: 54)
                    } else { Image(systemName: selectedPoint.systemImage).font(.title2) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedPoint.title).font(.headline).lineLimit(1)
                        Text(selectedPoint.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if let photo = selectedPoint.photo {
                        Button("查看") { openPhoto(photo) }.font(.subheadline)
                    }
                }
                .padding(12)
            }
            if !photos.isEmpty {
                HStack {
                    Text("活动照片与视频").font(.subheadline.bold())
                    Spacer()
                    let unlocated = photos.count - points.filter { $0.photo != nil }.count
                    if unlocated > 0 { Text("\(unlocated) 项未定位").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.horizontal)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(photos) { photo in
                            Button { openPhoto(photo) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    DearPhotoPreview(store: store, path: thumbnailPath(photo))
                                        .frame(width: 82, height: 82)
                                    Text(photo.text("originalFileName").isEmpty ? "照片" : photo.text("originalFileName"))
                                        .font(.caption2).lineLimit(1).frame(width: 82, alignment: .leading)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 112)
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
        .fullScreenCover(isPresented: $showingPhoto) {
            if let selectedPhoto {
                DearPhotoGalleryView(store: store, photos: photos, initialPhotoID: selectedPhoto.id,
                                     spaceID: spaceID, activityID: activityID, allowsDeletion: false,
                                     onDeleted: { _, _ in })
            }
        }
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

private struct DearTimelineEntry: Identifiable {
    let id: String
    enum Kind { case photo, moment, checkIn }
    let kind: Kind
    var checkIn: Bool { kind == .checkIn }
    let record: DearRecord
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
    @State private var cameraMode: DearCamera.Mode?
    @State private var cameraTarget: DearCaptureTarget?
    @State private var capturedMedia: DearCapturedMedia?
    @State private var requestingCamera = false
    @State private var cameraError = ""
    @State private var showingCameraError = false
    @AppStorage("dearPhotoViewMode") private var photoViewMode = "grid"
    @State private var photoLocationName = ""
    @State private var selectingPhotoDownloads = false
    @State private var selectedPhotoIDs = Set<String>()
    @State private var batchOriginalURLs: [URL] = []
    @State private var batchDownloadProgress = 0.0
    @State private var batchDownloading = false
    @State private var batchDeleting = false
    @State private var showingBatchDelete = false
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
    @State private var showingActivityCreate = false
    @State private var newActivityDescription = ""
    @State private var newActivityDate = Date()
    @State private var activityCreateError = ""
    @State private var showingMomentCreate = false
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
    private var allActivities: [DearRecord] {
        let combined = activities + joinedActivities.filter { joined in !activities.contains { $0.id == joined.id } }
        return combined.sorted { left, right in
            let leftDate = ActivityListDate.value(startsAt: left.text("startsAt"), createdAt: left.text("createdAt")) ?? .distantPast
            let rightDate = ActivityListDate.value(startsAt: right.text("startsAt"), createdAt: right.text("createdAt")) ?? .distantPast
            return leftDate == rightDate ? left.id < right.id : leftDate > rightDate
        }
    }
    private var selectedActivity: DearRecord? { allActivities.first { $0.id == activityId } }
    private var visibleSpaces: [DearRecord] { spaces.filter { $0.text("role") == "owner" || $0.text("role") == "member" } }
    private var activityTenantId: String { selectedActivity?.text("sourceTenantId") ?? spaceId }
    private var isActivityCreator: Bool {
        guard let creator = selectedActivity?.text("createdBySubject"), !creator.isEmpty else { return false }
        return activityMembers.contains { $0.flag("isSelf") && $0.subject == creator }
    }
    private func activityDate(_ item: DearRecord) -> String {
        ActivityListDate.label(startsAt: item.text("startsAt"), createdAt: item.text("createdAt"))
    }
    private func activityDateValue(_ item: DearRecord) -> Date {
        ActivityListDate.value(startsAt: item.text("startsAt"), createdAt: item.text("createdAt")) ?? Date()
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
                    Section {
                        Text("日期按设备当地时区显示").font(.caption).foregroundStyle(.secondary)
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
                    } header: {
                        HStack {
                            Text("活动列表")
                            Spacer()
                            if selectedSpace?.text("role") == "owner" {
                                Button {
                                    activityName = ""; newActivityDescription = ""; newActivityDate = Date(); activityCreateError = ""
                                    showingActivityCreate = true
                                } label: { Label("新增", systemImage: "plus.circle.fill") }
                                .font(.subheadline.weight(.semibold)).disabled(busy)
                            }
                        }.textCase(nil)
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
                ToolbarItem(placement: .topBarTrailing) { MomentNotificationButton(notifications: store.notifications) }
                if showLogout { ToolbarItem(placement: .topBarLeading) { Button("退出") { store.logout() } } }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
            .onChange(of: spaceId) { _, _ in activityId = ""; showingActivity = false; showingPhoto = false; selectedPhoto = nil; showingActivityManagement = false; activities = []; photos = []; activityError = ""; activityLoading = true; run { try await loadActivities() } }
            .navigationDestination(isPresented: $showingActivity) { activityDetail }
            .sheet(isPresented: $showingActivityManagement) { activityManagement }
            .sheet(isPresented: $showingActivityCreate) { activityCreateSheet }
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
            }.buttonStyle(.plain).disabled(batchDownloading || batchDeleting)
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
        let nickname = photo.text("sourceDisplayName").isEmpty ? "活动成员" : photo.text("sourceDisplayName")
        return HStack(alignment: .top, spacing: 12) {
            DearPhotoPreview(store: store, path: path)
                .frame(width: isGrid ? nil : 112, height: isGrid ? 240 : 112)
                .frame(maxWidth: isGrid ? .infinity : nil)
                .overlay(alignment: .topLeading) {
                    Label(nickname, systemImage: "person.crop.circle.fill")
                        .font(.caption.weight(.semibold)).lineLimit(1)
                        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule()).padding(7).padding(.trailing, selectingPhotoDownloads ? 44 : 0)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .bottom) {
                        if !photo.text("locationName").isEmpty {
                            Label(photo.text("locationName"), systemImage: "mappin")
                                .font(.caption2).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        if photo.text("contentType").hasPrefix("video/") { Image(systemName: "play.circle.fill").font(.title2) }
                    }
                    .foregroundStyle(.white).padding(8)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if !isGrid {
                VStack(alignment: .leading, spacing: 6) {
                    Text(nickname).font(.subheadline.bold()).lineLimit(1)
                    Text(photo.text("originalFileName")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text(photo.dateText("createdAt")).font(.caption2).foregroundStyle(.secondary)
                    if !photo.flag("thumbnailAvailable") { Text("点开查看原文件").font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(nickname)，\(photo.text("originalFileName"))，\(photo.dateText("createdAt"))")
    }

    private var activityCreateSheet: some View {
        NavigationStack {
            Form {
                if !activityCreateError.isEmpty { Text(activityCreateError).foregroundStyle(.red) }
                Section("活动信息") {
                    TextField("活动名称，例如周末野餐", text: $activityName)
                    DatePicker("活动日期", selection: $newActivityDate, displayedComponents: .date)
                    TextField("活动介绍（可选）", text: $newActivityDescription, axis: .vertical).lineLimit(3...5)
                }
                Section { Text("创建到\(selectedSpace?.text("name") ?? "当前空间") · 日期按当地时区保存") .font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("新增活动")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showingActivityCreate = false }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task {
                            guard !busy else { return }
                            busy = true; activityCreateError = ""; defer { busy = false }
                            do { try await createActivity(); showingActivityCreate = false }
                            catch { activityCreateError = error.localizedDescription }
                        }
                    }.disabled(busy || activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }

    private var momentCreateSheet: some View {
        NavigationStack {
            Form {
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
                TextField("分享这一刻…", text: $momentDraft, axis: .vertical).lineLimit(5...10)
                    .onChange(of: momentDraft) { _, _ in momentRequestID = UUID() }
            }
            .navigationTitle("日常分享")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showingMomentCreate = false }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发布") { run { try await publishMoment(); showingMomentCreate = false } }
                        .disabled(busy || momentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var activityPhotoSection: some View {
        Section {
            HStack {
                Button { Task { await openCamera(.photo) } } label: { Label("拍照", systemImage: "camera") }
                Spacer()
                Button { Task { await openCamera(.video) } } label: { Label("录制视频", systemImage: "video") }
            }.buttonStyle(.borderless)
                .disabled(busy || requestingCamera || capturedMedia != nil || batchDeleting || batchDownloading)
            Text("拍摄确认后自动保存到系统相册并共享到当前活动；视频最长 3 分钟。")
                .font(.caption).foregroundStyle(.secondary)
            if let capturedMedia {
                Text(capturedMedia.savedToLibrary ? "已保存到系统相册，尚未共享到活动。" : "拍摄内容尚未保存并共享，请重试。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("重试保存并共享") { shareCapturedMedia() }
                    Spacer()
                    ShareLink(item: capturedMedia.url) { Label("另存或分享", systemImage: "square.and.arrow.up") }
                    Button("移除", role: .destructive) {
                        try? FileManager.default.removeItem(at: capturedMedia.url)
                        self.capturedMedia = nil
                    }
                }.buttonStyle(.borderless).disabled(busy)
            }
            HStack {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 50, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                    Label("分享照片 / 视频", systemImage: "photo.badge.plus")
                }.disabled(busy || batchDeleting || batchDownloading)
                Spacer()
                Picker("显示方式", selection: $photoViewMode) {
                    Image(systemName: "rectangle").tag("grid").accessibilityLabel("大图")
                    Image(systemName: "list.bullet").tag("list").accessibilityLabel("紧凑")
                }.pickerStyle(.segmented).frame(width: 105)
            }
            DisclosureGroup("添加照片地点（可选）") {
                TextField("照片地点", text: $photoLocationName)
                Text("优先使用照片自带定位；未记录定位时使用此处填写的地点。")
                    .font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline)
            if !photos.isEmpty {
                Button(selectingPhotoDownloads ? "完成多选" : "多选管理") {
                    selectingPhotoDownloads.toggle(); selectedPhotoIDs.removeAll(); batchOriginalURLs = []; batchDownloadError = ""; batchDownloadProgress = 0
                }.disabled(batchDownloading || batchDeleting)
            }
            if selectingPhotoDownloads {
                Text("已选 \(selectedPhotoIDs.count) 项").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(batchDownloading ? "正在获取…" : "获取原文件") { Task { await downloadSelectedPhotos() } }
                        .disabled(selectedPhotoIDs.isEmpty || batchDownloading || batchDeleting)
                    Spacer()
                    Button(batchDeleting ? "正在删除…" : "删除分享", role: .destructive) { showingBatchDelete = true }
                        .disabled(!canDeleteSelectedPhotos || batchDownloading || batchDeleting)
                }
                Text("分享者和活动 owner 可删除分享；iPhone 相册原件保留。") .font(.caption).foregroundStyle(.secondary)
                if batchDownloading || batchDownloadProgress > 0 && batchDownloadProgress < 1 { ProgressView(value: batchDownloadProgress) }
                if !batchOriginalURLs.isEmpty { ShareLink(items: batchOriginalURLs) { Label("保存或分享 \(batchOriginalURLs.count) 项", systemImage: "square.and.arrow.up") } }
                if !batchDownloadError.isEmpty { Text(batchDownloadError).font(.caption).foregroundStyle(.red) }
            }
        } header: { Text("发布与管理").textCase(nil) }
    }

    private var activityTimeline: [DearTimelineEntry] {
        let shared = moments.map { DearTimelineEntry(id: "moment:" + $0.id, kind: .moment, record: $0) }
        let located = checkIns.map { DearTimelineEntry(id: "checkin:" + $0.id, kind: .checkIn, record: $0) }
        let media = photos.map { DearTimelineEntry(id: "photo:" + $0.id, kind: .photo, record: $0) }
        return (shared + located + media).sorted {
            let left = ActivityListDate.parse($0.record.text("createdAt")) ?? .distantPast
            let right = ActivityListDate.parse($1.record.text("createdAt")) ?? .distantPast
            return left == right ? $0.id < $1.id : left > right
        }
    }

    private var activityTimelineSection: some View {
        Section("活动动态 · 照片、打卡与日常") {
            HStack {
                Button { momentDraft = ""; momentRequestID = UUID(); error = ""; showingMomentCreate = true } label: { Label("写日常", systemImage: "square.and.pencil") }
                Spacer()
                Button {
                    checkInNote = ""; checkInRequestID = UUID(); pendingCheckIn = true; checkInLocator.locate()
                } label: { Label(pendingCheckIn ? "正在定位…" : "打卡", systemImage: "location.circle") }
            }.disabled(busy || pendingCheckIn)
            ForEach(activityTimeline, id: \.id) { entry in
                if entry.kind == .photo {
                    VStack(alignment: .leading, spacing: 10) {
                        photoLink(entry.record)
                        Text(entry.record.dateText("createdAt")).font(.caption2).foregroundStyle(.secondary)
                        DearPhotoCommentsView(store: store, spaceID: activityTenantId, activityID: activityId, photoID: entry.record.id)
                            .id("\(activityTenantId)/\(activityId)/\(entry.record.id)")
                    }.padding(.vertical, 8)
                } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(entry.record.text("authorName"), systemImage: entry.checkIn ? "location.fill" : "text.bubble.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(entry.checkIn ? "打卡" : "分享").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(entry.record.text(entry.checkIn ? "note" : "text")).textSelection(.enabled)
                    if entry.checkIn {
                        if !entry.record.text("address").isEmpty { Label(entry.record.text("address"), systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Label(String(format: "海拔 %.1f 米", entry.record.number("altitudeMeters")), systemImage: "mountain.2").font(.caption)
                            Spacer()
                            Button(entry.record.flag("canEdit") ? "查看 / 编辑" : "查看打卡") {
                                pendingCheckIn = false; selectedCheckIn = entry.record; checkInNote = entry.record.text("note")
                                error = ""; checkInLocator.clear(); showingCheckIn = true
                            }.font(.caption).disabled(busy || pendingCheckIn)
                        }
                    } else if entry.record.flag("canDelete") {
                        Button("删除日常分享", role: .destructive) { run { try await deleteMoment(entry.record) } }.font(.caption)
                    }
                    Text(entry.record.dateText("createdAt")).font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
                }
            }
            if activityTimeline.isEmpty { Text("还没有动态，拍照、写日常或打卡，留下活动的第一刻。") .foregroundStyle(.secondary).font(.subheadline) }
        }
    }

    private var activityDetail: some View {
        List {
            if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
            if !notice.isEmpty { Section { Text(notice).foregroundStyle(.teal) } }
            if let selectedActivity {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedActivity.text("title")).font(.title2.bold())
                        HStack { Label(activityDate(selectedActivity), systemImage: "calendar"); Spacer(); Label("\(activityMembers.count) 位成员", systemImage: "person.2") }
                            .font(.caption).foregroundStyle(.secondary)
                        if !selectedActivity.text("description").isEmpty { Text(selectedActivity.text("description")).font(.subheadline).foregroundStyle(.secondary) }
                        Button {
                            editedActivityName = selectedActivity.text("title"); editedActivityDescription = selectedActivity.text("description")
                            editedActivityDate = activityDateValue(selectedActivity); showingActivityManagement = true
                        } label: { Label("管理与邀请", systemImage: "person.badge.plus") }.font(.subheadline)
                    }.padding(.vertical, 4)
                }
                activityPhotoSection
                activityTimelineSection
                Section("活动地图") {
                    let points = DearActivityMapPoint.points(checkIns: checkIns, photos: photos)
                    NavigationLink {
                        DearActivityMapView(store: store, title: selectedActivity.text("title"), spaceID: activityTenantId, activityID: activityId, points: points, photos: photos)
                    } label: {
                        Label("查看地图 · \(checkIns.count) 次打卡 · \(photos.count) 项照片与视频", systemImage: "map.fill").font(.subheadline)
                    }.disabled(points.isEmpty && photos.isEmpty)
                }
                Section {
                    DisclosureGroup("活动成员与好友关系") {
                        ForEach(activityMembers, id: \.subject) { member in
                            HStack {
                                Text(member.text("displayName")); Spacer()
                                if member.flag("isSelf") { Text("我").foregroundStyle(.secondary) }
                                else if let relation = relationships.first(where: { $0.text("peerSubject") == member.subject }) {
                                    Text(relation.text("status") == "accepted" ? "朋友" : "待确认").foregroundStyle(.secondary)
                                }
                            }.font(.subheadline)
                        }
                        Text("好友关系需要双方确认，可在活动管理中发起申请。") .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .readablePage()
        .navigationTitle(selectedActivity?.text("title") ?? "活动详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = URL(string: "https://happylife.ai.xmkurt.com/dear/spaces/\(activityTenantId)/activities/\(activityId)") {
                    ShareLink(item: url, subject: Text(selectedActivity?.text("title") ?? "活动")) {
                        Label("分享活动链接", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingPhoto) {
            if let selectedPhoto {
                DearPhotoGalleryView(store: store, photos: photos, initialPhotoID: selectedPhoto.id,
                                     spaceID: activityTenantId, activityID: activityId,
                                     allowsDeletion: true,
                                     onDeleted: { photoID, localCopyRemoved in
                                         photos.removeAll { $0.id == photoID }
                                         if !localCopyRemoved { self.error = "分享已删除，本机副本暂未清理；App 会继续重试。" }
                                         Task {
                                             do { try await loadPhotos() }
                                             catch { self.error = "相册刷新失败：\(error.localizedDescription)" }
                                         }
                                     })
            }
        }
        .confirmationDialog("删除选中的 \(selectedPhotoIDs.count) 项分享？", isPresented: $showingBatchDelete, titleVisibility: .visible) {
            Button("删除选中的分享", role: .destructive) { Task { await deleteSelectedPhotos() } }
            Button("取消", role: .cancel) { }
        } message: { Text("活动成员将无法再获取这些文件；iPhone 相册中的原文件不会删除。") }
        .sheet(isPresented: $showingCheckIn) { checkInSheet }
        .sheet(isPresented: $showingMomentCreate) { momentCreateSheet }
        .fullScreenCover(item: $cameraMode, onDismiss: { shareCapturedMedia() }) { mode in
            DearCamera(mode: mode) { result in
                switch result {
                case .success(let media):
                    if let (url, video) = media, let target = cameraTarget {
                        capturedMedia = DearCapturedMedia(url: url, video: video, target: target)
                    }
                case .failure(let failure):
                    cameraError = failure.localizedDescription; showingCameraError = true
                }
                cameraMode = nil
            }.ignoresSafeArea()
        }
        .alert("拍摄提示", isPresented: $showingCameraError) {
            Button("好", role: .cancel) { }
            Button("打开设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } message: { Text(cameraError) }
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

    @MainActor private func openCamera(_ mode: DearCamera.Mode) async {
        guard !busy, !requestingCamera, capturedMedia == nil,
              let token = store.identity.accessToken, !activityId.isEmpty else { return }
        requestingCamera = true
        defer { requestingCamera = false }
        let target = DearCaptureTarget(spaceID: activityTenantId, activityID: activityId,
                                       locationName: photoLocationName, sessionToken: token)
        do {
            guard UIImagePickerController.isSourceTypeAvailable(.camera),
                  UIImagePickerController.availableMediaTypes(for: .camera)?.contains(mode == .video ? UTType.movie.identifier : UTType.image.identifier) == true else {
                throw APIError.message("此设备不支持所选拍摄方式，请从相册选择照片或视频。")
            }
            let cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
            guard cameraAllowed else { throw APIError.message("请在设置中允许使用相机，以拍摄照片或视频。") }
            if mode == .video {
                let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
                guard microphoneAllowed else { throw APIError.message("请在设置中允许使用麦克风，以录制有声音的视频。") }
            }
            let library = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard library == .authorized || library == .limited else {
                throw APIError.message("请在设置中允许添加照片，以保存拍摄的照片和视频。")
            }
            guard token == store.identity.accessToken, target.activityID == activityId, showingActivity else { return }
            cameraTarget = target
            cameraMode = mode
        } catch { cameraError = error.localizedDescription; showingCameraError = true }
    }

    private func shareCapturedMedia() {
        guard let capture = capturedMedia, !busy else { return }
        busy = true; error = ""; notice = ""
        Task {
            defer { busy = false }
            do {
                guard capture.target.sessionToken == store.identity.accessToken else {
                    throw APIError.message("登录状态已变化，拍摄内容未共享。请另存到相册，再使用当前账号选择共享。")
                }
                if !capture.savedToLibrary {
                    try await PHPhotoLibrary.shared().performChanges {
                        if capture.video {
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: capture.url)
                        } else {
                            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: capture.url)
                        }
                    }
                    capturedMedia?.savedToLibrary = true
                }
                guard capture.target.sessionToken == store.identity.accessToken else { throw CancellationError() }
                do {
                    if capture.video {
                        try await store.photoSource.publishVideo(at: capture.url, spaceID: capture.target.spaceID,
                                                                activityID: capture.target.activityID, locationName: capture.target.locationName)
                    } else {
                        let data = try Data(contentsOf: capture.url, options: .mappedIfSafe)
                        try await store.photoSource.publish(data, spaceID: capture.target.spaceID, activityID: capture.target.activityID,
                                                            name: "拍摄照片.jpg", locationName: capture.target.locationName)
                    }
                } catch {
                    throw APIError.message("已保存到系统相册，共享未完成：\(error.localizedDescription)。可点击重试保存并共享。")
                }
                capturedMedia = nil
                try? FileManager.default.removeItem(at: capture.url)
                notice = "已保存到系统相册并共享到活动；请保持此 iPhone 可以响应原文件请求。"
                if activityId == capture.target.activityID { try await loadPhotos() }
            } catch { self.error = error.localizedDescription }
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
    private var canDeleteSelectedPhotos: Bool {
        guard !selectedPhotoIDs.isEmpty else { return false }
        let selected = photos.filter { selectedPhotoIDs.contains($0.id) }
        return selected.count == selectedPhotoIDs.count && selected.allSatisfy { $0.flag("canDelete") }
    }

    private func deleteSelectedPhotos() async {
        guard canDeleteSelectedPhotos, !batchDeleting, !batchDownloading else { return }
        let selected = photos.filter { selectedPhotoIDs.contains($0.id) }
        let targetSpace = activityTenantId, targetActivity = activityId
        batchDeleting = true; batchDownloadError = ""; batchOriginalURLs = []
        defer { batchDeleting = false }
        var failures: [String] = []
        var deleted = 0
        var pendingCleanup = false
        for photo in selected {
            do {
                let cleaned = try await store.photoSource.revoke(photoID: photo.id, spaceID: targetSpace, activityID: targetActivity)
                deleted += 1
                pendingCleanup = pendingCleanup || !cleaned
                if targetSpace == activityTenantId && targetActivity == activityId {
                    photos.removeAll { $0.id == photo.id }
                    selectedPhotoIDs.remove(photo.id)
                }
            } catch { failures.append("\(photo.text("originalFileName"))：\(error.localizedDescription)") }
        }
        guard targetSpace == activityTenantId && targetActivity == activityId else { return }
        notice = "已删除 \(deleted) 项分享。" + (pendingCleanup ? "部分本机副本暂未清理，App 会继续重试。" : "")
        do { try await loadPhotos() } catch { failures.append("相册刷新失败：\(error.localizedDescription)") }
        batchDownloadError = failures.joined(separator: "；")
    }

    private func downloadSelectedPhotos() async {
        let selected = photos.filter { selectedPhotoIDs.contains($0.id) }
        guard !selected.isEmpty, !batchDownloading, !batchDeleting else { return }
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
        let name = activityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200, newActivityDescription.count <= 2000 else { throw APIError.message("活动名称须为 1 至 200 字，介绍不超过 2000 字。") }
        let value = try await store.call(base + "tenants/\(spaceId)/activities", method: "POST", body: [
            "title": activityName.trimmingCharacters(in: .whitespacesAndNewlines), "description": newActivityDescription,
            "startsAt": ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: newActivityDate))
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

private struct DearPhotoCommentsView: View {
    @ObservedObject var store: FamilyStore
    let spaceID: String
    let activityID: String
    let photoID: String
    @State private var comments: [DearRecord] = []
    @State private var draft = ""
    @State private var requestID = UUID()
    @State private var busy = false
    @State private var failure = ""
    @State private var loaded = false
    @State private var hasMore = false
    @State private var nextSkip = 0
    @State private var expanded = false
    private var route: String { "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)/native-photos/\(photoID)/comments" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("照片点评", systemImage: "text.bubble").font(.subheadline.weight(.semibold))
            if !loaded && failure.isEmpty { ProgressView("正在加载点评…").font(.caption) }
            ForEach(expanded ? comments : Array(comments.prefix(3))) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(comment.text("authorName")).font(.caption.bold())
                        Spacer()
                        if comment.flag("canDelete") {
                            Button("删除") { perform { _ = try await store.call(route + "/" + comment.id, method: "DELETE"); try await load(reset: true) } }
                                .font(.caption).disabled(busy)
                        }
                    }
                    Text(comment.text("text")).font(.subheadline).textSelection(.enabled)
                    Text(comment.dateText("createdAt")).font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 3)
            }
            if comments.count > 3 {
                Button(expanded ? "收起点评" : "展开点评") { expanded.toggle() }.font(.caption)
            }
            if expanded && hasMore { Button("加载更多点评") { perform { try await load(reset: false) } }.font(.caption).disabled(busy) }
            if loaded && comments.isEmpty { Text("还没有点评，说说这张照片吧。").font(.caption).foregroundStyle(.secondary) }
            if !failure.isEmpty {
                Text(failure).font(.caption).foregroundStyle(.red)
                Button("重新加载点评") { perform { try await load(reset: true) } }.font(.caption).disabled(busy)
            }
            HStack(alignment: .bottom) {
                TextField("点评这张照片…", text: $draft, axis: .vertical).lineLimit(1...4)
                    .textFieldStyle(.roundedBorder).disabled(busy)
                    .onChange(of: draft) { _, _ in requestID = UUID() }
                Button("发表") {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines), id = requestID
                    perform {
                        _ = try await store.call(route, method: "POST", body: ["text": text, "requestId": id.uuidString])
                        draft = ""; requestID = UUID()
                        try await load(reset: true)
                    }
                }.disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.utf16.count > 1000)
            }
            if draft.utf16.count > 1000 { Text("点评最多 1000 字，请缩短后发表。").font(.caption).foregroundStyle(.red) }
        }.buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task { do { try await load(reset: true) } catch is CancellationError { } catch { failure = error.localizedDescription } }
    }
    @MainActor private func load(reset: Bool) async throws {
        let skip = reset ? 0 : nextSkip
        guard let result = try await store.call(route + "?skip=\(skip)") as? [String: Any] else { throw APIError.message("无法读取点评。") }
        let rows = try DearRecord.list(result["items"])
        if reset { comments = rows } else { comments += rows.filter { row in !comments.contains { $0.id == row.id } } }
        nextSkip = result["nextSkip"] as? Int ?? skip + rows.count
        hasMore = result["hasMore"] as? Bool ?? false
        loaded = true; failure = ""
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true; failure = ""
        Task { defer { busy = false }; do { try await action() } catch { failure = error.localizedDescription } }
    }
}

private struct DearPhotoGalleryView: View {
    @ObservedObject var store: FamilyStore
    let photos: [DearRecord]
    let spaceID: String
    let activityID: String
    let allowsDeletion: Bool
    let onDeleted: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String

    init(store: FamilyStore, photos: [DearRecord], initialPhotoID: String, spaceID: String, activityID: String,
         allowsDeletion: Bool, onDeleted: @escaping (String, Bool) -> Void) {
        self.store = store; self.spaceID = spaceID; self.activityID = activityID
        self.allowsDeletion = allowsDeletion; self.onDeleted = onDeleted
        self.photos = photos.sorted {
            let left = ActivityListDate.parse($0.text("createdAt")) ?? .distantPast
            let right = ActivityListDate.parse($1.text("createdAt")) ?? .distantPast
            return left == right ? $0.id < $1.id : left > right
        }
        _selectedID = State(initialValue: photos.contains(where: { $0.id == initialPhotoID }) ? initialPhotoID : photos.first?.id ?? "")
    }
    var body: some View {
        NavigationStack {
            TabView(selection: $selectedID) {
                ForEach(photos) { photo in
                    DearPhotoDetailView(store: store, photo: photo, spaceID: spaceID, activityID: activityID,
                                        path: "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)/native-photos/\(photo.id)/thumbnail",
                                        canDelete: allowsDeletion && photo.flag("canDelete"),
                                        onDeleted: { removed in onDeleted(photo.id, removed); dismiss() },
                                        onSwipeDown: { dismiss() })
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle("\((photos.firstIndex(where: { $0.id == selectedID }) ?? 0) + 1) / \(photos.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark").accessibilityLabel("关闭照片查看") } }
                ToolbarItem(placement: .bottomBar) { Text("左右切换 · 下拉照片返回列表").font(.caption).foregroundStyle(.secondary) }
            }
            .onChange(of: selectedID) { _, _ in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
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
    var onSwipeDown: (() -> Void)? = nil
    @State private var dismissOffset = 0.0
    @State private var downwardDrag: Bool?
    @State private var image: UIImage?
    @State private var error: String?
    @State private var originalURL: URL?
    @State private var player: AVPlayer?
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
                Group {
                    if isVideo, let player {
                        VideoPlayer(player: player).frame(minHeight: 240)
                    } else if let image = originalImage ?? image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if let error {
                        ContentUnavailableView("无法显示照片预览", systemImage: "photo.badge.exclamationmark",
                                                   description: Text(error))
                        Button("重试") { Task { await load() } }
                    } else { ProgressView("正在加载照片") }
                }
                .contentShape(Rectangle())
                .offset(y: dismissOffset)
                .scaleEffect(1 - min(dismissOffset / 1200, 0.15))
                .simultaneousGesture(DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard onSwipeDown != nil else { return }
                        if downwardDrag == nil {
                            downwardDrag = value.translation.height > 0 && value.translation.height > abs(value.translation.width) * 1.25
                        }
                        if downwardDrag == true { dismissOffset = max(0, value.translation.height) }
                    }
                    .onEnded { value in
                        let close = downwardDrag == true && PhotoViewerSwipe.shouldDismiss(
                            horizontal: value.translation.width, vertical: value.translation.height,
                            predictedVertical: value.predictedEndTranslation.height)
                        downwardDrag = nil
                        if close { onSwipeDown?() }
                        else { withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { dismissOffset = 0 } }
                    })
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
                DearPhotoCommentsView(store: store, spaceID: spaceID, activityID: activityID, photoID: photo.id)
                if canDelete {
                    Button("删除分享", role: .destructive) { showingDelete = true }.disabled(deleting)
                }
                Text("原文件从分享者设备传来，获取时请保持对方的分享应用打开。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .confirmationDialog("删除这项分享？", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("删除分享", role: .destructive) { Task { await deleteSharedMedia() } }
            Button("取消", role: .cancel) { }
        } message: { Text("活动成员将无法再获取此文件；iPhone 相册中的原文件不会删除。") }
        .task(id: path) { await load() }
        .onDisappear { player?.pause() }
    }

    private func load() async {
        image = nil; error = nil
        if isVideo, let local = await store.photoSource.localOriginal(photoID: photo.id, spaceID: spaceID, activityID: activityID) {
            originalURL = local
            player = AVPlayer(url: local)
            return
        }
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
            if isVideo { player = AVPlayer(url: url) }
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


struct MomentNotificationInbox: View {
    @ObservedObject var store: FamilyStore
    @ObservedObject var notifications: MomentNotifications
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if !notifications.error.isEmpty { Section { Text(notifications.error).foregroundStyle(.red) } }
                if !notifications.pushRegistrationError.isEmpty { Section { Text(notifications.pushRegistrationError).foregroundStyle(.red) } }
                Section {
                    HStack {
                        Button(notifications.enableButtonTitle) { Task { await notifications.enable() } }
                            .disabled(notifications.enabling || notifications.registering)
                        if notifications.enabling || notifications.registering { Spacer(); ProgressView() }
                    }
                    Text(notifications.notificationStatus).font(.footnote).foregroundStyle(.secondary)
                    Button("系统通知设置") { notifications.openSettings() }.font(.footnote)
                    Text("下载请求会发送给共享者。原文件保存在共享设备上，传输时请保持该设备的应用打开。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("请求与消息 · 未读 \(notifications.unreadCount)") {
                    ForEach(notifications.items) { item in
                        NavigationLink {
                            MomentNotificationDetail(store: store, notifications: notifications, item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { if item.readAt == nil { Circle().fill(.teal).frame(width: 7, height: 7) }; Text(item.title).font(.headline) }
                                Text(item.content).lineLimit(2).font(.subheadline).foregroundStyle(.secondary)
                                Text(DearRecord(data: ["createdAt": item.createdAt]).dateText("createdAt"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if notifications.items.isEmpty { Text("暂无消息。下载请求会在此保留。") }
                }
            }
            .navigationTitle("消息通知")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .refreshable { await notifications.reload() }
            .task { await notifications.reload() }
            .navigationDestination(isPresented: Binding(get: { notifications.selectedMessageID != nil && !notifications.items.isEmpty }, set: { if !$0 { notifications.selectedMessageID = nil } })) {
                if let item = notifications.items.first(where: { $0.id == notifications.selectedMessageID }) {
                    MomentNotificationDetail(store: store, notifications: notifications, item: item)
                } else { ContentUnavailableView("此消息不属于当前账号或已不可访问", systemImage: "bell.slash") }
            }
        }
    }
}

private struct MomentNotificationDetail: View {
    @ObservedObject var store: FamilyStore
    @ObservedObject var notifications: MomentNotifications
    let item: ApplicationNotification
    @State private var request: DearRecord?
    @State private var error = ""
    @State private var refreshing = false
    private var requestID: UUID? {
        guard let source = item.sourceRecordId, source.hasPrefix("photo-request:") else { return nil }
        return UUID(uuidString: String(source.dropFirst("photo-request:".count)))
    }
    private var status: String {
        switch request?.text("status") {
        case "waiting": return "等待共享设备传输"
        case "transferring": return "正在传输原文件"
        case "confirming": return "正在核验下载文件"
        case "completed": return "下载已完成"
        case "expired": return "请求已过期，请对方重新请求"
        case "cancelled": return "下载者已取消请求"
        case "revoked": return "分享已撤销或成员权限已变更"
        case "unavailable": return "共享设备未找到原文件"
        case "failed": return "传输未完成，请对方重新请求"
        default: return "正在读取请求状态"
        }
    }
    var body: some View {
        List {
            Section {
                Text(item.title).font(.headline)
                Text(item.content).textSelection(.enabled)
                Text(DearRecord(data: ["createdAt": item.createdAt]).dateText("createdAt"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if requestID != nil {
                Section("原文件下载请求") {
                    if let request {
                        Text("请求人：\(request.text("requesterDisplayName").isEmpty ? "成员 " + request.text("requester") : request.text("requesterDisplayName"))")
                        Text(request.text("fileName")); Text(status)
                    }
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                    Button("刷新请求状态") { Task { await loadRequest() } }.disabled(refreshing)
                    if request?.text("status") == "waiting" || request?.text("status") == "transferring" {
                        Button("继续共享并传输原文件") { Task { await store.photoSource.serveCurrentRequests(); await loadRequest() } }
                        Text("请在保存原文件的设备上打开应用，并保持前台运行。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("消息详情")
        .task { await notifications.markRead(item); await loadRequest() }
    }
    private func loadRequest() async {
        guard let requestID else { return }
        refreshing = true; defer { refreshing = false }
        do {
            guard let row = try await store.call("/api/dear/social/photo-requests/\(requestID.uuidString)") as? [String: Any] else { throw APIError.message("请求数据无效。") }
            request = DearRecord(data: row); error = ""
        } catch { self.error = "请求已不可访问或登录已过期，请刷新后重试。" }
    }
}


private struct MomentNotificationButton: View {
    @ObservedObject var notifications: MomentNotifications
    var body: some View {
        Button { notifications.open() } label: {
            Label("消息通知", systemImage: notifications.unreadCount > 0 ? "bell.badge" : "bell")
        }.accessibilityLabel("消息通知，\(notifications.unreadCount) 条未读")
    }
}
