import AgentIdentity
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
        if mode == .photo {
            picker.cameraOverlayView = DearCompositionOverlay(frame: picker.view.bounds)
        }
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

private final class DearCompositionOverlay: UIView {
    private let button = UIButton(type: .system)
    private let tipLabel = UILabel()
    private let tipCard = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let bundle = AgentIdentityLanguage.appBundle()
        let locale = Locale(identifier: AgentIdentityLanguage.current)
        let title = String(localized: "构图建议", bundle: bundle, locale: locale)
        let tips = [
            (String(localized: "三分构图", bundle: bundle, locale: locale),
             String(localized: "把画面想成九宫格，让主体靠近交点，视线方向多留一点空间。", bundle: bundle, locale: locale)),
            (String(localized: "人像", bundle: bundle, locale: locale),
             String(localized: "让眼睛靠近画面上方三分线，头顶留一点空间，避开杂乱背景。", bundle: bundle, locale: locale)),
            (String(localized: "合照", bundle: bundle, locale: locale),
             String(localized: "留出画面两侧的空间，确认每个人的脸都看得见。", bundle: bundle, locale: locale)),
            (String(localized: "风景", bundle: bundle, locale: locale),
             String(localized: "先把地平线拍平，放在上方或下方三分线，突出更有看点的一侧。", bundle: bundle, locale: locale))
        ]

        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: "viewfinder")
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.75)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        button.configuration = configuration
        button.showsMenuAsPrimaryAction = true
        let actions = tips.map { name, tip in
            UIAction(title: name) { [weak self] _ in self?.showTip(tip) }
        }
        let hide = UIAction(title: String(localized: "收起构图提示", bundle: bundle, locale: locale)) { [weak self] _ in
            self?.tipCard.isHidden = true
        }
        button.menu = UIMenu(title: title, children: actions + [hide])

        tipLabel.font = .preferredFont(forTextStyle: .subheadline)
        tipLabel.adjustsFontForContentSizeCategory = true
        tipLabel.textColor = .white
        tipLabel.numberOfLines = 0
        tipCard.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        tipCard.layer.cornerRadius = 14
        tipCard.isHidden = true

        for view in [button, tipCard, tipLabel] { view.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(button)
        addSubview(tipCard)
        tipCard.addSubview(tipLabel)
        let preferredWidth = tipCard.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor, constant: -32)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            button.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 56),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            tipCard.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 8),
            tipCard.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            tipCard.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            preferredWidth,
            tipLabel.topAnchor.constraint(equalTo: tipCard.topAnchor, constant: 10),
            tipLabel.leadingAnchor.constraint(equalTo: tipCard.leadingAnchor, constant: 14),
            tipLabel.trailingAnchor.constraint(equalTo: tipCard.trailingAnchor, constant: -14),
            tipLabel.bottomAnchor.constraint(equalTo: tipCard.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { nil }

    private func showTip(_ tip: String) {
        tipLabel.text = tip
        tipCard.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: tip)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return nil }
        return button.hitTest(button.convert(point, from: self), with: event)
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
        return String(format: "%@ %.5f，%@ %.5f", latitude < 0 ? String(localized: "南纬", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "北纬", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), abs(latitude), longitude < 0 ? String(localized: "西经", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "东经", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), abs(longitude))
    }
}

@MainActor private final class PhotoPlaceNames {
    static let shared = PhotoPlaceNames()
    private var cached: [String: (String?, Date)] = [:]
    private var pending: [String: Task<String?, Never>] = [:]
    private var tail: Task<String?, Never>?
    func name(latitude: Double, longitude: Double) async -> String? {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        let key = String(format: "%.4f,%.4f", latitude, longitude)
        if let (value, expires) = cached[key], expires > Date() { return value }
        if let task = pending[key] { return await task.value }
        let previous = tail
        let task = Task { @MainActor () -> String? in
            _ = await previous?.value
            let geocoder = CLGeocoder()
            let places = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
            let place = places?.first
            let parts = [place?.administrativeArea, place?.locality, place?.subLocality, place?.name].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            var unique: [String] = []
            for part in parts where !unique.contains(part) { unique.append(part) }
            let result = unique.isEmpty ? nil : String(unique.joined(separator: " ").prefix(200))
            try? await Task.sleep(for: .milliseconds(300))
            return result
        }
        pending[key] = task; tail = task
        let value = await task.value
        pending.removeValue(forKey: key); cached[key] = (value, Date().addingTimeInterval(value == nil ? 60 : 3600))
        return value
    }
}

