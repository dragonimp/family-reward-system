import CryptoKit
import Foundation
import UIKit
import UserNotifications
import AVFoundation

// Linko Social keeps original media bytes on the source device. This adapter
// stores selected photos and videos on the iPhone and serves verified requests.
@MainActor final class DearPhotoSource {
    private struct SharedPhoto: Codable {
        let id: String
        let spaceID: String
        let activityID: String
        let fileName: String
        let length: Int
        let sha256: String
    }
    private struct Index: Codable {
        var deviceID: String?
        var photos: [SharedPhoto] = []
    }

    weak var store: FamilyStore?
    private var pump: Task<Void, Never>?
    private var subjectCache: String?
    private var enabledForSession = false
    private var publishing = false
    private var pushToken: String?
    private let session = URLSession(configuration: .ephemeral)
    private let base = URL(string: "https://happylife.ai.xmkurt.com")!

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

    func stop() { pump?.cancel(); pump = nil; enabledForSession = false }
    func reset() { stop(); subjectCache = nil; pushToken = nil }

    func updatePushToken(_ token: String) async {
        guard !token.isEmpty, token.allSatisfy(\.isHexDigit) else { return }
        pushToken = token
        guard let store, let subject = try? await currentSubject(), let root = try? directory(for: subject),
              let deviceID = (try? readIndex(at: root))?.deviceID else { return }
        _ = try? await store.call("/api/dear/social/photo-devices", method: "POST",
                                  body: ["id": deviceID, "pushToken": token])
    }

    private func enableNotificationsIfNeeded() async -> Bool {
        guard UIApplication.shared.applicationState == .active else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let updated = await center.notificationSettings()
        guard updated.authorizationStatus == .authorized || updated.authorizationStatus == .provisional else { return false }
        UIApplication.shared.registerForRemoteNotifications()
        return true
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
        guard let deviceID = index.deviceID else { enabledForSession = true; return }
        do {
            var body: [String: Any] = ["id": deviceID]
            if let pushToken { body["pushToken"] = pushToken }
            _ = try await store.call("/api/dear/social/photo-devices", method: "POST", body: body)
            enabledForSession = true
            if !index.photos.isEmpty { _ = await enableNotificationsIfNeeded() }
        } catch { }
    }

