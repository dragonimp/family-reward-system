import CryptoKit
import MyVncRealtime
import AgentIdentity
import SwiftUI
import Foundation
import UIKit
import UserNotifications
import AVFoundation
import ImageIO
import Photos
import UniformTypeIdentifiers

// Linko Social keeps original media bytes on the source device. This adapter
// stores selected photos and videos on the iPhone and serves verified requests.
@MainActor final class DearPhotoSource: ObservableObject {
    @Published private(set) var originalsRevision = UUID()
    private struct SharedPhoto: Codable {
        let id: String
        let spaceID: String
        let activityID: String
        let fileName: String
        let length: Int
        let sha256: String
        var assetIdentifier: String? = nil
        var originalFileName: String? = nil
    }
    private struct Index: Codable {
        var deviceID: String?
        var photos: [SharedPhoto] = []
        var pendingRemoval: [SharedPhoto] = []

        init() { }

        private enum CodingKeys: String, CodingKey { case deviceID, photos, pendingRemoval }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            deviceID = try values.decodeIfPresent(String.self, forKey: .deviceID)
            photos = try values.decodeIfPresent([SharedPhoto].self, forKey: .photos) ?? []
            pendingRemoval = try values.decodeIfPresent([SharedPhoto].self, forKey: .pendingRemoval) ?? []
        }
    }

    weak var store: FamilyStore?
    private var pump: Task<Void, Never>?
    private var cacheTask: Task<Void, Never>?
    private var librarySearch: Task<URL?, Error>?
    private var fileVerifiers: [String: OriginalFileVerifier] = [:]
    private var localReads: [String: Task<URL?, Never>] = [:]
    private var legacyLibraryAttempts = Set<String>()
    private var legacyRead: Task<URL?, Error>?
    private var cachedShares = Set<String>()
    private var cacheRetries: [String: Date] = [:]
    private(set) var currentDeviceID: String?

    private var deviceModel: String {
        var system = utsname(); uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
    private var deviceInformation: [String: Any] {
        ["deviceName": UIDevice.current.name, "deviceModel": deviceModel, "platform": "iOS " + UIDevice.current.systemVersion]
    }
    func deviceDescription(_ photo: [String: Any]) -> String {
        let id = (photo["sourceDeviceId"] as? String ?? "")
        let name = (photo["sourceDeviceName"] as? String ?? "")
        let model = (photo["sourceDeviceModel"] as? String ?? "")
        let platform = (photo["sourceDevicePlatform"] as? String ?? "")
        let detail = [name, model, platform].filter { !$0.isEmpty }.joined(separator: " · ")
        let relation = id.isEmpty ? "来源设备未登记" : currentDeviceID == nil ? "来源设备" : id.caseInsensitiveCompare(currentDeviceID!) == .orderedSame ? "本机" : "其他设备"
        return relation + (detail.isEmpty ? "" : " · " + detail)
    }

    private var subjectCache: String?
    private var enabledForSession = false
    private var publishing = false
    private var polling = false
    private var transfers: [UUID: RealtimeFileTransfer] = [:]
    private var downloads = Set<String>()
    private var sourceTasks: [String: Task<Void, Never>] = [:]
    private var generation = UUID()
    private var importingSharedItems = false
    private var checkedLocationIDs = Set<String>()
    private let session = URLSession(configuration: .ephemeral)
    private let base = URL(string: "https://happylife.ai.impx.net")!

    func start() {
        guard pump == nil else { return }
        pump = Task {
            while !Task.isCancelled {
                if !enabledForSession { await enableExistingDevice() }
                if enabledForSession { await poll() }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stop() {
        for task in localReads.values { task.cancel() }; localReads.removeAll(); fileVerifiers.removeAll(); legacyLibraryAttempts.removeAll(); legacyRead?.cancel(); legacyRead = nil
        generation = UUID(); originalsRevision = UUID(); librarySearch?.cancel(); librarySearch = nil; cacheTask?.cancel(); cacheTask = nil; cachedShares.removeAll(); cacheRetries.removeAll(); currentDeviceID = nil; pump?.cancel(); pump = nil; enabledForSession = false
        for task in sourceTasks.values { task.cancel() }; sourceTasks.removeAll()
        let active = Array(transfers.values); transfers.removeAll()
        for transfer in active { Task { await transfer.cancel() } }
    }
    func reset() { stop(); subjectCache = nil; checkedLocationIDs.removeAll() }

    func cacheShareActivities(_ rows: [[String: Any]]) async {
        guard let subject = try? await currentSubject() else { return }
        let account = SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
        let formatter = ISO8601DateFormatter()
        let activities = rows.compactMap { row -> DearShareInbox.Activity? in
            guard let id = row["id"] as? String, UUID(uuidString: id) != nil,
                  let tenant = row["sourceTenantId"] as? String, UUID(uuidString: tenant) != nil,
                  let title = row["title"] as? String else { return nil }
            let raw = (row["startsAt"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (row["createdAt"] as? String) ?? ""
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) ?? .distantPast
            return .init(id: id, tenantID: tenant, title: title, date: date)
        }.sorted { $0.date > $1.date }
        try? DearShareInbox.saveCatalog(.init(account: account, activities: activities))
    }

    func importSharedItems() async {
        guard !importingSharedItems, let store, store.identity.isAuthenticated,
              let subject = try? await currentSubject(),
              let root = try? DearShareInbox.pendingRoot() else { return }
        importingSharedItems = true
        defer { importingSharedItems = false }
        let account = SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
        guard let rows = try? await store.call("/api/dear/social/activities/joined") as? [[String: Any]] else { return }
        let allowed = Set(rows.compactMap { row -> String? in
            guard let tenant = row["sourceTenantId"] as? String, let activity = row["id"] as? String else { return nil }
            return tenant + "/" + activity
        })
        guard let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        var imported = 0
        for directory in directories where directory.hasDirectoryPath && UUID(uuidString: directory.lastPathComponent) != nil {
            let manifest = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifest),
                  var batch = try? JSONDecoder().decode(DearShareInbox.Batch.self, from: data),
                  batch.account == account,
                  allowed.contains(batch.tenantID + "/" + batch.activityID) else { continue }
            for item in batch.items {
                guard item.fileName == URL(fileURLWithPath: item.fileName).lastPathComponent,
                      !item.fileName.contains("..") else { break }
                let url = directory.appendingPathComponent(item.fileName)
                do {
                    if item.mediaType == "video" {
                        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                        try FileManager.default.copyItem(at: url, to: copy)
                        defer { try? FileManager.default.removeItem(at: copy) }
                        try await publishVideo(at: copy, spaceID: batch.tenantID, activityID: batch.activityID)
                    } else if item.mediaType == "image" {
                        let imageData = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
                        try await publish(imageData, spaceID: batch.tenantID, activityID: batch.activityID,
                                          name: item.displayName,
                                          locationName: DearPhotoLocation.label(in: imageData) ?? "")
                    } else { break }
                    batch.items.removeFirst()
                    try DearShareInbox.save(batch, at: directory)
                    try? FileManager.default.removeItem(at: url)
                    imported += 1
                } catch {
                    store.error = "相册分享尚未完成：\(error.localizedDescription)。打开 App 后会重试。"
                    break
                }
            }
            if batch.items.isEmpty { try? FileManager.default.removeItem(at: directory) }
        }
        if imported > 0 { store.photoRequestNotice = "已从相册共享 \(imported) 项到活动；请保持 App 打开，以便他人获取原文件。" }
    }

    private func enableNotificationsIfNeeded() async -> Bool {
        guard let store, UIApplication.shared.applicationState == .active else { return false }
        await store.notifications.resume()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func logout(token: String?) {
        let deviceID: String? = subjectCache.flatMap { subject in
            guard let root = try? directory(for: subject) else { return nil }
            return try? readIndex(at: root).deviceID
        }
        reset()
        guard let token, let deviceID else { return }
        Task {
            var request = URLRequest(url: URL(string: "/api/dear/social/photo-devices/\(deviceID)", relativeTo: base)!.absoluteURL)
            request.httpMethod = "DELETE"; request.timeoutInterval = 15
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: request)
        }
    }

    private func enableExistingDevice() async {
        guard let store, let subject = try? await currentSubject(), let root = try? directory(for: subject),
              let index = try? readIndex(at: root) else { return }
        if !index.pendingRemoval.isEmpty { _ = try? cleanPendingRemoval(at: root) }
        do {
            var body: [String: Any] = deviceInformation.merging(["notificationApplicationKey": "happylife.ai", "transferProtocol": "connect-datachannel-v1"]) { _, value in value }
            if let deviceID = index.deviceID { body["id"] = deviceID }
            let response = try await store.call("/api/dear/social/photo-devices", method: "POST", body: body) as? [String: Any]
            guard let deviceID = response?["id"] as? String, UUID(uuidString: deviceID) != nil else { return }
            if index.deviceID == nil {
                var updated = index
                updated.deviceID = deviceID
                try writeIndex(updated, at: root)
            }
            currentDeviceID = deviceID; store.objectWillChange.send()
            enabledForSession = true
            // Every signed-in phone may alert the sharer, even if another
            // device holds the original. Re-register invalidated tokens too.
            if (response?["pushRegistered"] as? Bool) == false {
                _ = await enableNotificationsIfNeeded()
            }
        } catch { }
    }

    static func originalFileName(assetIdentifier: String?, fallback: String) -> String {
        if let assetIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject,
           let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo || $0.type == .video }),
           !resource.originalFilename.isEmpty { return String(resource.originalFilename.prefix(200)) }
        let file = URL(fileURLWithPath: fallback).lastPathComponent
        let stem = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        if !stem.isEmpty && UUID(uuidString: stem) == nil && !["照片", "视频", "iPhone照片", "iPhone视频", "相机照片", "image", "photo"].contains(stem) { return String(file.prefix(200)) }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = URL(fileURLWithPath: file).pathExtension
        return "\(["mov", "mp4"].contains(suffix.lowercased()) ? "视频" : "照片")-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6))" + (suffix.isEmpty ? "" : "." + suffix)
    }

    func publish(_ imageData: Data, spaceID: String, activityID: String, name: String, locationName: String = "", assetIdentifier: String? = nil) async throws {
        guard imageData.count > 0, imageData.count <= 50 * 1024 * 1024,
              UIImage(data: imageData) != nil else { throw APIError.message("照片文件无效或超过 50 MB。") }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier) else { throw APIError.message("无法识别照片格式。") }
        let format: (mime: String, ext: String)
        if type.conforms(to: .jpeg) { format = ("image/jpeg", "jpg") }
        else if type.conforms(to: .png) { format = ("image/png", "png") }
        else if type.conforms(to: .heic) { format = ("image/heic", "heic") }
        else if type.conforms(to: .webP) { format = ("image/webp", "webp") }
        else { throw APIError.message("该照片格式暂不支持共享。") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + format.ext)
        try await Task.detached(priority: .utility) { try imageData.write(to: temporary, options: .atomic) }.value
        defer { try? FileManager.default.removeItem(at: temporary) }
        let fileName = name.contains(".") ? name : name + "." + format.ext
        try await publishMedia(at: temporary, contentType: format.mime, spaceID: spaceID, activityID: activityID, name: fileName, locationName: locationName, assetIdentifier: assetIdentifier)
    }

    func publishVideo(at url: URL, spaceID: String, activityID: String, locationName: String = "", name: String? = nil, assetIdentifier: String? = nil) async throws {
        let length = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...500 * 1024 * 1024).contains(length) else { throw APIError.message("视频必须在 500 MB 以内。") }
        let type = url.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"
        let fileName = name ?? Self.originalFileName(assetIdentifier: assetIdentifier, fallback: "视频." + (type == "video/mp4" ? "mp4" : "mov"))
        try await publishMedia(at: url, contentType: type, spaceID: spaceID, activityID: activityID, name: fileName, locationName: locationName, assetIdentifier: assetIdentifier)
    }

    private func publishMedia(at sourceURL: URL, contentType: String, spaceID: String, activityID: String, name: String, locationName: String, assetIdentifier: String? = nil) async throws {
        guard !publishing else { throw APIError.message("另一张照片正在共享，请稍后重试。") }
        publishing = true
        defer { publishing = false }
        let length = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let limit = contentType.starts(with: "video/") ? 500 * 1024 * 1024 : 50 * 1024 * 1024
        guard UUID(uuidString: spaceID) != nil, UUID(uuidString: activityID) != nil,
              length > 0, length <= limit else { throw APIError.message("照片或视频文件超过大小限制。") }
        guard let store else { throw APIError.message("活动服务暂不可用。") }
        let subject = try await currentSubject()
        let root = try directory(for: subject)
        var index = try readIndex(at: root)
        let deviceBody = deviceInformation.merging(["id": index.deviceID as Any? ?? NSNull(), "notificationApplicationKey": "happylife.ai", "transferProtocol": "connect-datachannel-v1"]) { _, value in value }
        let device = try await store.call("/api/dear/social/photo-devices", method: "POST",
                                          body: deviceBody) as? [String: Any]
        guard let deviceID = device?["id"] as? String, UUID(uuidString: deviceID) != nil else {
            throw APIError.message("照片分享设备登记失败。")
        }
        index.deviceID = deviceID; currentDeviceID = deviceID
        try writeIndex(index, at: root)
        enabledForSession = true

        let suffix: String
        switch contentType {
        case "video/mp4": suffix = ".mp4"
        case "video/quicktime": suffix = ".mov"
        case "image/png": suffix = ".png"
        case "image/heic": suffix = ".heic"
        case "image/webp": suffix = ".webp"
        default: suffix = ".jpg"
        }
        let localName = UUID().uuidString + suffix
        let localURL = root.appendingPathComponent(localName)
        do {
            try await Task.detached(priority: .utility) {
                try FileManager.default.copyItem(at: sourceURL, to: localURL)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: localURL.path)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            throw error
        }
        let displayName = String(name.prefix(200)).isEmpty ? "共享媒体.jpg" : String(name.prefix(200))
        let prefix = "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)"
        var publishedID: String?
        do {
            let sha = try await hashFile(localURL)
            let thumbnail = try await Task.detached(priority: .utility) { try Self.preview(fromFile: localURL) }.value
            let geography = await DearPhotoLocation.geography(at: localURL, fallbackName: locationName)
            let response = try await store.call(prefix + "/native-photos", method: "POST", body: [
                "deviceId": deviceID, "fileName": displayName, "contentType": contentType,
                "length": length, "sha256": sha, "locationName": String(geography.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
                "latitude": geography.latitude as Any? ?? NSNull(), "longitude": geography.longitude as Any? ?? NSNull(),
                "altitudeMeters": geography.altitudeMeters as Any? ?? NSNull()]) as? [String: Any]
            guard let photoID = response?["id"] as? String, UUID(uuidString: photoID) != nil else {
                throw APIError.message("照片登记回执无效。")
            }
            publishedID = photoID
            index.photos.append(SharedPhoto(id: photoID, spaceID: spaceID, activityID: activityID,
                                            fileName: localName, length: length, sha256: sha, assetIdentifier: assetIdentifier, originalFileName: displayName))
            try writeIndex(index, at: root)
            do {
                try await uploadThumbnail(thumbnail, prefix: prefix, photoID: photoID, revision: sha)
            } catch {
                // The original remains available. Opening the album retries a missing preview.
            }
            start()
            if !(await enableNotificationsIfNeeded()) {
                store.error = "有人请求原图时需要通知提醒。请在系统设置中允许 Linko Moment 发送通知，并保持 App 打开完成传输。"
            }
        } catch {
            if let publishedID {
                if (try? await store.call(prefix + "/live/photos/\(publishedID)", method: "DELETE")) != nil {
                    try? FileManager.default.removeItem(at: localURL)
                }
            } else {
                try? FileManager.default.removeItem(at: localURL)
            }
            throw error
        }
    }

    func revoke(photoID: String, spaceID: String, activityID: String) async throws -> Bool {
        guard UUID(uuidString: photoID) != nil, UUID(uuidString: spaceID) != nil,
              UUID(uuidString: activityID) != nil, let store else { throw APIError.message("照片或视频标识无效。") }
        let prefix = "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)"
        _ = try await store.call(prefix + "/live/photos/\(photoID)", method: "DELETE")
        guard let subject = try? await currentSubject(), let root = try? directory(for: subject) else { return true }
        var index = try readIndex(at: root)
        let removed = index.photos.filter { UUID(uuidString: $0.id) == UUID(uuidString: photoID) && UUID(uuidString: $0.spaceID) == UUID(uuidString: spaceID) && UUID(uuidString: $0.activityID) == UUID(uuidString: activityID) }
        index.photos.removeAll { UUID(uuidString: $0.id) == UUID(uuidString: photoID) && UUID(uuidString: $0.spaceID) == UUID(uuidString: spaceID) && UUID(uuidString: $0.activityID) == UUID(uuidString: activityID) }
        index.pendingRemoval.append(contentsOf: removed)
        try writeIndex(index, at: root)
        _ = try cleanPendingRemoval(at: root)
        let remaining = try readIndex(at: root).pendingRemoval
        return !remaining.contains {
            UUID(uuidString: $0.id) == UUID(uuidString: photoID) && UUID(uuidString: $0.spaceID) == UUID(uuidString: spaceID) && UUID(uuidString: $0.activityID) == UUID(uuidString: activityID)
        }
    }

    private func cleanPendingRemoval(at root: URL) throws -> Bool {
        var index = try readIndex(at: root)
        var failed: [SharedPhoto] = []
        for item in index.pendingRemoval {
            let path = root.appendingPathComponent(item.fileName)
            do {
                if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
            } catch { failed.append(item) }
        }
        index.pendingRemoval = failed
        try writeIndex(index, at: root)
        return failed.isEmpty
    }

    func refreshPreviews(spaceID: String, activityID: String, rows: [[String: Any]]) async {
        guard !publishing else { return }
        guard let subject = try? await currentSubject(), let root = try? directory(for: subject),
              let index = try? readIndex(at: root) else { return }
        let prefix = "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)"
        // A list response is not proof that a missing photo was revoked. Keep
        // originals until deletion is confirmed so other members can fetch them.
        for photo in index.photos where photo.spaceID == spaceID && photo.activityID == activityID {
            guard !Task.isCancelled else { return }
            guard rows.contains(where: { ($0["id"] as? String) == photo.id && ($0["thumbnailAvailable"] as? Bool) == false }) else { continue }
            let path = root.appendingPathComponent(photo.fileName)
            guard (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) == photo.length,
                  let thumbnail = try? await Task.detached(priority: .utility, operation: { try Self.preview(fromFile: path) }).value else { continue }
            try? await uploadThumbnail(thumbnail, prefix: prefix, photoID: photo.id, revision: photo.sha256)
        }
    }

    func refreshLocations(spaceID: String, activityID: String, rows: [[String: Any]]) async -> Bool {
        guard let store, let subject = try? await currentSubject(), let root = try? directory(for: subject),
              let index = try? readIndex(at: root) else { return false }
        var changed = false
        for photo in index.photos where photo.spaceID == spaceID && photo.activityID == activityID {
            guard !Task.isCancelled else { return changed }
            guard !checkedLocationIDs.contains(photo.id),
                  let row = rows.first(where: { ($0["id"] as? String) == photo.id }),
                  (row["latitude"] as? NSNumber == nil || row["altitudeMeters"] as? NSNumber == nil ||
                   (row["locationName"] as? String ?? "").isEmpty || DearPhotoLocation.coordinateLabel(row["locationName"] as? String ?? "") != nil) else { continue }
            checkedLocationIDs.insert(photo.id)
            guard let local = await localOriginal(photoID: photo.id, spaceID: spaceID, activityID: activityID) else { continue }
            let name = row["locationName"] as? String ?? ""
            let geography = await DearPhotoLocation.geography(at: local, fallbackName: name)
            guard geography.name != name || geography.latitude != nil && row["latitude"] as? NSNumber == nil ||
                  geography.altitudeMeters != nil && row["altitudeMeters"] as? NSNumber == nil else { continue }
            do {
                _ = try await store.call("/api/dear/social/tenants/\(spaceID)/activities/\(activityID)/live/photos/\(photo.id)/location",
                    method: "PATCH", body: ["locationName": String(geography.name.prefix(200)),
                        "latitude": geography.latitude as Any? ?? NSNull(), "longitude": geography.longitude as Any? ?? NSNull(),
                        "altitudeMeters": geography.altitudeMeters as Any? ?? NSNull()])
                changed = true
            } catch { checkedLocationIDs.remove(photo.id) }
        }
        return changed
    }

    func stopRequest(_ id: UUID) async throws {
        guard let store else { throw APIError.message("活动服务不可用。") }
        _ = try await store.call("/api/dear/social/photo-requests/\(id.uuidString)/cancel", method: "POST", body: [:])
        sourceTasks.removeValue(forKey: id.uuidString.lowercased())?.cancel()
        if sourceTasks.isEmpty { store.photoRequestNotice = nil; store.photoTransferProgress = nil }
    }

    func isSourceDevice(_ photo: DearRecord) -> Bool {
        var deviceID = currentDeviceID
        if deviceID == nil, let subjectCache, let root = try? directory(for: subjectCache) {
            deviceID = (try? readIndex(at: root))?.deviceID
        }
        guard let source = UUID(uuidString: photo.text("sourceDeviceId")),
              let deviceID, let current = UUID(uuidString: deviceID) else { return false }
        return source == current
    }

    // A PhotoKit resource must be materialized to a file for AVPlayer/export. This
    // reads local bytes only, never creates a download request or relay upload.
    func localOriginal(photoID: String, spaceID: String, activityID: String, record: DearRecord? = nil) async -> URL? {
        let expected = generation
        guard let id = UUID(uuidString: photoID), let tenant = UUID(uuidString: spaceID),
              let activity = UUID(uuidString: activityID),
              let subject = try? await currentSubject(), expected == generation,
              let root = try? directory(for: subject), let index = try? readIndex(at: root) else { return nil }
        var entry = index.photos.first { UUID(uuidString: $0.id) == id && UUID(uuidString: $0.spaceID) == tenant && UUID(uuidString: $0.activityID) == activity }
        if entry == nil, let record, record.text("sourceSubject") == subject, isSourceDevice(record),
           let length = (record.data["length"] as? NSNumber)?.intValue, length > 0 {
            let sha = record.text("thumbnailRevision")
            if sha.count == 64, sha.allSatisfy({ $0.isHexDigit }) {
                entry = SharedPhoto(id: photoID, spaceID: spaceID, activityID: activityID,
                    fileName: UUID().uuidString + ".original", length: length, sha256: sha,
                    originalFileName: record.text("originalFileName"))
            }
        }
        guard let photo = entry else { return nil }
        let path = root.appendingPathComponent(photo.fileName)
        if (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) == photo.length,
           await verifiedOriginal(path, length: photo.length, sha: photo.sha256, subject: subject),
           expected == generation { return path }
        var permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if permission == .notDetermined { permission = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard permission == .authorized || permission == .limited, expected == generation else { return nil }
        let key = id.uuidString + photo.sha256
        if let task = localReads[key] { let value = await task.value; return expected == generation ? value : nil }
        let type = record?.text("contentType") ?? UTType(filenameExtension: photo.originalFileName.map { ($0 as NSString).pathExtension } ?? path.pathExtension)?.preferredMIMEType ?? "image/jpeg"
        let assetID = photo.assetIdentifier
        // Older shares did not save a Photos ID. Rebuild that local index once
        // automatically; subsequent reads go straight to the saved asset ID.
        let attempt = key + String(describing: permission)
        guard assetID != nil || legacyLibraryAttempts.insert(attempt).inserted else { return nil }
        let task = Task<URL?, Never> {
            let previous = self.legacyRead
            let search = Task.detached(priority: .utility) {
                if assetID == nil { _ = try? await previous?.value; try Task.checkCancellation() }
                if let assetID {
                    return try await MomentLibraryOriginals.locate(assetIdentifier: assetID, length: photo.length, sha: photo.sha256, contentType: type)
                }
                return try await MomentLibraryOriginals.find(length: photo.length, sha: photo.sha256, contentType: type, indexRoot: root) { _, _ in }
            }
            if assetID == nil { self.legacyRead = search }
            do {
                guard let temporary = try await withTaskCancellationHandler(operation: { try await search.value }, onCancel: { search.cancel() }) else { return nil }
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Task.checkCancellation()
                guard expected == self.generation else { return nil }
                let local = root.appendingPathComponent(UUID().uuidString + "." + temporary.pathExtension)
                try FileManager.default.copyItem(at: temporary, to: local)
                var refreshed = try self.readIndex(at: root)
                refreshed.photos.removeAll { UUID(uuidString: $0.id) == id && UUID(uuidString: $0.spaceID) == tenant && UUID(uuidString: $0.activityID) == activity }
                let restoredID = assetID ?? MomentLibraryOriginals.indexedAssetIdentifier(length: photo.length, sha: photo.sha256, indexRoot: root)
                refreshed.photos.append(SharedPhoto(id: photoID, spaceID: spaceID, activityID: activityID,
                    fileName: local.lastPathComponent, length: photo.length, sha256: photo.sha256,
                    assetIdentifier: restoredID, originalFileName: photo.originalFileName))
                do { try self.writeIndex(refreshed, at: root) }
                catch { try? FileManager.default.removeItem(at: local); throw error }
                return local
            } catch { return nil }
        }
        localReads[key] = task
        let result = await task.value
        if expected == generation { localReads.removeValue(forKey: key) }
        return expected == generation ? result : nil
    }

    func availableOriginal(photo: DearRecord, spaceID: String, activityID: String) async -> URL? {
        let expected = generation
        guard let subject = try? await currentSubject(), expected == generation,
              UUID(uuidString: photo.id) != nil, UUID(uuidString: spaceID) != nil, UUID(uuidString: activityID) != nil,
              let length = (photo.data["length"] as? NSNumber)?.intValue, length > 0 else { return nil }
        let sha = photo.text("thumbnailRevision")
        guard sha.count == 64, sha.allSatisfy({ $0.isHexDigit }) else { return nil }
        if let local = await localOriginal(photoID: photo.id, spaceID: spaceID, activityID: activityID, record: photo),
           (try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize) == length,
           await verifiedOriginal(local, length: length, sha: sha, subject: subject), expected == generation { return local }
        let subjectKey = SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DearReceivedPhotos").appendingPathComponent(subjectKey)
        let prefix = photo.id.lowercased() + "-" + sha.lowercased() + "."
        for file in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
            guard file.lastPathComponent.hasPrefix(prefix), file.pathExtension != "part",
                  (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) == length,
                  await verifiedOriginal(file, length: length, sha: sha, subject: subject), expected == generation else { continue }
            return file
        }
        return nil
    }

    func recoverAllMyOriginals(status: @escaping (String) -> Void) async throws -> String {
        guard let store else { throw CancellationError() }
        let subject = try await currentSubject(), expected = generation
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard authorization == .authorized || authorization == .limited else {
            throw APIError.message("需要允许访问保存原件的相册后才能批量匹配。")
        }
        let activities = try DearRecord.list(await store.call("/api/dear/social/activities/joined"))
        var seen = Set<UUID>(), matched = 0, missing = 0, failed = 0, cached = 0
        for activity in activities {
            try Task.checkCancellation()
            guard expected == generation else { throw CancellationError() }
            let tenant = activity.text("sourceTenantId").isEmpty ? activity.text("tenantId") : activity.text("sourceTenantId")
            guard UUID(uuidString: tenant) != nil, UUID(uuidString: activity.id) != nil else { continue }
            let photos = try DearRecord.list(await store.call("/api/dear/social/tenants/\(tenant)/activities/\(activity.id)/live/photos"))
            for photo in photos where photo.text("sourceSubject") == subject {
                guard let id = UUID(uuidString: photo.id), seen.insert(id).inserted else { continue }
                try Task.checkCancellation()
                guard expected == generation else { throw CancellationError() }
                status("已检查 \(seen.count) 张：已匹配 \(matched)，缓存就绪 \(cached)，未找到 \(missing)，失败 \(failed)")
                if photo.flag("serverCached"), await availableOriginal(photo: photo, spaceID: tenant, activityID: activity.id) != nil { cached += 1; continue }
                var request = photo.data
                request["photoId"] = photo.id; request["tenantId"] = tenant; request["activityId"] = activity.id
                request["serverCached"] = false
                request["sha256"] = photo.text("thumbnailRevision"); request["canStop"] = true; request["status"] = "waiting"
                do {
                    if try await restoreOriginal(for: request, allowLibraryScan: true, status: status) { matched += 1 } else { missing += 1 }
                } catch is CancellationError { throw CancellationError() }
                catch { failed += 1 }
            }
        }
        return "检查 \(seen.count) 张：匹配并恢复 \(matched)，缓存已就绪 \(cached)，本机未找到 \(missing)，失败待重试 \(failed)。"
    }

    // Recover only this account's verified bytes, never infer physical ownership
    // from the username or claim an unrelated item from the system photo library.
    func restoreOriginal(for request: [String: Any], selectedFile: URL? = nil, selectedAssetIdentifier: String? = nil, allowLibraryScan: Bool = false, status: ((String) -> Void)? = nil) async throws -> Bool {
        guard request["canStop"] as? Bool == true, request["status"] as? String == "waiting",
              request["serverCached"] as? Bool != true else { return false }
        guard store != nil, let photoID = request["photoId"] as? String, UUID(uuidString: photoID) != nil,
              let spaceID = request["tenantId"] as? String, UUID(uuidString: spaceID) != nil,
              let activityID = request["activityId"] as? String, UUID(uuidString: activityID) != nil,
              let length = (request["length"] as? NSNumber)?.intValue, length > 0,
              let sha = request["sha256"] as? String, sha.count == 64 else { throw APIError.message("原文件请求数据无效。") }
        let expected = generation
        let subject = try await currentSubject(), root = try directory(for: subject)
        if !enabledForSession { await enableExistingDevice() }
        guard let deviceID = currentDeviceID else { throw APIError.message("本机共享设备登记失败，请稍后重试。") }
        let recorded = try readIndex(at: root).photos.first {
            UUID(uuidString: $0.id) == UUID(uuidString: photoID) && UUID(uuidString: $0.spaceID) == UUID(uuidString: spaceID) && UUID(uuidString: $0.activityID) == UUID(uuidString: activityID)
        }
        let recordedURL = recorded.map { root.appendingPathComponent($0.fileName) }
        var candidates = selectedFile.map { [$0] } ?? recordedURL.map { [$0] } ?? []
        if allowLibraryScan && selectedFile == nil {
            candidates += (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        }
        var original: URL?
        for candidate in candidates {
            try Task.checkCancellation()
            guard (try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize) == length else { continue }
            if (try? await hashFile(candidate))?.caseInsensitiveCompare(sha) == .orderedSame { original = candidate; break }
        }
        if original == nil, selectedFile == nil {
            var metadata = request
            metadata["id"] = photoID; metadata["sourceSubject"] = subject
            metadata["sourceDeviceId"] = deviceID; metadata["thumbnailRevision"] = sha
            original = await localOriginal(photoID: photoID, spaceID: spaceID, activityID: activityID, record: DearRecord(data: metadata))
        }
        var libraryOriginal: URL?
        defer { if let libraryOriginal { try? FileManager.default.removeItem(at: libraryOriginal) } }
        let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let assetID = selectedAssetIdentifier ?? recorded?.assetIdentifier
        if original == nil, let assetID, authorization == .authorized || authorization == .limited {
            let type = request["contentType"] as? String ?? ""
            libraryOriginal = try await Task.detached(priority: .utility) {
                try await MomentLibraryOriginals.locate(assetIdentifier: assetID, length: length, sha: sha, contentType: type)
            }.value
            original = libraryOriginal
        }
        if allowLibraryScan, original == nil, selectedFile == nil, authorization == .authorized || authorization == .limited {
            guard librarySearch == nil else { throw APIError.message("正在自动匹配其他原件，请稍后重试。") }
            let type = request["contentType"] as? String ?? ""
            let search = Task.detached(priority: .utility) {
                try await MomentLibraryOriginals.find(length: length, sha: sha, contentType: type, indexRoot: root) { checked, total in
                    await MainActor.run { status?("正在自动匹配相册原件 \(checked)/\(total)…") }
                }
            }
            librarySearch = search
            defer { if expected == generation { librarySearch = nil } }
            libraryOriginal = try await withTaskCancellationHandler { try await search.value } onCancel: { search.cancel() }
            original = libraryOriginal
        }
        guard let original else {
            if selectedFile != nil { throw APIError.message("选择的文件与这张共享照片的原文件不一致，请选择未编辑、未转换的原文件。") }
            return false
        }
        guard expected == generation else { throw CancellationError() }
        let prefix = "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)/native-photos/\(photoID)/relay"
        var upload = try await relayRequest(path: prefix, method: "PUT")
        upload.setValue(deviceID, forHTTPHeaderField: "X-Source-Device")
        upload.setValue(sha, forHTTPHeaderField: "X-Photo-Revision")
        upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        upload.setValue(String(length), forHTTPHeaderField: "Content-Length")
        status?("已匹配原件，正在继续分享…")
        try await RealtimeFileRelay.upload(file: original, request: upload)
        guard expected == generation else { throw CancellationError() }
        let local: URL
        if original.deletingLastPathComponent() == root { local = original }
        else {
            local = root.appendingPathComponent(UUID().uuidString + "." + original.pathExtension)
            do {
                try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: original, to: local) }.value
                try Task.checkCancellation()
                guard expected == generation else { throw CancellationError() }
            } catch { try? FileManager.default.removeItem(at: local); throw error }
        }
        // Reload after asynchronous work so a concurrent share cannot lose its index.
        var index = try readIndex(at: root)
        let restoredAssetID = index.photos.first { UUID(uuidString: $0.id) == UUID(uuidString: photoID) }?.assetIdentifier
        index.photos.removeAll { UUID(uuidString: $0.id) == UUID(uuidString: photoID) }
        index.photos.append(SharedPhoto(id: photoID, spaceID: spaceID, activityID: activityID, fileName: local.lastPathComponent, length: length, sha256: sha, assetIdentifier: assetID ?? restoredAssetID, originalFileName: recorded?.originalFileName ?? request["fileName"] as? String))
        try writeIndex(index, at: root)
        cachedShares.insert(photoID + sha)
        return true
    }

    func downloadOriginal(photoID: String, spaceID: String, activityID: String, record: DearRecord? = nil,
                          status: ((String) -> Void)? = nil, progress: ((Double) -> Void)? = nil) async throws -> URL {
        guard UUID(uuidString: photoID) != nil, UUID(uuidString: spaceID) != nil,
              UUID(uuidString: activityID) != nil else { throw APIError.message("照片标识无效。") }
        if let record, let local = await availableOriginal(photo: record, spaceID: spaceID, activityID: activityID) { progress?(1); return local }
        if record == nil, let local = await localOriginal(photoID: photoID, spaceID: spaceID, activityID: activityID) { progress?(1); return local }
        if let record, isSourceDevice(record) {
            throw APIError.message("这是本机分享的文件。请允许访问对应相册原件；若原件仅在 iCloud，请先在系统照片中打开使其保留在本机。无需向自己请求下载或手动匹配。")
        }
        guard let store, store.identity.isAuthenticated else { throw APIError.message("请先登录用户中心。") }
        guard !downloads.contains(photoID) else { throw APIError.message("该原文件正在接收，请稍候。") }
        downloads.insert(photoID)
        defer { downloads.remove(photoID) }
        let value = try await store.call("/api/dear/social/tenants/\(spaceID)/activities/\(activityID)/photo-requests",
                                         method: "POST", body: ["photoId": photoID, "operationId": UUID().uuidString, "transport": "connect-datachannel-v1"])
        guard let request = value as? [String: Any], let id = request["id"] as? String,
              UUID(uuidString: id) != nil, request["transport"] as? String == "connect-datachannel-v1", let length = (request["length"] as? NSNumber)?.intValue,
              let contentType = request["contentType"] as? String,
              length > 0, length <= (contentType.hasPrefix("video/") ? 500 : 50) * 1024 * 1024,
              let sha = request["sha256"] as? String,
              sha.count == 64, sha.allSatisfy({ $0.isHexDigit }) else {
            throw APIError.message("原图请求回执无效。")
        }
        let subject = try await currentSubject()
        let subjectKey = SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DearReceivedPhotos", isDirectory: true)
            .appendingPathComponent(subjectKey, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for old in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            guard UUID(uuidString: String(old.lastPathComponent.prefix(36))) != nil,
                  let modified = try? old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < Date().addingTimeInterval(-7 * 24 * 60 * 60) else { continue }
            try? FileManager.default.removeItem(at: old)
        }
        let suffix: String
        switch contentType {
        case "image/png": suffix = ".png"
        case "image/webp": suffix = ".webp"
        case "image/heic": suffix = ".heic"
        case "video/mp4": suffix = ".mp4"
        case "video/quicktime": suffix = ".mov"
        default: suffix = ".jpg"
        }
        let key = "\(photoID.lowercased())-\(sha.lowercased())"
        let partialURL = root.appendingPathComponent(key + ".part")
        let finalURL = root.appendingPathComponent(key + suffix)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            if (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) == length,
               (try? await hashFile(finalURL))?.caseInsensitiveCompare(sha) == .orderedSame {
                _ = try? await store.call("/api/dear/social/photo-requests/\(id)/cancel", method: "POST", body: [:])
                progress?(1)
                return finalURL
            }
            try? FileManager.default.removeItem(at: finalURL)
        }
        var current = (try await store.call("/api/dear/social/photo-requests/\(id)") as? [String: Any]) ?? request
        let expectedGeneration = generation
        while current["status"] as? String == "pending_approval" {
            status?("等待分享者打开消息同意…")
            try Task.checkCancellation()
            guard expectedGeneration == generation else { throw CancellationError() }
            guard let expiry = (current["expiresAt"] as? NSNumber)?.doubleValue, Date().timeIntervalSince1970 * 1000 < expiry else {
                throw APIError.message("等待同意已超时，请重新发起下载请求。")
            }
            try await Task.sleep(for: .seconds(2))
            guard let next = try await store.call("/api/dear/social/photo-requests/\(id)") as? [String: Any] else { throw APIError.message("请求状态读取失败。") }
            current = next
        }
        if let state = current["status"] as? String, ["cancelled", "expired", "revoked", "unavailable", "failed"].contains(state) {
            throw APIError.message("本次分享已停止、已过期或不可用，请重新发起下载请求。")
        }
        let manifest = try connectManifest(current)
        if current["serverCached"] as? Bool == true {
            status?("正在从服务器缓存接收原文件…")
            let relayRequest = try await relayRequest(path: "/api/dear/social/photo-requests/\(id)/relay")
            try await RealtimeFileRelay.receive(to: partialURL, manifest: manifest, request: relayRequest) { value in await MainActor.run { progress?(value) } }
            guard expectedGeneration == generation else { try? FileManager.default.removeItem(at: partialURL); throw CancellationError() }
            _ = try await store.call("/api/dear/social/photo-requests/\(id)/complete", method: "POST", body: [:])
            try FileManager.default.moveItem(at: partialURL, to: finalURL); progress?(1); return finalURL
        }
        status?("已同意，正在连接原件设备…")

        let transfer = RealtimeFileTransfer(), transferID = UUID()
        transfers[transferID] = transfer
        defer { transfers.removeValue(forKey: transferID) }
        let requests = try await connectRequests(requestID: id, role: "receiver")
        guard expectedGeneration == generation else { throw CancellationError() }
        // A source may finish caching while Connect is still waiting for a peer.
        // Stop that wait promptly so the existing fallback can fetch verified bytes.
        let cacheWatch = Task {
            while !Task.isCancelled, expectedGeneration == generation {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                if let latest = try? await store.call("/api/dear/social/photo-requests/\(id)") as? [String: Any],
                   latest["serverCached"] as? Bool == true {
                    await transfer.cancel(); return
                }
            }
        }
        defer { cacheWatch.cancel() }
        do {
            try await withTaskCancellationHandler {
                try await transfer.receive(partial: partialURL, manifest: manifest, requests: requests) { value in
                    await MainActor.run { progress?(value) }
                }
            } onCancel: { Task { await transfer.cancel() } }
        } catch {
            try Task.checkCancellation()
            let latest = try? await store.call("/api/dear/social/photo-requests/\(id)") as? [String: Any]
            if let state = latest?["status"] as? String, ["cancelled", "expired", "revoked", "unavailable"].contains(state) {
                throw APIError.message("本次分享已停止、已过期或不可用，请重新发起下载请求。")
            }
            guard expectedGeneration == generation else { throw CancellationError() }
            if latest?["serverCached"] as? Bool == true {
                status?("设备直传中断，正在从服务器缓存接收…")
                let cached = try await relayRequest(path: "/api/dear/social/photo-requests/\(id)/relay")
                try await RealtimeFileRelay.receive(to: partialURL, manifest: manifest, request: cached) { value in await MainActor.run { progress?(value) } }
            } else { throw error }
        }
        // Connect returns only after peer acknowledgement and durable SHA validation.
        _ = try await store.call("/api/dear/social/photo-requests/\(id)/complete", method: "POST", body: [:])
        try FileManager.default.moveItem(at: partialURL, to: finalURL)
        originalsRevision = UUID()
        progress?(1)
        return finalURL
    }

    private func connectManifest(_ row: [String: Any]) throws -> RealtimeFileManifest {
        guard row["transport"] as? String == "connect-datachannel-v1",
              let length = (row["length"] as? NSNumber)?.intValue, let sha = row["sha256"] as? String,
              let expiry = (row["expiresAt"] as? NSNumber)?.doubleValue else { throw APIError.message("Connect 传输回执无效。") }
        return try RealtimeFileManifest(length: length, sha256: sha, expiresAt: Date(timeIntervalSince1970: expiry / 1000))
    }

    private func connectRequests(requestID: String, role: String) async throws -> RealtimeFileTransfer.Requests {
        guard let store, let config = try await store.call("/api/dear/social/connect-configuration") as? [String: Any],
              config["transport"] as? String == "connect-datachannel-v1", let text = config["origin"] as? String,
              let origin = URL(string: text), origin.scheme == "https", origin.host != nil,
              origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil,
              origin.path.isEmpty || origin.path == "/",
              config["apiPathPrefix"] as? String == "/api/dear/social" else { throw APIError.message("Connect 服务尚未配置。") }
        return { [weak store] in
            try await MainActor.run { guard store?.identity.isAuthenticated == true else { throw CancellationError() } }
            guard let token = try await store?.identity.validAccessToken() else { throw CancellationError() }
            func request(_ action: String) -> URLRequest {
                var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
                components.path = "/api/dear/social/photo-requests/\(requestID)/connect/\(action)"
                components.queryItems = [URLQueryItem(name: "role", value: role)]
                var request = URLRequest(url: components.url!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue(text, forHTTPHeaderField: "Origin")
                request.timeoutInterval = 30
                return request
            }
            return (request("ice"), request("signal"))
        }
    }

    private func relayRequest(path: String, method: String = "GET") async throws -> URLRequest {
        guard let store else { throw CancellationError() }
        guard let token = try await store.identity.validAccessToken() else { throw APIError.message("请重新登录用户中心。") }
        var request = URLRequest(url: URL(string: path, relativeTo: base)!.absoluteURL)
        request.httpMethod = method; request.timeoutInterval = 30 * 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func startCaching(index: Index, root: URL) {
        guard cacheTask == nil, let deviceID = index.deviceID,
              let photo = index.photos.reversed().first(where: { !cachedShares.contains($0.id + $0.sha256) && (cacheRetries[$0.id] ?? .distantPast) < Date() }) else { return }
        let expected = generation
        cacheTask = Task { [weak self] in
            guard let self else { return }
            defer { if expected == generation { cacheTask = nil } }
            let prefix = "/api/dear/social/tenants/\(photo.spaceID)/activities/\(photo.activityID)/native-photos/\(photo.id)/relay"
            do {
                let state = try await store?.call(prefix) as? [String: Any]
                if state?["cached"] as? Bool != true {
                    let path = root.appendingPathComponent(photo.fileName)
                    guard (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) == photo.length else { cachedShares.insert(photo.id + photo.sha256); return }
                    var request = try await relayRequest(path: prefix, method: "PUT")
                    request.setValue(deviceID, forHTTPHeaderField: "X-Source-Device")
                    request.setValue(photo.sha256, forHTTPHeaderField: "X-Photo-Revision")
                    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                    request.setValue(String(photo.length), forHTTPHeaderField: "Content-Length")
                    try Task.checkCancellation()
                    guard expected == generation else { throw CancellationError() }
                    try await RealtimeFileRelay.upload(file: path, request: request)
                }
                guard expected == generation else { return }
                cachedShares.insert(photo.id + photo.sha256)
            } catch { if expected == generation { cacheRetries[photo.id] = Date().addingTimeInterval(60) } }
        }
    }

    private func currentSubject() async throws -> String {
        let expected = generation
        if let subjectCache, store?.identity.isAuthenticated == true { return subjectCache }
        guard let store, store.identity.isAuthenticated,
              let me = try await store.call("/api/dear/social/me") as? [String: Any],
              let subject = me["subject"] as? String, !subject.isEmpty else {
            throw APIError.message("请先在 iPhone 上登录 Linko Moment。")
        }
        guard expected == generation else { throw CancellationError() }
        subjectCache = subject
        return subject
    }

    private func directory(for subject: String) throws -> URL {
        let key = SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DearSharedPhotos", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func readIndex(at root: URL) throws -> Index {
        let path = root.appendingPathComponent("index.json")
        return FileManager.default.fileExists(atPath: path.path)
            ? try JSONDecoder().decode(Index.self, from: Data(contentsOf: path)) : Index()
    }

    private func writeIndex(_ index: Index, at root: URL) throws {
        try JSONEncoder().encode(index).write(to: root.appendingPathComponent("index.json"),
                                              options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        originalsRevision = UUID()
    }

    private func verifiedOriginal(_ url: URL, length: Int, sha: String, subject: String) async -> Bool {
        guard let root = try? directory(for: subject) else { return false }
        let verifier: OriginalFileVerifier
        if let saved = fileVerifiers[subject] { verifier = saved }
        else { verifier = OriginalFileVerifier(directory: root); fileVerifiers[subject] = verifier }
        return await verifier.verify(url, length: length, sha256: sha)
    }

    private func hashFile(_ url: URL) async throws -> String {
        try await Task.detached(priority: .utility) { try Self.fileSHA256(url) }.value
    }

    private nonisolated static func fileSHA256(_ url: URL, limit: Int? = nil) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        var remaining = limit
        while remaining != 0, let chunk = try handle.read(upToCount: min(remaining ?? 1024 * 1024, 1024 * 1024)), !chunk.isEmpty {
            digest.update(data: chunk)
            if remaining != nil { remaining! -= chunk.count }
        }
        if remaining != nil && remaining != 0 { throw APIError.message("续传原文件已发生变化。") }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func preview(fromFile fileURL: URL) throws -> Data {
        let image: CGImage?
        if ["mp4", "mov"].contains(fileURL.pathExtension.lowercased()) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fileURL))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 360, height: 360)
            image = try? generator.copyCGImage(at: .zero, actualTime: nil)
        } else if let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 360,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        } else { image = nil }
        guard let image else { throw APIError.message("无法处理照片预览。") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw APIError.message("照片预览无法压缩。")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.65] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 256 * 1024 else { throw APIError.message("照片预览无法压缩。") }
        return output as Data
    }

    private func uploadThumbnail(_ data: Data, prefix: String, photoID: String, revision: String) async throws {
        guard let store, let token = store.identity.accessToken else { throw APIError.message("登录已过期。") }
        var request = URLRequest(url: URL(string: prefix + "/native-photos/\(photoID)/thumbnail", relativeTo: base)!.absoluteURL)
        request.httpMethod = "PUT"; request.httpBody = data; request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue(revision, forHTTPHeaderField: "X-Photo-Revision")
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.message("预览上传失败。") }
    }

    func serveCurrentRequests() async {
        start()
        if !enabledForSession { await enableExistingDevice() }
        await poll()
    }

    private func poll() async {
        guard !Task.isCancelled, let store, store.identity.isAuthenticated,
              let subject = try? await currentSubject(), let root = try? directory(for: subject),
              let index = try? readIndex(at: root), let deviceID = index.deviceID else { return }
        guard !polling else { return }
        polling = true
        defer { polling = false }
        if !index.pendingRemoval.isEmpty { _ = try? cleanPendingRemoval(at: root) }
        startCaching(index: index, root: root)
        do {
            let rows = try await store.call("/api/dear/social/photo-devices/\(deviceID)/requests") as? [[String: Any]] ?? []
            if rows.isEmpty && sourceTasks.isEmpty { store.photoRequestNotice = nil; store.photoTransferProgress = nil; return }
            store.photoRequestNotice = "有活动成员正在请求原图，请保持 App 打开直到传输完成。"
            store.photoTransferProgress = nil

            for request in rows {
                guard !Task.isCancelled else { return }
                let requestID = request["id"] as? String ?? ""
                guard UUID(uuidString: requestID) != nil, request["transport"] as? String == "connect-datachannel-v1",
                      sourceTasks[requestID] == nil, sourceTasks.count < 2 else { continue }
                let photoID = request["photoId"] as? String ?? ""
                guard request["sourceSubject"] as? String == subject,
                      UUID(uuidString: request["deviceId"] as? String ?? "") == UUID(uuidString: deviceID) else { continue }
                var metadata = request
                metadata["id"] = photoID; metadata["sourceDeviceId"] = deviceID
                metadata["thumbnailRevision"] = request["sha256"]
                guard let tenant = request["tenantId"] as? String, let activity = request["activityId"] as? String,
                      let path = await availableOriginal(photo: DearRecord(data: metadata), spaceID: tenant, activityID: activity) else {
                    store.photoRequestNotice = "暂时无法读取本机原件，请检查相册访问权限及原件是否保留在本机。"
                    continue
                }
                let expectedGeneration = generation
                sourceTasks[requestID] = Task { [weak self] in
                    guard let self else { return }
                    do { try await self.sendOriginal(at: path, request: request, requestID: requestID) }
                    catch { /* Next authorized poll can resume the same request. */ }
                    guard expectedGeneration == self.generation else { return }
                    self.sourceTasks.removeValue(forKey: requestID)
                    if self.sourceTasks.isEmpty { store.photoRequestNotice = nil; store.photoTransferProgress = nil }
                }
            }
        } catch { }
    }

    private func sendOriginal(at url: URL, request: [String: Any], requestID: String) async throws {
        guard let store, store.identity.isAuthenticated else { throw APIError.message("登录已过期。") }
        let expectedGeneration = generation
        let manifest = try connectManifest(request)
        let requests = try await connectRequests(requestID: requestID, role: "source")
        guard expectedGeneration == generation else { throw CancellationError() }
        let transfer = RealtimeFileTransfer(), id = UUID()
        transfers[id] = transfer
        defer { transfers.removeValue(forKey: id) }
        try await withTaskCancellationHandler {
            try await transfer.send(file: url, manifest: manifest, requests: requests, started: {
                _ = try await store.call("/api/dear/social/photo-requests/\(requestID)/begin", method: "POST", body: [:])
            }, commit: {
                _ = try await store.call("/api/dear/social/photo-requests/\(requestID)/confirm", method: "POST", body: [:])
            }, progress: { value in
                await MainActor.run { store.photoTransferProgress = value }
            })
        } onCancel: { Task { await transfer.cancel() } }
    }

}