extension DearPhotoLocation {
    static func coordinateLabel(_ text: String) -> (Double, Double)? {
        let parts = text.components(separatedBy: "，")
        guard parts.count == 2 else { return nil }
        let lat = parts[0].trimmingCharacters(in: .whitespaces), lon = parts[1].trimmingCharacters(in: .whitespaces)
        guard lat.hasPrefix("北纬") || lat.hasPrefix("南纬"), lon.hasPrefix("东经") || lon.hasPrefix("西经"),
              let latitude = Double(lat.dropFirst(2).trimmingCharacters(in: .whitespaces)),
              let longitude = Double(lon.dropFirst(2).trimmingCharacters(in: .whitespaces)), abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        return (lat.hasPrefix("南纬") ? -latitude : latitude, lon.hasPrefix("西经") ? -longitude : longitude)
    }
    @MainActor static func geography(at url: URL, fallbackName: String) async -> PhotoGeography {
        var result = PhotoGeography(name: fallbackName, latitude: nil, longitude: nil, altitudeMeters: nil)
        if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
            let asset = AVURLAsset(url: url)
            if let metadata = try? await asset.load(.metadata) {
                for item in metadata where item.identifier == .quickTimeMetadataLocationISO6709 {
                    if let text = try? await item.load(.stringValue), let (lat,lon,alt) = PhotoGeography.iso6709(text) {
                        result.latitude = lat; result.longitude = lon; result.altitudeMeters = alt; break
                    }
                }
            }
        } else {
            let fields = await Task.detached(priority: .utility) { () -> PhotoGeography in
                var info = PhotoGeography(name: fallbackName, latitude: nil, longitude: nil, altitudeMeters: nil)
                guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                      let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any] else { return info }
                if let lat = (gps[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue,
                   let lon = (gps[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue, lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 {
                    info.latitude = (gps[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased() == "S" ? -lat : lat
                    info.longitude = (gps[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased() == "W" ? -lon : lon
                }
                info.altitudeMeters = PhotoGeography.altitude((gps[kCGImagePropertyGPSAltitude as String] as? NSNumber)?.doubleValue,
                    belowSeaLevel: (gps[kCGImagePropertyGPSAltitudeRef as String] as? NSNumber)?.intValue == 1)
                return info
            }.value
            result = fields
        }
        if result.latitude == nil, let (lat,lon) = coordinateLabel(fallbackName) { result.latitude = lat; result.longitude = lon }
        if result.name.isEmpty || coordinateLabel(result.name) != nil, let lat = result.latitude, let lon = result.longitude {
            result.name = await PhotoPlaceNames.shared.name(latitude: lat, longitude: lon) ?? coordinates(latitude: lat, longitude: lon) ?? fallbackName
        }
        return result
    }
}

private enum PhotoDisplayImage {
    static func preview(_ url: URL, isVideo: Bool) async throws -> UIImage {
        if !isVideo { return try await load(url) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 2048, height: 2048)
        let result = try await generator.image(at: .zero)
        return UIImage(cgImage: result.image)
    }
    static func load(_ url: URL) async throws -> UIImage {
        try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw APIError.message("原图无法显示。") }
            return UIImage(cgImage: thumbnail)
        }.value
    }
}

private struct DearPhotoPlaceView: View {
    let photo: DearRecord
    @State private var resolvedName: String?
    private var coordinates: (Double,Double)? {
        if let lat = photo.data["latitude"] as? NSNumber, let lon = photo.data["longitude"] as? NSNumber { return (lat.doubleValue,lon.doubleValue) }
        return DearPhotoLocation.coordinateLabel(photo.text("locationName"))
    }
    private var name: String {
        let raw = photo.text("locationName")
        if !raw.isEmpty && DearPhotoLocation.coordinateLabel(raw) == nil { return raw }
        return resolvedName ?? (coordinates == nil ? "位置未记录" : "位置已记录，地点名称待解析")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(name, systemImage: "mappin").lineLimit(2)
            if let altitude = (photo.data["altitudeMeters"] as? NSNumber)?.doubleValue, altitude.isFinite {
                Label("海拔 \(altitude.formatted(.number.precision(.fractionLength(0...1)))) 米", systemImage: "mountain.2").lineLimit(1)
            } else { Label("海拔未记录", systemImage: "mountain.2").lineLimit(1) }
        }
        .task(id: photo.text("locationName") + String(describing: coordinates)) {
            guard let (lat,lon) = coordinates, photo.text("locationName").isEmpty || DearPhotoLocation.coordinateLabel(photo.text("locationName")) != nil else { return }
            let value = await PhotoPlaceNames.shared.name(latitude: lat, longitude: lon)
            if !Task.isCancelled { resolvedName = value }
        }
    }
}

// Export the original file bytes to the share sheet, rather than a URL link.
private struct DearOriginalFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { SentTransferredFile($0.url) }
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

private struct DearPickedOriginal: Transferable {
    let url: URL
    let originalFileName: String
    private static func copy(_ received: ReceivedTransferredFile) throws -> Self {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + received.file.pathExtension)
        try FileManager.default.copyItem(at: received.file, to: path)
        return Self(url: path, originalFileName: received.file.lastPathComponent)
    }
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { try copy($0) }
        FileRepresentation(importedContentType: .movie) { try copy($0) }
    }
}

struct DearRecord: Identifiable {
    let data: [String: Any]
    let sortDate: Date
    private let startsAtInstant: Date?
    init(data: [String: Any]) {
        self.data = data
        self.sortDate = ActivityListDate.parse(data["createdAt"] as? String ?? "") ?? .distantPast
        let raw = data["startsAt"] as? String ?? ""
        // Calendar-only dates stay tied to the current device time zone.
        self.startsAtInstant = raw.count == 10 ? nil : ActivityListDate.parse(raw)
    }
    var activitySortDate: Date {
        let raw = text("startsAt")
        if raw.count == 10 { return ActivityListDate.parse(raw) ?? sortDate }
        return startsAtInstant ?? sortDate
    }
    var id: String { text("id") }
    var subject: String { text("subject") }
    func text(_ key: String) -> String { data[key] as? String ?? "" }
    func dateText(_ key: String) -> String {
        let date = key == "createdAt" ? (sortDate == .distantPast ? nil : sortDate) : ActivityListDate.parse(text(key))
        return date.map { "\($0.formatted(date: .abbreviated, time: .shortened))（当地时间）" } ?? "时间未知"
    }
    func flag(_ key: String) -> Bool { data[key] as? Bool ?? false }
    func number(_ key: String) -> Double { data[key] as? Double ?? 0 }
    static func list(_ value: Any) throws -> [DearRecord] {
        guard let values = value as? [[String: Any]] else { throw APIError.message(String(localized: "Linko Social 返回的数据格式不正确。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        return values.map { DearRecord(data: $0) }
    }
}

private struct DearActivityMapPoint: Identifiable {
    let id: String
    let nickname: String
    let placeName: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let systemImage: String
    let photo: DearRecord?

    static func points(checkIns: [DearRecord], photos: [DearRecord]) -> [Self] {
        let visits = checkIns.compactMap { item -> Self? in
            guard let coordinate = coordinate(latitude: item.data["latitude"], longitude: item.data["longitude"]) else { return nil }
            let address = item.text("address")
            let subtitle = "\(item.dateText("createdAt")) · 海拔 \(String(format: "%.1f", item.number("altitudeMeters"))) 米"
            return Self(id: "checkin-\(item.id)", nickname: item.text("authorName"), placeName: address,
                        subtitle: subtitle, coordinate: coordinate, systemImage: "mappin.circle.fill", photo: nil)
        }
        let pictures = photos.compactMap { item -> Self? in
            guard let coordinate = coordinate(latitude: item.data["latitude"], longitude: item.data["longitude"]) ?? photoCoordinate(item.text("locationName")) else { return nil }
            let rawPlace = item.text("locationName")
            let place = DearPhotoLocation.coordinateLabel(rawPlace) == nil ? rawPlace : ""
            return Self(id: "photo-\(item.id)", nickname: item.text("sourceDisplayName"), placeName: place,
                        subtitle: item.dateText("createdAt"),
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
        let south = latitudeText.hasPrefix(String(localized: "南纬", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        let west = longitudeText.hasPrefix(String(localized: "西经", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        guard (south || latitudeText.hasPrefix(String(localized: "北纬", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))), (west || longitudeText.hasPrefix(String(localized: "东经", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))),
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
    @State private var resolvedPlaces: [String: String] = [:]
    @State private var selectedPhoto: DearRecord?

    private var selectedPoint: DearActivityMapPoint? { points.first { $0.id == selectedPointID } }
    private func thumbnailPath(_ photo: DearRecord) -> String {
        "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)/native-photos/\(photo.id)/thumbnail"
    }

    private func openPhoto(_ photo: DearRecord) {
        selectedPhoto = photo
    }
    private func mapTitle(_ point: DearActivityMapPoint) -> String {
        ActivityMapLabel.title(nickname: point.nickname, placeName: resolvedPlaces[point.id] ?? point.placeName)
    }
    private func photoTitle(_ photo: DearRecord) -> String {
        let raw = photo.text("locationName")
        return ActivityMapLabel.title(nickname: photo.text("sourceDisplayName"),
            placeName: resolvedPlaces["photo-" + photo.id] ?? (DearPhotoLocation.coordinateLabel(raw) == nil ? raw : ""))
    }


    var body: some View {
        VStack(spacing: 0) {
            if points.isEmpty {
                ContentUnavailableView(String(localized: "暂无地图位置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "map",
                                       description: Text(String(localized: "照片没有记录坐标时仍可在下方查看，但无法固定到地图上。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Map(position: $cameraPosition) {
                    ForEach(points) { point in
                        Annotation("", coordinate: point.coordinate) {
                            Button { selectedPointID = point.id } label: {
                                VStack(spacing: 4) {
                                if let photo = point.photo {
                                    DearPhotoPreview(store: store, path: thumbnailPath(photo), photo: photo)
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
                                Text(mapTitle(point)).font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary).multilineTextAlignment(.center).lineLimit(2)
                                    .frame(maxWidth: 156).fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                                }
                            }.buttonStyle(.plain)
                            .accessibilityLabel("\(mapTitle(point))，\(point.subtitle)")
                        }
                    }
                }
                .mapControls { MapCompass(); MapScaleView() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: points.map { "\($0.id):\($0.coordinate.latitude):\($0.coordinate.longitude)" }.joined(separator: "|")) {
                    for point in points where point.placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if Task.isCancelled { return }
                        if let name = await PhotoPlaceNames.shared.name(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude), !Task.isCancelled {
                            resolvedPlaces[point.id] = name
                        }
                    }
                }
            }
            if let selectedPoint {
                HStack(spacing: 10) {
                    if let photo = selectedPoint.photo {
                        DearPhotoPreview(store: store, path: thumbnailPath(photo), photo: photo)
                            .frame(width: 54, height: 54)
                    } else { Image(systemName: selectedPoint.systemImage).font(.title2) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mapTitle(selectedPoint)).font(.headline).lineLimit(1)
                        Text(selectedPoint.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if let photo = selectedPoint.photo {
                        Button(String(localized: "查看", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { openPhoto(photo) }.font(.subheadline)
                    }
                }
                .padding(12)
            }
            if !photos.isEmpty {
                HStack {
                    Text(String(localized: "活动照片与视频", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.subheadline.bold())
                    Spacer()
                    let unlocated = photos.count - points.filter { $0.photo != nil }.count
                    if unlocated > 0 { Text(String(localized: "\(unlocated) 项未定位", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.horizontal)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(photos) { photo in
                            Button { openPhoto(photo) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    DearPhotoPreview(store: store, path: thumbnailPath(photo), photo: photo)
                                        .frame(width: 82, height: 82)
                                    Text(photoTitle(photo))
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
                            Text(mapTitle(point)).lineLimit(1)
                            Text(point.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    } icon: { Image(systemName: point.systemImage) }
                }
            }
            .frame(height: min(CGFloat(points.count) * 70 + 16, 220))
        }
        .navigationTitle(String(localized: "\(title) · 地图", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedPhoto) { selectedPhoto in
                DearPhotoGalleryView(store: store, photos: photos, initialPhotoID: selectedPhoto.id,
                                     spaceID: spaceID, activityID: activityID, allowsDeletion: false,
                                     onDeleted: { _, _ in })
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
    @State private var invitationToOpen: MomentActivityLink?
    @State private var spaces: [DearRecord] = []
    @State private var joinedActivities: [DearRecord] = []
    @State private var activities: [DearRecord] = []
    @State private var photos: [DearRecord] = []
    @State private var selectedPhoto: DearRecord?
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
    @State private var batchProgress = PhotoTransferPresentation()
    private var batchDownloadProgress: Double {
        get { batchProgress.progress ?? 0 }
        nonmutating set { batchProgress.updateProgress(newValue) }
    }
    @State private var batchDownloading = false
    @State private var batchDeleting = false
    @State private var showingBatchDelete = false
    @State private var photoToDelete: DearRecord?
    @State private var showingPhotoLocation = false
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
            let leftDate = left.activitySortDate
            let rightDate = right.activitySortDate
            return leftDate == rightDate ? left.id < right.id : leftDate > rightDate
        }
    }
    private var selectedActivity: DearRecord? { activities.first { $0.id == activityId } ?? joinedActivities.first { $0.id == activityId } }
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
                    Section(String(localized: "待确认的活动邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        ForEach(invitations.filter { !$0.flag("joined") }) { invitation in
                            HStack {
                                Text(invitation.text("activityTitle"))
                                Spacer()
                                Button(String(localized: "确认加入", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { run { try await accept(invitation) } }.disabled(busy)
                            }
                        }
                    }
                }
                Section(String(localized: "我的空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    if visibleSpaces.isEmpty { Text(String(localized: "请用右上角“…”新增个人空间。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) .foregroundStyle(.secondary) }
                    else {
                        HStack {
                            Picker("", selection: $spaceId) {
                                ForEach(visibleSpaces) { item in Text(item.text("name")).tag(item.id) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Menu {
                                if selectedSpace?.text("role") == "owner" {
                                    Button(String(localized: "编辑基本信息", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "pencil") {
                                        editedSpaceName = selectedSpace?.text("name") ?? ""
                                        showingSpaceRename = true
                                    }
                                }
                                Button(String(localized: "查看空间成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "person.2") { run { try await loadSpaceMembers() } }
                                if selectedSpace?.text("role") == "owner" {
                                    Button(String(localized: "删除空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "trash", role: .destructive) { showingSpaceDelete = true }
                                }
                            } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(String(localized: "管理当前空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                            .disabled(busy)
                        }
                    }
                    Text(String(localized: "每个人管理自己的空间，同一活动可收藏到多个空间。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if selectedSpace?.text("role") == "owner" || !joinedActivities.isEmpty {
                    Section {
                        Text("日期按设备当地时区显示").font(.caption).foregroundStyle(.secondary)
                        if activityLoading { Text(String(localized: "正在读取已有活动…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
                        if !activityError.isEmpty { Text(activityError).foregroundStyle(.red) }
                        if allActivities.isEmpty && !activityLoading && activityError.isEmpty { Text(String(localized: "还没有活动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(.secondary) }
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
                                        Button(String(localized: "活动管理", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "gearshape") {
                                            activityId = item.id
                                            editedActivityName = item.text("title")
                                            editedActivityDescription = item.text("description")
                                            editedActivityDate = activityDateValue(item)
                                            showingActivityManagement = true
                                        }
                                        if item.flag("isBookmarked") {
                                            Button(String(localized: "取消收藏", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "bookmark.slash", role: .destructive) { run { try await removeBookmark(item) } }
                                        } else if selectedSpace?.text("role") == "owner" && item.text("sourceTenantId") != spaceId && !activities.contains(where: { $0.id == item.id }) {
                                            Button(String(localized: "收藏到当前空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "bookmark") { run { try await addBookmark(item) } }
                                        }
                                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(String(localized: "管理\(item.text("title"))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
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
                Section(String(localized: "好友关系 · 跨空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    DisclosureGroup(String(localized: "查看好友与申请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        if relationships.isEmpty { Text(String(localized: "还没有好友关系或申请。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) .foregroundStyle(.secondary) }
                        ForEach(relationships) { relation in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(relation.text("peerName"))
                                    Text(relation.text("status") == "accepted" ? String(localized: "朋友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : relation.text("direction") == "incoming" ? String(localized: "邀请你成为朋友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "等待对方确认", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if relation.text("status") == "pending" && relation.text("direction") == "incoming" {
                                    Button(String(localized: "接受", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { run { try await acceptFriend(relation) } }.disabled(busy)
                                }
                                Button(relation.text("status") == "accepted" ? String(localized: "解除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "移除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) {
                                    run { try await removeFriend(relation) }
                                }.disabled(busy)
                            }
                        }
                    }
                }
                if showLogout {
                    Section { Link(String(localized: "隐私政策与支持", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), destination: URL(string: "https://happylife.ai.impx.net/legal/linko-family-privacy.html")!) }
                }
            }
            .listStyle(.insetGrouped)
            .readablePage()
            .navigationTitle(String(localized: "活动与分享", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(String(localized: "新增空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "plus") { spaceName = ""; showingSpaceCreate = true }
                        if selectedSpace?.text("role") == "owner" {
                            Button(String(localized: "修改空间名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "pencil") { editedSpaceName = selectedSpace?.text("name") ?? ""; showingSpaceRename = true }
                            Button(String(localized: "删除空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "trash", role: .destructive) { showingSpaceDelete = true }
                        }
                        Button(String(localized: "刷新", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "arrow.clockwise") { run { try await load() } }
                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(String(localized: "空间菜单", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                    .disabled(busy)
                }
                ToolbarItem(placement: .topBarTrailing) { MomentNotificationButton(notifications: store.notifications) }
                if showLogout { ToolbarItem(placement: .topBarLeading) { Button(String(localized: "退出", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { store.logout() } } }
            }
            .refreshable { await refresh() }
            .task(id: store.pendingActivityLink?.id) { await refresh(); await openPendingActivityLink() }
            .alert("加入邀请中的活动？", isPresented: Binding(get: { invitationToOpen != nil }, set: { if !$0 { invitationToOpen = nil } })) {
                Button("确认加入") {
                    if let link = invitationToOpen { invitationToOpen = nil; run { try await acceptActivityLink(link) } }
                }
                Button("取消", role: .cancel) { invitationToOpen = nil }
            } message: { Text("确认后使用当前登录账号接受活动邀请，并查看活动内容。") }
            .onChange(of: spaceId) { _, _ in if !showingActivity { activityId = ""; selectedPhoto = nil; showingActivityManagement = false; photos = [] }; activities = []; activityError = ""; activityLoading = true; run { try await loadActivities() } }
            .navigationDestination(isPresented: $showingActivity) { activityDetail }
            .sheet(isPresented: $showingActivityManagement) { activityManagement }
            .sheet(isPresented: $showingActivityCreate) { activityCreateSheet }
            .sheet(isPresented: $showingSpaceMembers) {
                NavigationStack {
                    List {
                        if selectedSpace?.text("role") == "owner" {
                            Text(String(localized: "先邀请对方加入本空间的活动，再从活动访客设为空间成员。空间成员可查看本空间的所有原生活动；收藏活动仍遵循原活动权限。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(spaceMembers) { member in
                            HStack {
                                Text(member.text("displayName"))
                                Spacer()
                                Text(member.text("role") == "owner" ? String(localized: "空间主人", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : member.text("role") == "member" ? String(localized: "空间成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "活动访客", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                    .foregroundStyle(.secondary)
                                if selectedSpace?.text("role") == "owner" && member.text("role") != "owner" {
                                    Menu {
                                        Button(member.text("role") == "member" ? String(localized: "改为活动访客", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "设为空间成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                                            run { try await setSpaceMemberRole(member,
                                                role: member.text("role") == "member" ? "guest" : "member") }
                                        }
                                    } label: { Image(systemName: "ellipsis.circle") }
                                }
                            }
                        }
                    }
                    .navigationTitle(String(localized: "空间成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { showingSpaceMembers = false } } }
                }
            }
            .onChange(of: activityId) { _, _ in photos = []; moments = []; checkIns = []; activityMembers = []; run { try await loadDetails() } }
            .alert(String(localized: "新增空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: $showingSpaceCreate) {
                TextField(String(localized: "空间名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $spaceName)
                Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .cancel) { }
                Button(String(localized: "创建", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { run { try await createSpace() } }
            } message: { Text(String(localized: "此空间由你管理，可收藏参加过的活动。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            .alert(String(localized: "修改空间名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: $showingSpaceRename) {
                TextField(String(localized: "空间名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $editedSpaceName)
                Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .cancel) { }
                Button(String(localized: "保存", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { run { try await renameSpace() } }
            } message: { Text(String(localized: "更新你的空间名称。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            .confirmationDialog(String(localized: "删除空间「\(selectedSpace?.text("name") ?? "")」？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: $showingSpaceDelete, titleVisibility: .visible) {
                Button(String(localized: "确认删除空间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { run { try await deleteSpace() } }
                Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .cancel) { }
            } message: { Text(String(localized: "仅可删除没有活动、其他成员或分享记录的空间。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
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
                        if photoViewMode != "list" { Image(systemName: selectedPhotoIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(selectedPhotoIDs.contains(photo.id) ? .teal : .white)
                            .padding(7) }
                    }
            }.buttonStyle(.plain).disabled(batchDownloading || batchDeleting)
        } else {
            Button {
                selectedPhoto = photo
            } label: { photoCard(photo, path: path) }
            .buttonStyle(.plain)
        }
    }

    private func photoCard(_ photo: DearRecord, path: String) -> some View {
        let expanded = photoViewMode != "list"
        let nickname = photo.text("sourceDisplayName").isEmpty ? String(localized: "活动成员", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : photo.text("sourceDisplayName")
        return DearPhotoPreview(store: store, path: path, photo: photo)
            .frame(height: expanded ? 240 : 112)
            .frame(maxWidth: expanded ? .infinity : 112)
            .overlay(alignment: .topLeading) {
                if expanded {
                    Label(nickname, systemImage: "person.crop.circle.fill")
                        .font(.caption.weight(.semibold)).lineLimit(1)
                        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule()).padding(7).padding(.trailing, selectingPhotoDownloads ? 44 : 0)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if expanded {
                    HStack(alignment: .bottom) {
                        DearPhotoPlaceView(photo: photo).font(.caption2)
                        Spacer(minLength: 0)
                        if photo.text("contentType").hasPrefix("video/") { Image(systemName: "play.circle.fill").font(.title2) }
                    }
                    .foregroundStyle(.white).padding(8)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("\(nickname)，\(photo.text("originalFileName"))，\(photo.dateText("createdAt"))")
    }

    private func photoActions(_ photo: DearRecord) -> some View {
        HStack(spacing: 16) {
            if photo.flag("canDelete") {
                Button("删除分享", role: .destructive) { photoToDelete = photo }
                    .disabled(busy || batchDeleting || batchDownloading)
            }
            Button { selectedPhoto = photo } label: {
                Label("\(Int(photo.number("commentCount")))", systemImage: "text.bubble")
            }.accessibilityLabel("照片点评 \(Int(photo.number("commentCount"))) 条")
            Spacer(minLength: 0)
            if selectingPhotoDownloads && photoViewMode == "list" {
                Image(systemName: selectedPhotoIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.teal)
            }
        }.font(.caption).buttonStyle(.borderless)
    }

    @ViewBuilder private func photoTimelineRow(_ photo: DearRecord) -> some View {
        if photoViewMode == "list" {
            HStack(alignment: .top, spacing: 12) {
                photoLink(photo).frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 7) {
                    Text(photo.text("sourceDisplayName").isEmpty ? "活动成员" : photo.text("sourceDisplayName")).font(.subheadline.bold()).lineLimit(1)
                    DearPhotoPlaceView(photo: photo).font(.caption2).foregroundStyle(.secondary)
                    Text(store.photoSource.deviceDescription(photo.data)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    Text(photo.dateText("createdAt")).font(.caption2).foregroundStyle(.secondary)
                    if photo.text("contentType").hasPrefix("video/") { Label("视频", systemImage: "play.circle").font(.caption2) }
                    photoActions(photo)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                photoLink(photo)
                Text(store.photoSource.deviceDescription(photo.data)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    Text(photo.dateText("createdAt")).font(.caption2).foregroundStyle(.secondary)
                photoActions(photo)
            }.padding(.vertical, 8)
        }
    }

    private var photoGridRows: [[DearRecord]] {
        stride(from: 0, to: photos.count, by: 5).map { Array(photos[$0..<min($0 + 5, photos.count)]) }
    }

    private func photoGridTile(_ photo: DearRecord) -> some View {
        let nickname = photo.text("sourceDisplayName").isEmpty ? "活动成员" : photo.text("sourceDisplayName")
        let path = base + "tenants/\(activityTenantId)/activities/\(activityId)/native-photos/\(photo.id)/thumbnail"
        return Button {
            if selectingPhotoDownloads {
                if !selectedPhotoIDs.insert(photo.id).inserted { selectedPhotoIDs.remove(photo.id) }
                batchOriginalURLs = []
            } else { selectedPhoto = photo }
        } label: {
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    DearPhotoPreview(store: store, path: path, photo: photo)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .overlay(alignment: .topLeading) {
                            Text(nickname).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                                .foregroundStyle(.white).padding(3).background(.black.opacity(0.4))
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if photo.text("contentType").hasPrefix("video/") {
                                Image(systemName: "play.circle.fill").foregroundStyle(.white).padding(3)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if selectingPhotoDownloads {
                                Image(systemName: selectedPhotoIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedPhotoIDs.contains(photo.id) ? .teal : .white).padding(3)
                            }
                        }
                }.aspectRatio(1, contentMode: .fit)
            }
        }.buttonStyle(.plain).disabled(batchDownloading || batchDeleting)
        .accessibilityLabel("\(nickname)，\(photo.text("originalFileName"))")
        .contextMenu {
            if photo.flag("canDelete") { Button("删除分享", role: .destructive) { photoToDelete = photo } }
        }
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
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 50, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                    Label("分享照片 / 视频", systemImage: "photo.badge.plus")
                }.buttonStyle(.borderedProminent).tint(.teal)
                Spacer()
                Menu {
                    Button { Task { await openCamera(.photo) } } label: { Label("拍照", systemImage: "camera") }
                    Button { Task { await openCamera(.video) } } label: { Label("录制视频", systemImage: "video") }
                } label: { Image(systemName: "camera").font(.title3).accessibilityLabel("拍摄并分享") }
            }.disabled(busy || requestingCamera || capturedMedia != nil || batchDeleting || batchDownloading)
            if let capturedMedia {
                Text(capturedMedia.savedToLibrary ? "已保存到系统相册，尚未共享到活动。" : "拍摄内容尚未保存并共享，请重试。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("重试保存并共享") { shareCapturedMedia() }
                    Spacer()
                    ShareLink(item: DearOriginalFile(url: capturedMedia.url), preview: SharePreview("原文件")) { Label("另存或分享", systemImage: "square.and.arrow.up") }
                    Button("移除", role: .destructive) {
                        try? FileManager.default.removeItem(at: capturedMedia.url)
                        self.capturedMedia = nil
                    }
                }.buttonStyle(.borderless).disabled(busy)
            }
            Picker("展现样式", selection: $photoViewMode) {
                Label("大图", systemImage: "rectangle").tag("grid")
                Label("紧凑", systemImage: "list.bullet").tag("list")
                Label("网格 · 每行5张", systemImage: "square.grid.3x3").tag("tiles")
            }.pickerStyle(.menu)
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
                DearBatchProgress(presentation: batchProgress, active: batchDownloading)
                if !batchOriginalURLs.isEmpty { ShareLink(items: batchOriginalURLs.map { DearOriginalFile(url: $0) }, preview: { SharePreview($0.url.lastPathComponent) }) { Label("保存或分享 \(batchOriginalURLs.count) 项", systemImage: "square.and.arrow.up") } }
                if !batchDownloadError.isEmpty { Text(batchDownloadError).font(.caption).foregroundStyle(.red) }
            }
        } header: { Text("照片分享").textCase(nil) }
    }

    private var activityTimeline: [DearTimelineEntry] {
        let shared = moments.map { DearTimelineEntry(id: "moment:" + $0.id, kind: .moment, record: $0) }
        let located = checkIns.map { DearTimelineEntry(id: "checkin:" + $0.id, kind: .checkIn, record: $0) }
        let media = photos.map { DearTimelineEntry(id: "photo:" + $0.id, kind: .photo, record: $0) }
        return (shared + located + media).sorted {
            let left = $0.record.sortDate
            let right = $1.record.sortDate
            return left == right ? $0.id < $1.id : left > right
        }
    }

    private var activityTimelineSection: some View {
        Section(photoViewMode == "tiles" ? "照片与视频" : "活动动态 · 照片、打卡与日常") {
            if photoViewMode == "tiles" {
                ForEach(Array(photoGridRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(row) { photo in photoGridTile(photo).frame(maxWidth: .infinity) }
                        ForEach(0..<(5 - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit) }
                    }.listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
            }
            ForEach(activityTimeline.filter { photoViewMode != "tiles" || $0.kind != .photo }, id: \.id) { entry in
                if entry.kind == .photo {
                    photoTimelineRow(entry.record)
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
            if activityTimeline.isEmpty {
                if busy { ProgressView("正在异步加载活动照片与动态…").font(.subheadline) }
                else { Text("还没有动态，拍照、写日常或打卡，留下活动的第一刻。").foregroundStyle(.secondary).font(.subheadline) }
            }
        }
    }

    private var activityDetail: some View {
        List {
            if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
            if !notice.isEmpty { Section { Text(notice).foregroundStyle(.teal) } }
            if let selectedActivity {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Label(activityDate(selectedActivity), systemImage: "calendar"); Spacer(); Label("\(activityMembers.count) 位成员", systemImage: "person.2") }
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                activityPhotoSection
                activityTimelineSection
            }
        }
        .listStyle(.insetGrouped)
        .readablePage()
        .task(id: activityTenantId + activityId + photos.map(\.id).joined()) {
            let tenant = activityTenantId, activity = activityId, rows = photos.map(\.data)
            guard !tenant.isEmpty, !activity.isEmpty, !rows.isEmpty else { return }
            await store.photoSource.refreshPreviews(spaceID: tenant, activityID: activity, rows: rows)
            let changed = await store.photoSource.refreshLocations(spaceID: tenant, activityID: activity, rows: rows)
            guard !Task.isCancelled, tenant == activityTenantId, activity == activityId else { return }
            if changed || rows.contains(where: { ($0["thumbnailAvailable"] as? Bool) == false }) {
                try? await loadPhotos()
            }
        }
        .navigationTitle(selectedActivity?.text("title") ?? "活动详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                activityActions
            }
        }
        .fullScreenCover(item: $selectedPhoto) { selectedPhoto in
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
        .alert("照片默认地点", isPresented: $showingPhotoLocation) {
            TextField("地点名称（可选）", text: $photoLocationName)
            Button("完成", role: .cancel) { }
        } message: { Text("优先使用照片自带定位；未记录定位时使用此处填写的地点。") }
        .confirmationDialog("删除这项分享？", isPresented: Binding(get: { photoToDelete != nil }, set: { if !$0 { photoToDelete = nil } }), titleVisibility: .visible) {
            if let photo = photoToDelete {
                Button("删除分享", role: .destructive) {
                    let tenant = activityTenantId, activity = activityId
                    run {
                        _ = try await store.photoSource.revoke(photoID: photo.id, spaceID: tenant, activityID: activity)
                        if tenant == activityTenantId && activity == activityId { photos.removeAll { $0.id == photo.id } }
                        photoToDelete = nil; notice = "分享已删除，设备相册原件保留。"
                    }
                }
            }
            Button("取消", role: .cancel) { photoToDelete = nil }
        } message: { Text("分享者或活动 owner 可删除；活动成员将无法再下载，设备相册原件保留。") }
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
        .onChange(of: activityId) { _, _ in photoToDelete = nil; showingActivityManagement = false; selectedPhoto = nil; inviteLink = ""; inviteUsername = ""; momentDraft = ""; momentRequestID = UUID(); photoLocationName = ""; selectingPhotoDownloads = false; selectedPhotoIDs.removeAll(); batchOriginalURLs = [] }
        .onChange(of: selectedPhotos) { _, selected in
            guard !selected.isEmpty else { return }
            let targetSpace = activityTenantId, targetActivity = activityId
            run {
                defer { selectedPhotos = [] }
                var completed = 0
                var failures: [String] = []
                for (index, item) in selected.enumerated() {
                    do {
                        guard let file = try await item.loadTransferable(type: DearPickedOriginal.self) else { throw APIError.message("无法读取所选原文件。") }
                        defer { try? FileManager.default.removeItem(at: file.url) }
                        let name = DearPhotoSource.originalFileName(assetIdentifier: item.itemIdentifier, fallback: file.originalFileName)
                        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                            try await store.photoSource.publishVideo(at: file.url, spaceID: targetSpace, activityID: targetActivity,
                                locationName: photoLocationName, name: name, assetIdentifier: item.itemIdentifier)
                        } else {
                            let data = try await Task.detached(priority: .utility) { try Data(contentsOf: file.url) }.value
                            let embedded = DearPhotoLocation.label(for: item, data: data)
                            try await store.photoSource.publish(data, spaceID: targetSpace, activityID: targetActivity,
                                name: name, locationName: embedded ?? photoLocationName, assetIdentifier: item.itemIdentifier)
                        }
                        completed += 1
                    } catch {
                        failures.append(String(localized: "第 \(index + 1) 项：\(momentDisplayError(error))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                    }
                }
                try await loadPhotos()
                notice = String(localized: "已共享 \(completed) 项；请保持此 iPhone 可以响应原文件请求。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
                if !failures.isEmpty { error = failures.joined(separator: "；") }
            }
        }
        .refreshable {
            do { try await loadDetails(); try await loadRelationships() }
            catch { self.error = momentDisplayError(error) }
        }
    }

    private var activityActions: some View {
                Menu {
                    if let url = URL(string: "https://happylife.ai.impx.net/api/dear/public/activities/\(activityTenantId)/\(activityId)") {
                        DearActivityShareLink(url: url, title: selectedActivity?.text("title") ?? "活动", label: "分享活动链接")
                    }
                    Button {
                        editedActivityName = selectedActivity?.text("title") ?? ""; editedActivityDescription = selectedActivity?.text("description") ?? ""
                        editedActivityDate = selectedActivity.map(activityDateValue) ?? Date(); showingActivityManagement = true
                    } label: { Label("活动管理与邀请", systemImage: "person.badge.plus") }
                    Button {
                        selectingPhotoDownloads.toggle(); selectedPhotoIDs.removeAll(); batchOriginalURLs = []; batchDownloadError = ""; batchDownloadProgress = 0
                    } label: { Label(selectingPhotoDownloads ? "完成多选" : "批量下载或删除", systemImage: "checkmark.circle") }
                        .disabled(photos.isEmpty || batchDownloading || batchDeleting)
                    Button { showingPhotoLocation = true } label: { Label("照片默认地点", systemImage: "mappin") }
                    Divider()
                    Button { momentDraft = ""; momentRequestID = UUID(); error = ""; showingMomentCreate = true } label: { Label("写日常", systemImage: "square.and.pencil") }
                    Button { checkInNote = ""; checkInRequestID = UUID(); pendingCheckIn = true; checkInLocator.locate() } label: { Label("打卡", systemImage: "location.circle") }
                        .disabled(busy || pendingCheckIn)
                    let points = DearActivityMapPoint.points(checkIns: checkIns, photos: photos)
                    NavigationLink {
                        DearActivityMapView(store: store, title: selectedActivity?.text("title") ?? "活动地图", spaceID: activityTenantId, activityID: activityId, points: points, photos: photos)
                    } label: { Label("活动地图", systemImage: "map") }.disabled(points.isEmpty && photos.isEmpty)
                } label: { Image(systemName: "ellipsis").accessibilityLabel("更多活动操作") }
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
                Section(String(localized: "当前位置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    if checkInLocator.fetching { ProgressView(String(localized: "正在获取位置和地址…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                    if !checkInLocator.error.isEmpty { Text(checkInLocator.error).foregroundStyle(.red) }
                    if let selectedCheckIn {
                        Text(checkInLocator.location == nil ? selectedCheckIn.text("address") : checkInLocator.address)
                        Text(String(format: String(localized: "纬度 %.6f，经度 %.6f", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), checkInLocator.location?.coordinate.latitude ?? selectedCheckIn.number("latitude"), checkInLocator.location?.coordinate.longitude ?? selectedCheckIn.number("longitude")))
                        Text(String(format: String(localized: "海拔 %.1f 米", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), checkInLocator.location?.altitude ?? selectedCheckIn.number("altitudeMeters")))
                    }
                    if selectedCheckIn?.flag("canEdit") == true {
                        Button(String(localized: "重新定位", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { checkInLocator.locate() }.disabled(checkInLocator.fetching)
                    }
                }
                Section(String(localized: "备注", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    TextField(String(localized: "默认填写当前位置地址", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $checkInNote, axis: .vertical)
                        .lineLimit(2...5)
                        .disabled(selectedCheckIn?.flag("canEdit") != true)
                    Text(String(localized: "留空时使用上方地址作为备注。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(selectedCheckIn?.flag("canEdit") == true ? String(localized: "修改打卡", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "打卡详情", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .onChange(of: checkInLocator.address) { _, address in
                if checkInNote.isEmpty { checkInNote = address }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "关闭", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { showingCheckIn = false } }
                if selectedCheckIn?.flag("canEdit") == true {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "保存", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { run { try await updateCheckIn() } }
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
                    Section(String(localized: "基本信息", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        TextField(String(localized: "活动名称", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $editedActivityName)
                        TextField(String(localized: "活动介绍", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $editedActivityDescription, axis: .vertical)
                            .lineLimit(2...5)
                        DatePicker(String(localized: "活动日期", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $editedActivityDate, displayedComponents: .date)
                        Button(String(localized: "保存基本信息", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { run { try await updateActivity() } }
                            .disabled(busy || editedActivityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedActivityDescription.count > 2000)
                        Button(String(localized: "删除活动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "trash", role: .destructive) {
                            showingActivityDelete = true
                        }.disabled(busy)
                    }
                }
                if selectedActivity?.flag("canEdit") == true {
                    Section(String(localized: "邀请参加", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        HStack {
                            TextField(String(localized: "用户中心用户名", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), text: $inviteUsername).textInputAutocapitalization(.never)
                            Button(String(localized: "邀请", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { run { try await inviteByName() } }
                                .disabled(busy || inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Button(String(localized: "生成七天有效的邀请链接", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { run { try await createInviteLink() } }.disabled(busy)
                        if let url = URL(string: inviteLink), url.scheme == "https" {
                            DearActivityShareLink(url: url, title: selectedActivity?.text("title") ?? "活动", label: String(localized: "分享邀请链接", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        }
                        Text(String(localized: "对方确认加入后才能查看这场活动的分享。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(String(localized: "发布日常", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    TextEditor(text: $momentDraft).frame(minHeight: 90)
                        .accessibilityLabel(String(localized: "写下生活日常", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        .onChange(of: momentDraft) { _, _ in momentRequestID = UUID() }
                    Button(String(localized: "发布日常", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { run { try await publishMoment() } }
                        .disabled(busy || momentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || momentDraft.count > 1000)
                }
                Section(String(localized: "活动成员与好友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    ForEach(activityMembers.filter { !$0.flag("isSelf") }, id: \.subject) { member in
                        HStack {
                            Text(member.text("displayName"))
                            Spacer()
                            if let relation = relationships.first(where: { $0.text("peerSubject") == member.subject }) {
                                Text(relation.text("status") == "accepted" ? String(localized: "已是朋友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "待确认", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button(String(localized: "申请好友", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { run { try await requestFriend(member) } }.disabled(busy)
                            }
                            if isActivityCreator {
                                Button(String(localized: "移出活动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { memberToRemove = member }.disabled(busy)
                            }
                        }
                    }
                    if activityMembers.filter({ !$0.flag("isSelf") }).isEmpty {
                        Text(String(localized: "邀请其他人参加活动后，可以互相申请好友。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(String(localized: "管理 · \(selectedActivity?.text("title") ?? String(localized: "活动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { showingActivityManagement = false } } }
            .confirmationDialog(String(localized: "删除活动「\(selectedActivity?.text("title") ?? "")」？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: $showingActivityDelete, titleVisibility: .visible) {
                Button(String(localized: "确认删除活动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { run { try await deleteActivity() } }
                Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .cancel) { }
            } message: { Text(String(localized: "仅可删除没有其他成员、照片或日常记录的活动；已发出的邀请会失效。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            .confirmationDialog(String(localized: "将「\(memberToRemove?.text("displayName") ?? "")」移出活动？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(
                get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }), titleVisibility: .visible) {
                Button(String(localized: "确认移出", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) {
                    guard let member = memberToRemove else { return }
                    memberToRemove = nil
                    run { try await removeActivityMember(member) }
                }
                Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .cancel) { memberToRemove = nil }
            } message: { Text(String(localized: "移出后，对方将无法查看这场活动的新内容；已有邀请链接仍可再次用于加入。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task { busy = true; error = ""; notice = ""; defer { busy = false }
            do { try await work() } catch { self.error = momentDisplayError(error) }
        }
    }
    private func refresh() async {
        do { try await load() }
        catch is CancellationError {} catch { self.error = momentDisplayError(error) }
    }
    private func openPendingActivityLink() async {
        guard !Task.isCancelled, let link = store.pendingActivityLink else { return }
        if link.invitation != nil { invitationToOpen = link; store.pendingActivityLink = nil; return }
        do {
            try openLinkedActivity(tenant: link.tenantID, activity: link.activityID)
            store.pendingActivityLink = nil
        } catch { store.error = error.localizedDescription; store.pendingActivityLink = nil }
    }

    private func openLinkedActivity(tenant: UUID, activity: UUID) throws {
        guard let item = joinedActivities.first(where: {
            UUID(uuidString: $0.id) == activity && UUID(uuidString: $0.text("sourceTenantId")) == tenant
        }) else { throw APIError.message("当前账号尚未加入这场活动，请使用活动邀请链接或联系发起人。") }
        activityId = item.id; showingActivity = true
    }

    private func acceptActivityLink(_ link: MomentActivityLink) async throws {
        guard let invitation = link.invitation,
              let token = invitation.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let response = try await store.call(base + "invites/link/\(token)/accept", method: "POST", body: [:]) as? [String: Any],
              let tenant = (response["tenantId"] as? String).flatMap(UUID.init(uuidString:)),
              let activity = (response["activityId"] as? String).flatMap(UUID.init(uuidString:)) else {
            throw APIError.message("邀请无效或已过期，请联系发起人重新分享。")
        }
        try await load()
        try openLinkedActivity(tenant: tenant, activity: activity)
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
        catch { self.error = String(localized: "活动邀请暂时无法读取：\(momentDisplayError(error))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
        do { try await loadRelationships() }
        catch { self.error = String(localized: "好友关系暂时无法读取：\(momentDisplayError(error))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }
    private func loadActivities() async throws {
        guard !spaceId.isEmpty else { activityLoading = false; return }
        activityLoading = true
        defer { activityLoading = false }
        let requestedSpace = spaceId
        let loaded: [DearRecord]
        do { loaded = try DearRecord.list(await store.call(base + "spaces/\(requestedSpace)/activities")) }
        catch {
            activityError = String(localized: "活动读取失败：\(momentDisplayError(error))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
            throw error
        }
        guard requestedSpace == spaceId else { return }
        activities = loaded
        activityError = ""
        let previousActivity = activityId
        if !loaded.contains(where: { $0.id == activityId }) && !joinedActivities.contains(where: { $0.id == activityId }) { activityId = ""; showingActivity = false }
        if activityId == previousActivity && !activityId.isEmpty {
            do { try await loadDetails() }
            catch { self.error = String(localized: "活动内容暂时无法读取：\(momentDisplayError(error))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
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
        let tenant = activityTenantId, activity = activityId
        let loaded = try DearRecord.list(await store.call(base + "tenants/\(tenant)/activities/\(activity)/live/photos"))
        guard !Task.isCancelled, tenant == activityTenantId, activity == activityId else { return }
        photos = loaded.sorted { $0.sortDate == $1.sortDate ? $0.id < $1.id : $0.sortDate > $1.sortDate }
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
                    spaceID: targetSpace, activityID: targetActivity, record: photo) { fraction in
                    batchDownloadProgress = (Double(index) + fraction) / Double(selected.count)
                }
                batchOriginalURLs.append(url)
            } catch { failures.append("\(photo.text("originalFileName"))：\(momentDisplayError(error))") }
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
        guard let location = checkInLocator.location, !checkInLocator.fetching else { throw APIError.message(String(localized: "请先获取当前位置。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        let note = checkInNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= 1000 else { throw APIError.message(String(localized: "备注不能超过 1000 字。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/checkins", method: "POST", body: [
            "requestId": checkInRequestID.uuidString,
            "latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude,
            "altitudeMeters": location.altitude, "address": checkInLocator.address,
            "note": note.isEmpty ? checkInLocator.address : note
        ])
        checkInRequestID = UUID(); try await loadCheckIns()
        notice = String(format: String(localized: "打卡已保存，海拔 %.1f 米。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), location.altitude)
    }
    private func updateCheckIn() async throws {
        guard let selectedCheckIn, selectedCheckIn.flag("canEdit") else { throw APIError.message(String(localized: "只能修改自己的打卡。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        let note = checkInNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= 1000 else { throw APIError.message(String(localized: "备注不能超过 1000 字。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        let location = checkInLocator.location
        let address = location == nil ? selectedCheckIn.text("address") : checkInLocator.address
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/checkins/\(selectedCheckIn.id)", method: "PATCH", body: [
            "latitude": location?.coordinate.latitude ?? selectedCheckIn.number("latitude"),
            "longitude": location?.coordinate.longitude ?? selectedCheckIn.number("longitude"),
            "altitudeMeters": location?.altitude ?? selectedCheckIn.number("altitudeMeters"),
            "address": address, "note": note.isEmpty ? address : note
        ])
        showingCheckIn = false; self.selectedCheckIn = nil; try await loadCheckIns(); notice = String(localized: "打卡已更新。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func loadMembers() async throws {
        guard !activityTenantId.isEmpty, !activityId.isEmpty else { return }
        activityMembers = try DearRecord.list(await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/members"))
    }
    private func removeActivityMember(_ member: DearRecord) async throws {
        guard isActivityCreator, !member.flag("isSelf"),
              let encoded = member.subject.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { throw APIError.message(String(localized: "只有活动创建者可以移除其他成员。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/members/\(encoded)", method: "DELETE")
        try await loadMembers()
        notice = String(localized: "已将成员移出活动。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func loadRelationships() async throws {
        relationships = try DearRecord.list(await store.call(base + "relationships"))
    }
    private func requestFriend(_ member: DearRecord) async throws {
        _ = try await store.call(base + "relationships/requests", method: "POST", body: ["targetSubject": member.subject, "tenantId": activityTenantId, "activityId": activityId])
        try await loadRelationships(); notice = String(localized: "好友申请已发出。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func acceptFriend(_ relation: DearRecord) async throws {
        _ = try await store.call(base + "relationships/\(relation.id)/accept", method: "POST", body: [:])
        try await loadRelationships(); notice = String(localized: "已确认好友关系。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func removeFriend(_ relation: DearRecord) async throws {
        _ = try await store.call(base + "relationships/\(relation.id)", method: "DELETE")
        try await loadRelationships(); notice = String(localized: "关系已移除。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func publishMoment() async throws {
        let body = momentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 1000 else { throw APIError.message(String(localized: "请填写 1 至 1000 字的日常内容。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/moments", method: "POST", body: ["text": body, "requestId": momentRequestID.uuidString])
        momentDraft = ""; momentRequestID = UUID(); try await loadMoments(); notice = String(localized: "日常已发布。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func deleteMoment(_ moment: DearRecord) async throws {
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/moments/\(moment.id)", method: "DELETE")
        try await loadMoments(); notice = String(localized: "日常已删除。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func createSpace() async throws {
        let value = try await store.call(base + "tenants", method: "POST", body: ["name": spaceName.trimmingCharacters(in: .whitespacesAndNewlines)])
        let item = DearRecord(data: value as? [String: Any] ?? [:])
        spaceName = ""; try await load(); spaceId = item.id; notice = String(localized: "空间已创建。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func addBookmark(_ item: DearRecord) async throws {
        guard selectedSpace?.text("role") == "owner" else { throw APIError.message(String(localized: "请先选择自己的空间。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        _ = try await store.call(base + "spaces/\(spaceId)/bookmarks", method: "POST", body: ["sourceTenantId": item.text("sourceTenantId"), "activityId": item.id])
        try await loadActivities(); notice = String(localized: "活动已收藏到空间。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func removeBookmark(_ item: DearRecord) async throws {
        guard selectedSpace?.text("role") == "owner" else { throw APIError.message(String(localized: "只有空间所有者可以取消收藏。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        _ = try await store.call(base + "spaces/\(spaceId)/bookmarks/\(item.text("sourceTenantId"))/\(item.id)", method: "DELETE")
        try await loadActivities(); notice = String(localized: "已取消收藏，原活动仍在。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func renameSpace() async throws {
        guard selectedSpace?.text("role") == "owner" else { throw APIError.message(String(localized: "只有空间所有者可以修改名称。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        let name = editedSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && name.count <= 200 else { throw APIError.message(String(localized: "请填写不超过 200 字的空间名称。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        _ = try await store.call(base + "tenants/\(spaceId)", method: "PATCH", body: ["name": name])
        try await load(); notice = String(localized: "空间名称已更新。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func deleteSpace() async throws {
        guard selectedSpace?.text("role") == "owner" else { throw APIError.message(String(localized: "只有空间所有者可以删除空间。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        _ = try await store.call(base + "tenants/\(spaceId)", method: "DELETE")
        spaceId = ""; activityId = ""; activities = []
        try await load(); notice = String(localized: "空间已删除。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func createActivity() async throws {
        let name = activityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200, newActivityDescription.count <= 2000 else { throw APIError.message("活动名称须为 1 至 200 字，介绍不超过 2000 字。") }
        let value = try await store.call(base + "tenants/\(spaceId)/activities", method: "POST", body: [
            "title": activityName.trimmingCharacters(in: .whitespacesAndNewlines), "description": newActivityDescription,
            "startsAt": ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: newActivityDate))
        ])
        let item = DearRecord(data: value as? [String: Any] ?? [:])
        activityName = ""; try await loadActivities(); activityId = item.id; showingActivity = true; notice = String(localized: "活动已创建。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func updateActivity() async throws {
        guard selectedActivity?.flag("canEdit") == true else { throw APIError.message(String(localized: "只有活动组织者可以修改基本信息。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        let name = editedActivityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && name.count <= 200 else { throw APIError.message(String(localized: "请填写不超过 200 字的活动名称。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        guard editedActivityDescription.count <= 2000 else { throw APIError.message(String(localized: "活动介绍不能超过 2000 字。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)", method: "PATCH", body: [
            "title": name, "description": editedActivityDescription,
            "startsAt": ISO8601DateFormatter().string(from: editedActivityDate)
        ])
        try await load(); notice = String(localized: "活动基本信息已更新。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func deleteActivity() async throws {
        guard selectedActivity?.flag("canEdit") == true else { throw APIError.message(String(localized: "只有活动组织者可以删除活动。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)", method: "DELETE")
        showingActivityManagement = false; showingActivity = false; activityId = ""
        try await load(); notice = String(localized: "活动已删除。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func inviteByName() async throws {
        _ = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/invites/username", method: "POST", body: ["username": inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines)])
        inviteUsername = ""; notice = String(localized: "邀请已发出，等待对方确认。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    private func createInviteLink() async throws {
        let value = try await store.call(base + "tenants/\(activityTenantId)/activities/\(activityId)/invites/link", method: "POST", body: [:])
        guard let token = (value as? [String: Any])?["token"] as? String,
              let safe = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw APIError.message(String(localized: "邀请链接无效。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        inviteLink = "https://happylife.ai.impx.net/api/dear/public/activities/\(activityTenantId)/\(activityId)?invite=\(safe)"
    }
    private func accept(_ invitation: DearRecord) async throws {
        let me = try await store.call(base + "me") as? [String: Any] ?? [:]
        guard let username = me["username"] as? String,
              let safe = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw APIError.message(String(localized: "无法确认用户名。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        _ = try await store.call(base + "tenants/\(invitation.text("tenantId"))/activities/\(invitation.text("activityId"))/invites/username/\(safe)/accept", method: "POST", body: [:])
        try await load(); activityId = invitation.text("activityId"); showingActivity = true; notice = String(localized: "已加入共同活动，可收藏到自己的空间。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
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
        default: fetching = false; error = String(localized: "请在系统设置中允许此 App 使用位置后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard fetching else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: fetching = false; error = String(localized: "位置访问未获授权，请在系统设置中开启。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard fetching else { return }
        guard let current = locations.last(where: { $0.horizontalAccuracy >= 0 && $0.verticalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 120 }) else {
            fetching = false; error = String(localized: "没有获取到有效的位置与海拔，请重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return
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
        fetching = false; self.error = String(localized: "定位失败：\(momentDisplayError(error))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
}

private struct DearBatchProgress: View {
    @ObservedObject var presentation: PhotoTransferPresentation
    let active: Bool
    var body: some View {
        if active || (presentation.progress ?? 0) > 0 && (presentation.progress ?? 0) < 1 {
            ProgressView(value: presentation.progress ?? 0)
        }
    }
}

private struct DearPhotoPreview: View {
    @ObservedObject var store: FamilyStore
    let path: String
    let photo: DearRecord
    @ObservedObject private var source: DearPhotoSource
    @State private var image: UIImage?
    @State private var failed = false
    init(store: FamilyStore, path: String, photo: DearRecord) {
        self.store = store; self.path = path; self.photo = photo; self.source = store.photoSource
    }
    var body: some View {
        GeometryReader { geometry in
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if failed {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text(String(localized: "预览失败", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption2)
                }.foregroundStyle(.secondary)
            }
            else { ProgressView() }
        }
        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped().background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: path + photo.text("thumbnailRevision") + source.originalsRevision.uuidString) {
            do {
                let parts = path.split(separator: "/").map(String.init)
                if parts.count == 10,
                   let local = await source.availableOriginal(photo: photo, spaceID: parts[4], activityID: parts[6]),
                   let original = try? await PhotoDisplayImage.preview(local, isVideo: photo.text("contentType").hasPrefix("video/")) {
                    try Task.checkCancellation(); image = original; failed = false; return
                }
                let preview = try await store.authenticatedImage(path)
                try Task.checkCancellation(); image = preview; failed = false
            }
            catch is CancellationError { }
            catch { image = nil; failed = true }
        }
    }
}

private struct DearPhotoCommentsView: View {
    @ObservedObject var store: FamilyStore
    let spaceID: String
    let activityID: String
    let photoID: String
    var allowsComposition = true
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
            if allowsComposition && loaded && comments.isEmpty { Text("还没有点评，说说这张照片吧。").font(.caption).foregroundStyle(.secondary) }
            if !failure.isEmpty {
                Text(failure).font(.caption).foregroundStyle(.red)
                Button("重新加载点评") { perform { try await load(reset: true) } }.font(.caption).disabled(busy)
            }
            if allowsComposition {
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
            }
        }.buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task { do { try await load(reset: true) } catch is CancellationError { } catch { failure = error.localizedDescription } }
    }
    @MainActor private func load(reset: Bool) async throws {
        let skip = reset ? 0 : nextSkip
        guard let result = try await store.call(route + "?skip=\(skip)") as? [String: Any] else { throw APIError.message("无法读取点评。") }
        guard let values = result["items"] else { throw APIError.message("点评返回格式无效。") }
        let rows = try DearRecord.list(values)
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
    @ObservedObject var notifications: MomentNotifications
    let photos: [DearRecord]
    let spaceID: String
    let activityID: String
    let allowsDeletion: Bool
    let onDeleted: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String

    init(store: FamilyStore, photos: [DearRecord], initialPhotoID: String, spaceID: String, activityID: String,
         allowsDeletion: Bool, onDeleted: @escaping (String, Bool) -> Void) {
        self.store = store; self.notifications = store.notifications; self.spaceID = spaceID; self.activityID = activityID
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
                                        active: photo.id == selectedID,
                                        onDeleted: { removed in onDeleted(photo.id, removed); dismiss() },
                                        onSwipeDown: { dismiss() },
                                        onPageSwipe: { offset in
                                            guard let index = photos.firstIndex(where: { $0.id == photo.id }), photos.indices.contains(index + offset) else { return }
                                            let target = photos[index + offset].id
                                            if target != selectedID { withAnimation(.easeInOut(duration: 0.2)) { selectedID = target } }
                                        })
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle("\((photos.firstIndex(where: { $0.id == selectedID }) ?? 0) + 1) / \(photos.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark").accessibilityLabel("关闭照片查看") } }
            }
            .onChange(of: notifications.showingInbox) { _, showing in if showing { dismiss() } }
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
    var active = true
    var downloadRequestID: UUID? = nil
    let onDeleted: (Bool) -> Void
    var onSwipeDown: (() -> Void)? = nil
    var onPageSwipe: ((Int) -> Void)? = nil
    @State private var dismissOffset = 0.0
    @State private var downwardDrag: Bool?
    @State private var image: UIImage?
    @State private var error: String?
    @State private var originalURL: URL?
    @State private var player: AVPlayer?
    @State private var originalImage: UIImage?
    @State private var originalError: String?
    @State private var fetchingOriginal = false
    @State private var savingOriginal = false
    @State private var originalSaved = false
    @State private var serverCacheReady: Bool?
    @State private var downloadStatus = ""
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
                        ContentUnavailableView(String(localized: "无法显示照片预览", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "photo.badge.exclamationmark",
                                                   description: Text(error))
                        Button(String(localized: "重试", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await load() } }
                    } else { ProgressView(String(localized: "正在加载照片", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
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
                        let page = PhotoViewerSwipe.pageOffset(horizontal: value.translation.width,
                            vertical: value.translation.height, predictedHorizontal: value.predictedEndTranslation.width)
                        if close { onSwipeDown?() }
                        else if page != 0 { dismissOffset = 0; onPageSwipe?(page) }
                        else { withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { dismissOffset = 0 } }
                    })
                Text(photo.text("originalFileName")).font(.headline)
                if let downloadRequestID {
                    MomentPhotoRequestProgress(store: store, requestID: downloadRequestID)
                }
                Text("分享者：\(photo.text("sourceDisplayName"))").font(.subheadline).foregroundStyle(.secondary)
                Label(store.photoSource.deviceDescription(photo.data), systemImage: "iphone").font(.caption).foregroundStyle(.secondary)
                if store.photoSource.isSourceDevice(photo) {
                    Text(originalURL != nil ? "正在使用本机原件" : "正在读取本机相册原件")
                        .font(.caption).foregroundStyle(.secondary)
                } else { Text((serverCacheReady ?? photo.flag("serverCached")) ? "服务器已缓存，可在共享设备离线时获取" : "服务器尚未缓存，获取原件需等待共享设备上线").font(.caption).foregroundStyle(.secondary) }
                Text("分享时间：\(photo.dateText("createdAt"))").font(.subheadline).foregroundStyle(.secondary)
                DearPhotoPlaceView(photo: photo).font(.subheadline).foregroundStyle(.secondary)
                if let originalURL {
                    HStack(spacing: 20) {
                        Button { Task { await saveOriginalToPhotos(originalURL) } } label: {
                            Label(originalSaved ? "已保存到照片" : savingOriginal ? "正在保存…" : "保存到照片", systemImage: originalSaved ? "checkmark.circle" : "square.and.arrow.down")
                        }.disabled(savingOriginal || originalSaved)
                        ShareLink(item: DearOriginalFile(url: originalURL), preview: SharePreview(photo.text("originalFileName"))) {
                            Label(String(localized: "分享原文件", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "square.and.arrow.up")
                        }
                    }
                } else if store.photoSource.isSourceDevice(photo) {
                    if fetchingOriginal { ProgressView("正在读取本机原件") }
                    else { Button("重新读取相册原件") { Task { await fetchOriginal() } } }
                } else {
                    Button {
                        Task { await fetchOriginal() }
                    } label: {
                        Label(fetchingOriginal ? (downloadStatus == "正在接收原文件" ? "正在接收原文件：\(Int(transferProgress * 100))%" : downloadStatus) : originalError == nil ? String(localized: "获取原文件", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "继续获取原文件", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "arrow.down.circle")
                    }.disabled(fetchingOriginal)
                }
                if fetchingOriginal || transferProgress > 0 && transferProgress < 1 {
                    ProgressView(value: transferProgress)
                        .accessibilityLabel(String(localized: "原文件接收进度", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                }
                if let originalError { Text(originalError).font(.footnote).foregroundStyle(.red) }
                if active { DearPhotoCommentsView(store: store, spaceID: spaceID, activityID: activityID, photoID: photo.id) }
                if canDelete {
                    Button(String(localized: "删除分享", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { showingDelete = true }.disabled(deleting)
                }
                if !store.photoSource.isSourceDevice(photo) {
                    Text("原文件可从共享设备或服务器缓存获取。服务器最多缓存 1 GB，较久未使用的文件可能被淘汰；未缓存时需等待共享设备上线。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .confirmationDialog(String(localized: "删除这项分享？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: $showingDelete, titleVisibility: .visible) {
            Button(String(localized: "删除分享", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { Task { await deleteSharedMedia() } }
            Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .cancel) { }
        } message: { Text(String(localized: "活动成员将无法再获取此文件；iPhone 相册中的原文件不会删除。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        .task(id: path + String(active)) {
            if active { await load() }
            else { player?.pause(); player = nil; image = nil; originalImage = nil }
        }
        .task(id: photo.id + String(active) + "relay-status") {
            guard active, !photo.text("sourceDeviceId").isEmpty else { return }
            for _ in 0..<6 {
                guard !Task.isCancelled else { return }
                if let state = try? await store.call("/api/dear/social/tenants/\(spaceID)/activities/\(activityID)/native-photos/\(photo.id)/relay") as? [String: Any],
                   let cached = state["cached"] as? Bool {
                    serverCacheReady = cached
                    if cached { return }
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .onDisappear { player?.pause() }
    }

    private func load() async {
        image = nil; error = nil
        if let originalURL {
            if isVideo { player = AVPlayer(url: originalURL) }
            else if let loaded = try? await PhotoDisplayImage.load(originalURL), !Task.isCancelled { originalImage = loaded }
            return
        }
        if let local = await store.photoSource.availableOriginal(photo: photo, spaceID: spaceID, activityID: activityID), !Task.isCancelled {
            originalURL = local
            if isVideo { player = AVPlayer(url: local) }
            else { originalImage = try? await PhotoDisplayImage.load(local) }
            return
        }
        if Task.isCancelled { return }
        if store.photoSource.isSourceDevice(photo) {
            originalError = "无法读取本机原件。请允许访问对应相册；若原件只在 iCloud，请先在系统照片中打开。无需向自己下载或手动匹配。"
        }
        do { let loaded = try await store.authenticatedImage(path); if !Task.isCancelled { image = loaded } }
        catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func fetchOriginal() async {
        fetchingOriginal = true; transferProgress = 0; originalError = nil; downloadStatus = store.photoSource.isSourceDevice(photo) ? "正在读取本机原件…" : "正在创建下载请求…"
        defer { fetchingOriginal = false }
        do {
            let url = try await store.photoSource.downloadOriginal(photoID: photo.id, spaceID: spaceID, activityID: activityID, record: photo, status: { downloadStatus = $0 }) {
                downloadStatus = "正在接收原文件"; transferProgress = max(transferProgress, $0)
            }
            if !isVideo {
                originalImage = try await PhotoDisplayImage.load(url)
            }
            originalURL = url
            if isVideo { player = AVPlayer(url: url) }
        } catch { originalError = error.localizedDescription }
    }

    private func saveOriginalToPhotos(_ url: URL) async {
        guard !savingOriginal && !originalSaved else { return }
        savingOriginal = true; originalError = nil
        defer { savingOriginal = false }
        do {
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
                throw APIError.message("原文件尚未接收完成，请重新获取。")
            }
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                throw APIError.message("请在系统设置中允许添加照片，原文件仍保留在 App 中。")
            }
            let video = isVideo
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: video ? .video : .photo, fileURL: url, options: nil)
            }
            originalSaved = true
        } catch { originalError = error.localizedDescription }
    }

    private func deleteSharedMedia() async {
        deleting = true; originalError = nil
        defer { deleting = false }
        do {
            let localCopyRemoved = try await store.photoSource.revoke(photoID: photo.id, spaceID: spaceID, activityID: activityID)
            onDeleted(localCopyRemoved)
        } catch { originalError = momentDisplayError(error) }
    }
}


struct MomentNotificationInbox: View {
    @ObservedObject var store: FamilyStore
    @ObservedObject var notifications: MomentNotifications
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteAll = false
    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "积分申请通知", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    NavigationLink { ApprovalList(store: store) } label: {
                        LabeledContent(String(localized: "奖励审批", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), value: "\(store.requests.filter { $0.text("status") == "pending" }.count)")
                    }
                }
                if !notifications.error.isEmpty { Section { Text(notifications.error).foregroundStyle(.red) } }
                if !notifications.pushRegistrationError.isEmpty { Section { Text(notifications.pushRegistrationError).foregroundStyle(.red) } }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("全部已读", systemImage: "checkmark.circle") { Task { await notifications.markAllRead() } }
                        .labelStyle(.iconOnly).disabled(notifications.unreadCount == 0 || notifications.editingInbox)
                    Button("全部删除", systemImage: "trash", role: .destructive) { confirmDeleteAll = true }
                        .labelStyle(.iconOnly).disabled(notifications.items.isEmpty || notifications.editingInbox)
                    Menu {
                        Button(notifications.enableButtonTitle) { Task { await notifications.enable() } }
                            .disabled(notifications.enabling || notifications.registering)
                        Button("系统通知设置", systemImage: "gearshape") { notifications.openSettings() }
                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("消息操作与设置") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .confirmationDialog("删除当前账号的全部应用消息？", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("全部删除", role: .destructive) { Task { await notifications.deleteAll() } }
                Button("取消", role: .cancel) { }
            } message: { Text("仅删除消息，原图下载请求和活动照片保留。") }
            .refreshable { await store.refreshRequests(); await notifications.reload() }
            .task { await store.refreshRequests(); await notifications.reload() }
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
    @State private var thumbnail: UIImage?
    @State private var error = ""
    @State private var refreshing = false
    @State private var recovering = false
    @State private var selectedOriginal: PhotosPickerItem?
    @State private var recoveryStatus = "正在核验本机原件…"
    @State private var libraryRecoveryTask: Task<Void, Never>?
    private var requestID: UUID? {
        guard let source = item.sourceRecordId, source.hasPrefix("photo-request:") else { return nil }
        return UUID(uuidString: String(source.dropFirst("photo-request:".count)))
    }
    private var status: String {
        switch request?.text("status") {
        case "pending_approval": return "等待分享者打开消息同意"
        case "waiting": return request?.flag("serverCached") == true ? "原文件已就绪，等待请求人打开 App 接收" : "已同意，正在等待原文件；可在本机恢复共享"
        case "transferring": return "正在传输原文件"
        case "confirming": return "正在核验下载文件"
        case "completed": return "下载已完成"
        case "expired": return "请求已过期，请对方重新请求"
        case "cancelled": return "本次分享已停止或下载已取消"
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
                    if let request, !request.text("activityTitle").isEmpty { Label(request.text("activityTitle"), systemImage: "calendar") }
                    if let request {
                        if let photo = request.data["photo"] as? [String: Any], let requestID {
                            NavigationLink {
                                DearPhotoDetailView(store: store, photo: DearRecord(data: photo),
                                    spaceID: request.text("tenantId"), activityID: request.text("activityId"),
                                    path: thumbnailPath(request), canDelete: false, downloadRequestID: requestID,
                                    onDeleted: { _ in })
                                    .navigationTitle("照片详情")
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                HStack(spacing: 12) {
                                    Group {
                                        if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
                                        else { Image(systemName: request.text("contentType").hasPrefix("video/") ? "video" : "photo").foregroundStyle(.secondary) }
                                    }
                                    .frame(width: 88, height: 88).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(request.text("fileName")).font(.headline).lineLimit(2)
                                        Text(ByteCountFormatter.string(fromByteCount: Int64(request.number("length")), countStyle: .file))
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text("查看照片详情与下载进度").font(.caption)
                                    }
                                }
                            }
                        } else { Text("照片已撤销或暂不可访问").foregroundStyle(.secondary) }
                        Text("请求人：\(request.text("requesterDisplayName").isEmpty ? "成员 " + request.text("requester") : request.text("requesterDisplayName"))")
                        Text(request.text("fileName")); Text(status)
                    }
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                    Button("刷新请求状态") { Task { await loadRequest() } }.disabled(refreshing)
                    if request?.flag("canStop") == true, let requestID {
                        Button("停止本次分享", role: .destructive) {
                            Task {
                                do { try await store.photoSource.stopRequest(requestID); await loadRequest() }
                                catch { self.error = "停止分享未完成，请重试。" }
                            }
                        }.disabled(refreshing)
                    }
                    if request?.flag("canStop") == true, request?.text("status") == "waiting", request?.flag("serverCached") != true {
                        Button("自动匹配本机与系统相册原件") {
                            libraryRecoveryTask = Task {
                                let permission = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                                if permission == .authorized || permission == .limited { await restoreOriginal() }
                                else { error = "相册访问未获允许。可在系统设置中允许访问，或使用下面的手动选择。" }
                            }
                        }.disabled(recovering || refreshing)
                        if [.denied, .limited].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite)) {
                            Button("调整相册访问范围") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                        }
                        PhotosPicker(selection: $selectedOriginal, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                            Label("选择本机原文件继续分享", systemImage: "photo.on.rectangle")
                        }.disabled(recovering || refreshing)
                        if recovering { ProgressView(recoveryStatus) }
                        Text("请求时按已保存的副本或相册标识直接定位。只有主动恢复时才扫描已授权范围；原件始终按文件大小和 SHA-256 校验。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("消息详情")
        .task {
            await notifications.markRead(item); await loadRequest()
            await restoreOriginal(silent: true)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                await loadRequest()
            }
        }
        .onDisappear { libraryRecoveryTask?.cancel() }
        .onChange(of: selectedOriginal) { _, item in
            guard let item else { return }
            Task {
                recovering = true; defer { recovering = false; selectedOriginal = nil }
                do {
                    guard let file = try await item.loadTransferable(type: DearPickedOriginal.self), let request else { throw APIError.message("无法读取所选原文件。") }
                    defer { try? FileManager.default.removeItem(at: file.url) }
                    _ = try await store.photoSource.restoreOriginal(for: request.data, selectedFile: file.url, selectedAssetIdentifier: item.itemIdentifier)
                    await loadRequest()
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    private func restoreOriginal(silent: Bool = false) async {
        guard let request, request.flag("canStop"), request.text("status") == "waiting", !request.flag("serverCached"), !recovering else { return }
        recovering = true; defer { recovering = false }
        do {
            error = ""; recoveryStatus = "正在核验本机原件…"
            let restored = try await store.photoSource.restoreOriginal(for: request.data, allowLibraryScan: !silent) { recoveryStatus = $0 }
            if restored { await loadRequest() }
            else if !silent { error = "在 App 和已授权的本机相册中未匹配到一致原件。云端原件需先下载到本机；也可手动选择原文件。" }
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func thumbnailPath(_ request: DearRecord) -> String {
        "/api/dear/social/tenants/\(request.text("tenantId"))/activities/\(request.text("activityId"))/native-photos/\(request.text("photoId"))/thumbnail"
    }
    private func loadRequest() async {
        guard let requestID else { return }
        refreshing = true; defer { refreshing = false }
        do {
            guard let row = try await store.call("/api/dear/social/photo-requests/\(requestID.uuidString)") as? [String: Any] else { throw APIError.message("请求数据无效。") }
            var updated = row
            if row["canApprove"] as? Bool == true {
                _ = try await store.call("/api/dear/social/photo-requests/\(requestID.uuidString)/approve", method: "POST", body: [:])
                if let approved = try await store.call("/api/dear/social/photo-requests/\(requestID.uuidString)") as? [String: Any] { updated = approved }
                await store.photoSource.serveCurrentRequests()
            }
            let record = DearRecord(data: updated)
            request = record
            if thumbnail == nil, updated["photo"] is [String: Any] {
                thumbnail = try? await store.authenticatedImage(thumbnailPath(record))
            }
        } catch { self.error = "请求已不可访问或登录已过期，请刷新后重试。" }
    }
}


private struct MomentPhotoRequestProgress: View {
    @ObservedObject var store: FamilyStore
    let requestID: UUID
    @State private var request: DearRecord?
    @State private var failed = false
    private var phase: String {
        switch request?.text("status") {
        case "pending_approval": return "等待分享者同意"
        case "waiting": return request?.flag("serverCached") == true ? "原文件已缓存，等待接收端继续下载" : "已同意，等待原文件设备上线或恢复共享"
        case "transferring": return "正在传输原文件"
        case "confirming": return "正在接收或校验原文件"
        case "completed": return "下载已完成"
        case "cancelled": return "下载已取消或已停止分享"
        case "expired": return "下载请求已过期"
        case "revoked": return "分享已撤销或成员权限已变更"
        case "unavailable": return "原文件暂不可用"
        case "failed": return "下载未完成，请重新请求"
        default: return "正在读取下载状态"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这次下载请求").font(.headline)
            if let request {
                Text("请求人：\(request.text("requesterDisplayName").isEmpty ? request.text("requester") : request.text("requesterDisplayName"))")
                    .font(.subheadline)
                Text(phase).font(.subheadline)
                if request.text("status") == "completed" {
                    ProgressView(value: 1).accessibilityLabel("下载已完成")
                } else if let bytes = request.data["relayBytesSent"] as? NSNumber, request.number("length") > 0 {
                    let value = min(0.99, bytes.doubleValue / request.number("length"))
                    ProgressView(value: value).accessibilityLabel("服务器发送进度")
                    Text("服务器已发送 \(Int(value * 100))%，接收端校验后完成")
                        .font(.caption).foregroundStyle(.secondary)
                } else if ["transferring", "confirming"].contains(request.text("status")) {
                    ProgressView().accessibilityLabel(phase)
                }
            } else { ProgressView() }
            if failed { Text("状态更新暂时失败，正在重试。 ").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .task(id: requestID) {
            while !Task.isCancelled {
                do {
                    if let row = try await store.call("/api/dear/social/photo-requests/\(requestID.uuidString)") as? [String: Any] {
                        guard !Task.isCancelled else { return }
                        request = DearRecord(data: row); failed = false
                        if ["completed", "cancelled", "expired", "revoked", "unavailable", "failed"].contains(request?.text("status") ?? "") { return }
                    }
                } catch is CancellationError { return }
                catch { failed = true }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}

struct MomentNotificationButton: View {
    @ObservedObject var notifications: MomentNotifications
    var pendingRequests: Int = 0
    private var count: Int { notifications.unreadCount + pendingRequests }
    var body: some View {
        Button { notifications.open() } label: {
            Image(systemName: count > 0 ? "bell.badge" : "bell")
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)").font(.caption2.bold()).foregroundStyle(.white).padding(3).background(.red, in: Capsule()).offset(x: 10, y: -8)
                    }
                }
        }.accessibilityLabel(String(localized: "消息通知，\(count) 条待处理或未读", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
    }
}

private struct DearActivityShareLink: View {
    let url: URL
    let title: String
    let label: String
    var body: some View {
        ShareLink(item: "\(title)\n\(url.absoluteString)") {
            Label(label, systemImage: "square.and.arrow.up")
        }
    }
}
