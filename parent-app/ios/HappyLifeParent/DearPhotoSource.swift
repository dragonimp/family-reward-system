import CryptoKit
import Foundation
import UIKit

// Linko Social keeps original image bytes on the source device. This adapter
// stores the selected JPEG on the paired iPhone and serves verified requests.
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
    func reset() { stop(); subjectCache = nil }

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
            _ = try await store.call("/api/dear/social/photo-devices", method: "POST", body: ["id": deviceID])
            enabledForSession = true
        } catch { }
    }

    func publish(_ imageData: Data, spaceID: String, activityID: String, name: String) async throws {
        guard !publishing else { throw APIError.message("另一张照片正在共享，请稍后重试。") }
        publishing = true
        defer { publishing = false }
        guard UUID(uuidString: spaceID) != nil, UUID(uuidString: activityID) != nil,
              imageData.count > 0, imageData.count <= 50 * 1024 * 1024,
              UIImage(data: imageData) != nil else { throw APIError.message("照片文件无效或超过 50 MB。") }
        guard let store else { throw APIError.message("活动服务暂不可用。") }
        let subject = try await currentSubject()
        let root = try directory(for: subject)
        var index = try readIndex(at: root)
        let device = try await store.call("/api/dear/social/photo-devices", method: "POST",
                                          body: ["id": index.deviceID as Any? ?? NSNull()]) as? [String: Any]
        guard let deviceID = device?["id"] as? String, UUID(uuidString: deviceID) != nil else {
            throw APIError.message("照片分享设备登记失败。")
        }
        index.deviceID = deviceID
        try writeIndex(index, at: root)
        enabledForSession = true

        let localName = UUID().uuidString + ".jpg"
        let localURL = root.appendingPathComponent(localName)
        try imageData.write(to: localURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let sha = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        let displayName = String(name.prefix(200)).isEmpty ? "共享照片.jpg" : String(name.prefix(200))
        let prefix = "/api/dear/social/tenants/\(spaceID)/activities/\(activityID)"
        var publishedID: String?
        do {
            let response = try await store.call(prefix + "/native-photos", method: "POST", body: [
                "deviceId": deviceID, "fileName": displayName, "contentType": "image/jpeg",
                "length": imageData.count, "sha256": sha]) as? [String: Any]
            guard let photoID = response?["id"] as? String, UUID(uuidString: photoID) != nil else {
                throw APIError.message("照片登记回执无效。")
            }
            publishedID = photoID
            index.photos.append(SharedPhoto(id: photoID, spaceID: spaceID, activityID: activityID,
                                            fileName: localName, length: imageData.count, sha256: sha))
            try writeIndex(index, at: root)
            do {
                let thumbnail = try preview(from: imageData)
                try await uploadThumbnail(thumbnail, prefix: prefix, photoID: photoID, revision: sha)
            } catch {
                // The original remains available. Opening the album retries a missing preview.
            }
            start()
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
            guard let data = try? Data(contentsOf: path), data.count == photo.length,
                  let thumbnail = try? preview(from: data) else { continue }
            try? await uploadThumbnail(thumbnail, prefix: prefix, photoID: photo.id, revision: photo.sha256)
        }
    }

    private func currentSubject() async throws -> String {
        if let subjectCache, store?.identity.isAuthenticated == true { return subjectCache }
        guard let store, store.identity.isAuthenticated,
              let me = try await store.call("/api/dear/social/me") as? [String: Any],
              let subject = me["subject"] as? String, !subject.isEmpty else {
            throw APIError.message("请先在 iPhone 上登录 Linko Dear。")
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

    private func preview(from data: Data) throws -> Data {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw APIError.message("无法处理照片预览。")
        }
        let scale = min(360 / image.size.width, 360 / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
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
                guard let data = try? Data(contentsOf: path), data.count == photo.length,
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == photo.sha256 else {
                    _ = try? await store.call("/api/dear/social/photo-requests/\(requestID)/unavailable", method: "POST", body: [:])
                    continue
                }
                try await sendOriginal(data, requestID: requestID)
            }
        } catch { }
    }

    private func sendOriginal(_ data: Data, requestID: String) async throws {
        guard let store, let token = store.identity.accessToken else { throw APIError.message("登录已过期。") }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        components.path = "/api/dear/social/photo-requests/\(requestID)/transfer"
        components.queryItems = [URLQueryItem(name: "role", value: "source")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }
        for start in stride(from: 0, to: data.count, by: 16 * 1024) {
            try Task.checkCancellation()
            try await task.send(.data(data.subdata(in: start..<min(start + 16 * 1024, data.count))))
        }
        // Linko confirms receipt only after the other device has consumed all bytes.
        do { _ = try await task.receive() }
        catch {
            guard task.closeCode == .normalClosure else { throw error }
        }
    }
}