@MainActor final class MomentNotifications: ObservableObject {
    weak var store: FamilyStore?
    @Published var items: [ApplicationNotification] = []
    @Published var unreadCount = 0
    @Published var error = ""
    @Published var pushRegistrationError = ""
    @Published var notificationStatus = "正在读取系统通知状态…"
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var enabling = false
    @Published var registering = false
    @Published var editingInbox = false
    @Published var showingInbox = false
    @Published var selectedMessageID: Int64?
    private var generation = UUID()
    private var inboxRequestID = UUID()
    private var client: NotificationClient?
    private var authority: URL?
    private var applicationKey: String?
    private var registrationTail: Task<Void, Never>?
    private var deviceToken: String?
    private var registrationTimeout: Task<Void, Never>?
    private var registrationAttempt = UUID()
    private let installationID: String = {
        let key = "moment.notifications.installation"
        if let value = UserDefaults.standard.string(forKey: key) { return value }
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }()
    private var channel: String { Bundle.main.bundleIdentifier == "net.impx.happylife.parent" ? "app-store-legacy" : "app-store-successor" }
    private func configuredClient() async throws -> NotificationClient {
        if let client { return client }
        guard let store else { throw APIError.message("消息服务不可用。") }
        let expected = generation
        guard let config = try await store.call("/auth/native/configuration") as? [String: Any],
              let text = config["authority"] as? String, let url = URL(string: text), url.scheme == "https",
              url.host != nil, url.user == nil, url.password == nil, url.path.isEmpty, url.query == nil, url.fragment == nil,
              let key = config["clientId"] as? String, key == "happylife.ai", expected == generation else {
            throw APIError.message("通知应用配置无效。")
        }
        let result = NotificationClient(authority: url, applicationKey: key) { [weak self] in
            guard let self, self.generation == expected, let token = try await self.store?.identity.validAccessToken(), !token.isEmpty else { throw CancellationError() }
            guard self.generation == expected else { throw CancellationError() }
            return token
        }
        authority = url; applicationKey = key; client = result
        return result
    }
    func reload() async {
        let expected = generation, requestID = UUID()
        inboxRequestID = requestID
        do {
            let inbox = try await configuredClient().list()
            guard expected == generation, requestID == inboxRequestID else { return }
            items = inbox.items; unreadCount = inbox.unreadCount; error = ""
        } catch is CancellationError { } catch {
            if expected == generation, requestID == inboxRequestID { self.error = "消息通知暂时无法读取，请重试。" }
        }
    }
    var enableButtonTitle: String {
        if enabling { return "正在请求通知权限…" }
        if registering { return "正在登记系统通知…" }
        switch authorizationStatus {
        case .denied: return "前往系统设置开启通知"
        case .authorized: return "重新登记系统通知"
        default: return "启用系统通知"
        }
    }
    func resume() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            if !registering { beginRegistration() }
        case .denied: notificationStatus = "系统通知已关闭，请到系统设置中允许通知。"
        default: notificationStatus = "尚未启用系统通知，下载请求仍可在消息列表查看。"
        }
        await reload()
    }
    func openSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
    }
    func registrationFailed() {
        registrationTimeout?.cancel(); registering = false
        notificationStatus = "系统推送登记失败。"
        pushRegistrationError = "暂时无法登记系统通知，请检查网络后重试。App 内请求消息仍可查看。"
    }
    private func beginRegistration() {
        guard !registering else { return }
        registering = true; pushRegistrationError = ""
        notificationStatus = "系统已允许通知，正在登记到用户中心…"
        let expected = generation, attempt = UUID()
        registrationAttempt = attempt
        registrationTimeout?.cancel()
        registrationTimeout = Task {
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard expected == generation, attempt == registrationAttempt, registering else { return }
            registering = false
            notificationStatus = "系统已授权，但推送登记尚未完成。"
            pushRegistrationError = "通知登记超时，请检查网络后点击重新登记。"
        }
        // Reuse the last OS token when iOS does not issue a fresh callback.
        if let deviceToken { updatePushToken(deviceToken) }
        UIApplication.shared.registerForRemoteNotifications()
    }
    func enable() async {
        guard !enabling, !registering else { return }
        enabling = true; pushRegistrationError = ""
        defer { enabling = false }
        let expected = generation
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard expected == generation else { return }
        authorizationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .denied {
            notificationStatus = "系统通知已关闭，请在打开的系统设置中允许通知。"
            openSettings()
            return
        }
        do {
            if settings.authorizationStatus != .authorized && settings.authorizationStatus != .ephemeral {
                notificationStatus = "正在请求系统通知权限…"
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                guard expected == generation else { return }
                authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                guard allowed else {
                    notificationStatus = "未允许系统通知；可再次点击按钮前往系统设置开启。"
                    return
                }
            }
            beginRegistration()
        } catch {
            if expected == generation {
                notificationStatus = "无法开启系统通知。"
                pushRegistrationError = "请检查系统设置后重试。"
            }
        }
    }
    func updatePushToken(_ token: String) {
        deviceToken = token
        let expected = generation, previous = registrationTail
        registrationTail = Task {
            await previous?.value
            do {
                guard expected == generation, let store, store.identity.isAuthenticated else { return }
                _ = try await configuredClient()
                guard let authority, let applicationKey, let access = try await store.identity.validAccessToken(), expected == generation else { return }
                let fixed = NotificationClient(authority: authority, applicationKey: applicationKey, accessToken: { access })
                #if DEBUG
                let environment = "sandbox"
                #else
                let environment = "production"
                #endif
                try await fixed.registerAppleDevice(installationID: installationID, token: token, environment: environment, channel: channel)
                if expected != generation { try? await fixed.unregisterDevice(installationID: installationID) }
                else {
                    registrationTimeout?.cancel(); registering = false; pushRegistrationError = ""
                    notificationStatus = "系统通知已允许，用户中心推送设备登记成功。"
                }
            } catch {
                if expected == generation {
                    registrationTimeout?.cancel(); registering = false
                    notificationStatus = "系统已授权，但用户中心推送登记未完成。"
                    self.pushRegistrationError = "请检查网络后点击重新登记；请求消息仍可在此查看。"
                }
            }
        }
    }
    func markRead(_ item: ApplicationNotification) async {
        let expected = generation
        do {
            try await configuredClient().markRead(item.id)
            if expected == generation { await reload() }
        } catch { if expected == generation { self.error = "标记已读失败，请重试。" } }
    }
    func markAllRead() async {
        guard !editingInbox else { return }
        let expected = generation; editingInbox = true
        defer { if expected == generation { editingInbox = false } }
        do { try await configuredClient().markAllRead(); if expected == generation { await reload() } }
        catch { if expected == generation { self.error = "全部已读未完成，请重试。" } }
    }
    func deleteAll() async {
        guard !editingInbox else { return }
        let expected = generation; editingInbox = true
        defer { if expected == generation { editingInbox = false } }
        do {
            try await configuredClient().deleteAll()
            if expected == generation { selectedMessageID = nil; await reload() }
        } catch { if expected == generation { self.error = "全部删除未完成，请重试。" } }
    }
    func open(messageID: Int64? = nil) {
        selectedMessageID = messageID; showingInbox = true
        guard store?.identity.isAuthenticated == true else { return }
        Task { await reload(); await store?.photoSource.serveCurrentRequests() }
    }
    func reset(token: String?) {
        let oldAuthority = authority, oldKey = applicationKey, previous = registrationTail
        registrationTimeout?.cancel(); registrationTimeout = nil; registrationAttempt = UUID()
        registering = false; enabling = false; notificationStatus = "请登录后启用系统通知。"
        generation = UUID(); client = nil; authority = nil; applicationKey = nil
        items = []; unreadCount = 0; editingInbox = false; showingInbox = false; selectedMessageID = nil; error = ""; pushRegistrationError = ""; inboxRequestID = UUID()
        registrationTail = Task {
            await previous?.value
            if let token, let oldAuthority, let oldKey {
                try? await NotificationClient(authority: oldAuthority, applicationKey: oldKey, accessToken: { token }).unregisterDevice(installationID: installationID)
            }
        }
    }
}