    func publish(_ imageData: Data, spaceID: String, activityID: String, name: String) async throws {
        guard imageData.count > 0, imageData.count <= 50 * 1024 * 1024,
              UIImage(data: imageData) != nil else { throw APIError.message("照片文件无效或超过 50 MB。") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try imageData.write(to: temporary, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await publishMedia(at: temporary, contentType: "image/jpeg", spaceID: spaceID, activityID: activityID, name: name)
    }

    func publishVideo(at url: URL, spaceID: String, activityID: String) async throws {
        let length = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...500 * 1024 * 1024).contains(length) else { throw APIError.message("视频必须在 500 MB 以内。") }
        let type = url.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"
        let name = type == "video/mp4" ? "iPhone视频.mp4" : "iPhone视频.mov"
        try await publishMedia(at: url, contentType: type, spaceID: spaceID, activityID: activityID, name: name)
    }

    private func publishMedia(at sourceURL: URL, contentType: String, spaceID: String, activityID: String, name: String) async throws {
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
        var deviceBody: [String: Any] = ["id": index.deviceID as Any? ?? NSNull()]
        if let pushToken { deviceBody["pushToken"] = pushToken }
        let device = try await store.call("/api/dear/social/photo-devices", method: "POST",
                                          body: deviceBody) as? [String: Any]
        guard let deviceID = device?["id"] as? String, UUID(uuidString: deviceID) != nil else {
            throw APIError.message("照片分享设备登记失败。")
        }
        index.deviceID = deviceID
        try writeIndex(index, at: root)
        enabledForSession = true

        let localName = UUID().uuidString + (contentType == "video/mp4" ? ".mp4" : contentType == "video/quicktime" ? ".mov" : ".jpg")
        let localURL = root.appendingPathComponent(localName)
        do {
            do { try FileManager.default.moveItem(at: sourceURL, to: localURL) }
            catch { try FileManager.default.copyItem(at: sourceURL, to: localURL) }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: localURL.path)
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            throw error
        }
        let displayName = String(name.prefix(200)).isEmpty ? "共享媒体.jpg" : String(name.prefix(200))
        let prefix = "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)"
        var publishedID: String?
        do {
            let sha = try await hashFile(localURL)
            let thumbnail = try preview(fromFile: localURL)
            let response = try await store.call(prefix + "/native-photos", method: "POST", body: [
                "deviceId": deviceID, "fileName": displayName, "contentType": contentType,
                "length": length, "sha256": sha]) as? [String: Any]
            guard let photoID = response?["id"] as? String, UUID(uuidString: photoID) != nil else {
                throw APIError.message("照片登记回执无效。")
            }
            publishedID = photoID
            index.photos.append(SharedPhoto(id: photoID, spaceID: spaceID, activityID: activityID,
                                            fileName: localName, length: length, sha256: sha))
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

    func revoke(photoID: String, spaceID: String, activityID: String) async throws {
        guard UUID(uuidString: photoID) != nil, UUID(uuidString: spaceID) != nil,
              UUID(uuidString: activityID) != nil, let store else { throw APIError.message("照片或视频标识无效。") }
        let prefix = "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)"
        _ = try await store.call(prefix + "/live/photos/\(photoID)", method: "DELETE")
        guard let subject = try? await currentSubject(), let root = try? directory(for: subject) else { return }
        var index = try readIndex(at: root)
        let removed = index.photos.filter { $0.id == photoID && $0.spaceID == spaceID && $0.activityID == activityID }
        index.photos.removeAll { $0.id == photoID && $0.spaceID == spaceID && $0.activityID == activityID }
        try writeIndex(index, at: root)
        for item in removed { try? FileManager.default.removeItem(at: root.appendingPathComponent(item.fileName)) }
    }

    func refreshPreviews(spaceID: String, activityID: String, rows: [[String: Any]]) async {
        guard !publishing else { return }
        guard let subject = try? await currentSubject(), let root = try? directory(for: subject),
              let index = try? readIndex(at: root) else { return }
        let prefix = "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)"
        // A list response is not proof that a missing photo was revoked. Keep
        // originals until deletion is confirmed so other members can fetch them.
        for photo in index.photos where photo.spaceID == spaceID && photo.activityID == activityID {
            guard rows.contains(where: { ($0["id"] as? String) == photo.id && ($0["thumbnailAvailable"] as? Bool) == false }) else { continue }
            let path = root.appendingPathComponent(photo.fileName)
            guard (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) == photo.length,
                  let thumbnail = try? preview(fromFile: path) else { continue }
            try? await uploadThumbnail(thumbnail, prefix: prefix, photoID: photo.id, revision: photo.sha256)
        }
    }

    func localOriginal(photoID: String, spaceID: String, activityID: String) async -> URL? {
        guard let subject = try? await currentSubject(), let root = try? directory(for: subject),
              let index = try? readIndex(at: root),
              let photo = index.photos.first(where: { $0.id == photoID && $0.spaceID == spaceID && $0.activityID == activityID }) else { return nil }
        let path = root.appendingPathComponent(photo.fileName)
        guard (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) == photo.length,
              (try? await hashFile(path)) == photo.sha256 else { return nil }
        return path
    }

    func downloadOriginal(photoID: String, spaceID: String, activityID: String,
                          progress: ((Double) -> Void)? = nil) async throws -> URL {
        guard UUID(uuidString: photoID) != nil, UUID(uuidString: spaceID) != nil,
              UUID(uuidString: activityID) != nil else { throw APIError.message("照片标识无效。") }
        if let local = await localOriginal(photoID: photoID, spaceID: spaceID, activityID: activityID) { return local }
        guard let store, let token = store.identity.accessToken else { throw APIError.message("请先登录用户中心。") }
        let value = try await store.call("/api/dear/social/tenants/\(spaceID)/activities/\(activityID)/photo-requests",
                                         method: "POST", body: ["photoId": photoID, "operationId": UUID().uuidString])
        guard let request = value as? [String: Any], let id = request["id"] as? String,
              UUID(uuidString: id) != nil, let length = (request["length"] as? NSNumber)?.intValue,
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
        if FileManager.default.fileExists(atPath: partialURL.path) {
            let size = try partialURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if size >= length {
                if size == length, (try? await hashFile(partialURL))?.caseInsensitiveCompare(sha) == .orderedSame {
                    try FileManager.default.moveItem(at: partialURL, to: finalURL)
                    _ = try? await store.call("/api/dear/social/photo-requests/\(id)/cancel", method: "POST", body: [:])
                    progress?(1)
                    return finalURL
                }
                try FileManager.default.removeItem(at: partialURL)
            }
        }
        if !FileManager.default.fileExists(atPath: partialURL.path) &&
            !FileManager.default.createFile(atPath: partialURL.path, contents: nil,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) {
            throw APIError.message("无法保存接收的原文件。")
        }
        let offset = try partialURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        var digest = SHA256()
        if offset > 0 {
            let existing = try FileHandle(forReadingFrom: partialURL)
            defer { try? existing.close() }
            while let chunk = try existing.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                digest.update(data: chunk)
                await Task.yield()
            }
        }
        var prefixDigest = digest
        let prefix = offset == 0 ? "" : prefixDigest.finalize().map { String(format: "%02x", $0) }.joined()
        progress?(Double(offset) / Double(length))
        var completed = false
        var badPartial = false
        do {
            let output = try FileHandle(forWritingTo: partialURL)
            defer { try? output.close() }
            try output.seek(toOffset: UInt64(offset))
            var received = offset
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            components.scheme = "wss"
            components.path = "/api/dear/social/photo-requests/\(id)/transfer"
            components.queryItems = [URLQueryItem(name: "role", value: "receiver"),
                                     URLQueryItem(name: "offset", value: String(offset))]
            if offset > 0 { components.queryItems?.append(URLQueryItem(name: "prefixSha256", value: prefix)) }
            var socketRequest = URLRequest(url: components.url!)
            socketRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            socketRequest.timeoutInterval = contentType.hasPrefix("video/") ? 1805 : 305
            let socket = session.webSocketTask(with: socketRequest)
            socket.resume()
            defer { socket.cancel(with: .normalClosure, reason: nil) }
            var started = false
            while true {
                try Task.checkCancellation()
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    guard let bytes = text.data(using: .utf8),
                          let marker = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                          let kind = marker["kind"] as? String else { throw APIError.message("原图传输消息无效。") }
                    if kind == "start" && !started {
                        guard (marker["length"] as? NSNumber)?.intValue == length,
                              (marker["offset"] as? NSNumber)?.intValue == offset,
                              (marker["sha256"] as? String)?.caseInsensitiveCompare(sha) == .orderedSame else {
                            badPartial = true
                            throw APIError.message("原图续传信息不匹配。")
                        }
                        started = true
                    } else if kind == "end" && started {
                        try output.synchronize()
                        guard received == length,
                              digest.finalize().map({ String(format: "%02x", $0) }).joined().caseInsensitiveCompare(sha) == .orderedSame,
                              (contentType.hasPrefix("video/") || UIImage(contentsOfFile: partialURL.path) != nil) else {
                            badPartial = true
                            throw APIError.message("原文件完整性校验失败。")
                        }
                        _ = try await store.call("/api/dear/social/photo-requests/\(id)/complete", method: "POST", body: [:])
                        try output.close()
                        try FileManager.default.moveItem(at: partialURL, to: finalURL)
                        progress?(1)
                        completed = true
                        return finalURL
                    } else if kind == "reset" {
                        badPartial = true
                        throw APIError.message("本地部分文件与分享源不一致，再次获取将从头开始。")
                    } else { throw APIError.message("原图传输顺序无效。") }
                case .data(let chunk):
                    guard started, received + chunk.count <= length else {
                        badPartial = true
                        throw APIError.message("原图大小不匹配。")
                    }
                    try output.write(contentsOf: chunk)
                    digest.update(data: chunk)
                    received += chunk.count
                    if received == length || received % (1024 * 1024) < chunk.count {
                        progress?(Double(received) / Double(length))
                    }
                @unknown default: throw APIError.message("原图传输格式无效。")
                }
            }
        } catch {
            if badPartial { try? FileManager.default.removeItem(at: partialURL) }
            if !completed { _ = try? await store.call("/api/dear/social/photo-requests/\(id)/cancel", method: "POST", body: [:]) }
            throw error
        }
    }

    private func currentSubject() async throws -> String {
        if let subjectCache, store?.identity.isAuthenticated == true { return subjectCache }
        guard let store, store.identity.isAuthenticated,
              let me = try await store.call("/api/dear/social/me") as? [String: Any],
              let subject = me["subject"] as? String, !subject.isEmpty else {
            throw APIError.message("请先在 iPhone 上登录 Linko Moment。")
        }
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

    private func preview(fromFile fileURL: URL) throws -> Data {
        let image: UIImage?
        if fileURL.pathExtension.lowercased() == "mp4" || fileURL.pathExtension.lowercased() == "mov" {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fileURL))
            generator.appliesPreferredTrackTransform = true
            image = (try? generator.copyCGImage(at: .zero, actualTime: nil)).map(UIImage.init(cgImage:))
        } else { image = UIImage(contentsOfFile: fileURL.path) }
        guard let image, image.size.width > 0, image.size.height > 0 else {
            throw APIError.message("无法处理照片预览。")
        }
        let scale = min(360 / image.size.width, 360 / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.65), jpeg.count <= 256 * 1024 else {
            throw APIError.message("照片预览无法压缩。")
        }
        return jpeg
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

    private func poll() async {
        guard !Task.isCancelled, let store, store.identity.isAuthenticated,
              let subject = try? await currentSubject(), let root = try? directory(for: subject),
              let index = try? readIndex(at: root), let deviceID = index.deviceID else { return }
        do {
            let rows = try await store.call("/api/dear/social/photo-devices/\(deviceID)/requests") as? [[String: Any]] ?? []
            if rows.isEmpty { store.photoRequestNotice = nil; store.photoTransferProgress = nil; return }
            store.photoRequestNotice = "有活动成员正在请求原图，请保持 App 打开直到传输完成。"
            store.photoTransferProgress = nil
            defer { store.photoRequestNotice = nil; store.photoTransferProgress = nil }
            for request in rows {
                guard !Task.isCancelled else { return }
                let requestID = request["id"] as? String ?? ""
                guard UUID(uuidString: requestID) != nil else { continue }
                let photoID = request["photoId"] as? String ?? ""
                guard let photo = index.photos.first(where: { $0.id == photoID }),
                      photo.spaceID == request["tenantId"] as? String,
                      photo.activityID == request["activityId"] as? String,
                      photo.length == (request["length"] as? Int),
                      photo.sha256.caseInsensitiveCompare(request["sha256"] as? String ?? "") == .orderedSame else {
                    _ = try? await store.call("/api/dear/social/photo-requests/\(requestID)/unavailable", method: "POST", body: [:])
                    continue
                }
                let path = root.appendingPathComponent(photo.fileName)
                guard (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) == photo.length,
                      (try? await hashFile(path)) == photo.sha256 else {
                    _ = try? await store.call("/api/dear/social/photo-requests/\(requestID)/unavailable", method: "POST", body: [:])
                    continue
                }
                try await sendOriginal(at: path, length: photo.length, requestID: requestID)
            }
        } catch { }
    }