// PhotoKit work stays on the utility executor. Only exact matches leave the
// authorized library; scanning never downloads iCloud originals or edits assets.
private enum MomentLibraryOriginals {
    private final class Read: @unchecked Sendable {
        private let lock = NSLock()
        private var requestID: PHAssetResourceDataRequestID?
        private var cancelled = false
        private var fingerprint: OriginalResourceFingerprint
        private var output: FileHandle?
        init(limit: Int, outputURL: URL?) throws {
            fingerprint = OriginalResourceFingerprint(limit: limit)
            if let outputURL {
                guard FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw APIError.message("无法暂存匹配原件。") }
                output = try FileHandle(forWritingTo: outputURL)
            }
        }
        func install(_ id: PHAssetResourceDataRequestID) {
            lock.lock(); requestID = id; let stop = cancelled; lock.unlock()
            if stop { PHAssetResourceManager.default().cancelDataRequest(id) }
        }
        func cancel() {
            lock.lock(); cancelled = true; let id = requestID; lock.unlock()
            if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
        }
        func consume(_ data: Data) {
            lock.lock(); let stop = cancelled; lock.unlock()
            guard !stop else { return }
            // PhotoKit delivers data and completion on the same serial queue.
            guard fingerprint.append(data) else { cancel(); return }
            do { try output?.write(contentsOf: data) } catch { cancel() }
        }
        func finish(_ error: Error?) -> OriginalResourceDigest? {
            lock.lock(); let stop = cancelled; lock.unlock()
            defer { try? output?.close(); output = nil }
            guard error == nil, !stop else { return nil }
            do { try output?.synchronize() } catch { return nil }
            return fingerprint.finish()
        }
    }
    private static func read(_ resource: PHAssetResource, limit: Int, outputURL: URL? = nil) async throws -> OriginalResourceDigest? {
        try Task.checkCancellation()
        let read = try Read(limit: limit, outputURL: outputURL)
        let value: OriginalResourceDigest? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = false
                let id = PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { data in
                    read.consume(data)
                }, completionHandler: { error in continuation.resume(returning: read.finish(error)) })
                read.install(id)
            }
        } onCancel: { read.cancel() }
        try Task.checkCancellation()
        return value
    }
    static func locate(assetIdentifier: String, length: Int, sha: String, contentType: String) async throws -> URL? {
        let permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard permission == .authorized || permission == .limited else { return nil }
        guard let expectedType = UTType(mimeType: contentType),
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject else { return nil }
        for resource in PHAssetResource.assetResources(for: asset) where resource.type != .adjustmentData && UTType(resource.uniformTypeIdentifier)?.conforms(to: expectedType) == true {
            try Task.checkCancellation()
            let ext = expectedType.preferredFilenameExtension ?? "data"
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("MomentLibraryMatch-" + UUID().uuidString + "." + ext)
            do {
                if let digest = try await read(resource, limit: length, outputURL: copy), digest.matches(length: length, sha256: sha) { return copy }
                try? FileManager.default.removeItem(at: copy)
            } catch { try? FileManager.default.removeItem(at: copy); throw error }
        }
        return nil
    }

    static func indexedAssetIdentifier(length: Int, sha: String, indexRoot: URL) -> String? {
        let path = indexRoot.appendingPathComponent("library-fingerprints.json")
        guard let data = try? Data(contentsOf: path),
              let fingerprints = try? JSONDecoder().decode([String: OriginalResourceDigest].self, from: data) else { return nil }
        return fingerprints.first { $0.value.matches(length: length, sha256: sha) }?.key.components(separatedBy: "|").first
    }

    static func find(length: Int, sha: String, contentType: String, indexRoot: URL,
                     progress: @escaping (Int, Int) async -> Void) async throws -> URL? {
        let permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard permission == .authorized || permission == .limited, let expectedType = UTType(mimeType: contentType) else { return nil }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", contentType.hasPrefix("video/") ? PHAssetMediaType.video.rawValue : PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: options)
        let indexURL = indexRoot.appendingPathComponent("library-fingerprints.json")
        var fingerprints = (try? JSONDecoder().decode([String: OriginalResourceDigest].self, from: Data(contentsOf: indexURL))) ?? [:]
        if fingerprints.count > 20000 { fingerprints.removeAll() }
        var changed = false
        func saveIndex() {
            if changed, let bytes = try? JSONEncoder().encode(fingerprints) {
                try? bytes.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        defer { saveIndex() }
        await progress(0, assets.count)
        for position in 0..<assets.count {
            try Task.checkCancellation()
            let asset = assets.object(at: position)
            // A limited grant only enumerates the assets the user allowed.
            let resources = PHAssetResource.assetResources(for: asset).filter { resource in
                resource.type != .adjustmentData && UTType(resource.uniformTypeIdentifier)?.conforms(to: expectedType) == true
            }
            for resource in resources {
                try Task.checkCancellation()
                let key = asset.localIdentifier + "|" + String(asset.modificationDate?.timeIntervalSince1970 ?? 0) + "|" + String(resource.type.rawValue) + "|" + resource.originalFilename
                let digest: OriginalResourceDigest?
                if let saved = fingerprints[key] { digest = saved }
                else {
                    digest = try await read(resource, limit: length)
                    if let digest, fingerprints.count < 20000 { fingerprints[key] = digest; changed = true }
                }
                guard digest?.matches(length: length, sha256: sha) == true else { continue }
                let ext = expectedType.preferredFilenameExtension ?? (contentType.hasPrefix("video/") ? "mov" : "jpg")
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("MomentLibraryMatch-" + UUID().uuidString + "." + ext)
                do {
                    guard let verified = try await read(resource, limit: length, outputURL: copy), verified.matches(length: length, sha256: sha) else {
                        try? FileManager.default.removeItem(at: copy); fingerprints.removeValue(forKey: key); changed = true; continue
                    }
                    try Task.checkCancellation()
                    return copy
                } catch { try? FileManager.default.removeItem(at: copy); throw error }
            }
            if position % 25 == 0 || position + 1 == assets.count { await progress(position + 1, assets.count) }
            if position % 100 == 0 { saveIndex() }
        }
        return nil
    }
}