    private func sendOriginal(at url: URL, length: Int, requestID: String) async throws {
        guard let store, let token = store.identity.accessToken else { throw APIError.message("登录已过期。") }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        components.path = "/api/dear/social/photo-requests/\(requestID)/transfer"
        components.queryItems = [URLQueryItem(name: "role", value: "source"), URLQueryItem(name: "protocol", value: "2")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }
        guard case .string(let controlText) = try await task.receive(),
              let controlData = controlText.data(using: .utf8),
              let control = try JSONSerialization.jsonObject(with: controlData) as? [String: Any],
              control["kind"] as? String == "resume",
              let offset = (control["offset"] as? NSNumber)?.intValue,
              offset >= 0, offset < length,
              let prefix = control["prefixSha256"] as? String else {
            throw APIError.message("续传请求无效。")
        }
        let localPrefix = offset == 0 ? "" : try await Task.detached(priority: .utility) {
            try Self.fileSHA256(url, limit: offset)
        }.value
        guard localPrefix.caseInsensitiveCompare(prefix) == .orderedSame else {
            try? await task.send(.string("{\"kind\":\"reset\"}"))
            throw APIError.message("已接收部分与本机原文件不匹配，请重新获取。")
        }
        try input.seek(toOffset: UInt64(offset))
        try await task.send(.string("{\"kind\":\"ready\"}"))
        var sent = offset
        store.photoTransferProgress = Double(sent) / Double(length)
        var reportedPercent = -1
        while let chunk = try input.read(upToCount: 16 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            guard sent + chunk.count <= length else { throw APIError.message("原文件已发生变化。") }
            try await task.send(.data(chunk))
            sent += chunk.count
            let percent = Int(Double(sent) / Double(length) * 100)
            if percent / 5 != reportedPercent / 5 {
                store.photoRequestNotice = "正在实时传输原文件：\(percent)%；请保持 App 打开。"
                store.photoTransferProgress = Double(sent) / Double(length)
                reportedPercent = percent
            }
        }
        guard sent == length else { throw APIError.message("原文件已发生变化。") }
        // Linko confirms receipt only after the other device has consumed all bytes.
        do { _ = try await task.receive() }
        catch {
            guard task.closeCode == .normalClosure else { throw error }
        }
    }
}
