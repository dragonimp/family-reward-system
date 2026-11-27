import AgentIdentity
import SwiftUI
import CoreMotion
import CryptoKit
import MapKit
import CoreLocation
import HealthKit
import UniformTypeIdentifiers

@MainActor final class ExerciseStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    private static var stores: [String: ExerciseStore] = [:]
    static func shared(userID: String) -> ExerciseStore {
        if let value = stores[userID] { return value }
        let value = ExerciseStore(userID: userID); stores[userID] = value; return value
    }
    @Published private var archive = ExerciseArchive()
    @Published var message: String?
    @Published var busy = false
    @Published var syncing = false
    @Published var syncMessage: String?
    @Published private(set) var conflicts: [ExerciseSession] = []
    @Published var locationMessage: String?
    private let locator = CLLocationManager()
    private var routeSegment = UUID()
    private var lastLocation: CLLocation?
    private var lastLocationAt = Date.distantPast
    private var tracking = false
    private weak var api: FamilyStore?
    private let userID: String
    private var syncAgain = false
    private var lastNotice = Date.distantPast
    private var lastSensorSave = Date.distantPast
    private let persistence = DispatchQueue(label: "net.impx.happylife.exercise.persistence", qos: .utility)
    private let pedometer = CMPedometer()
    private let file: URL
    private var generation = UUID()
    private var readable = true
    var active: ExerciseSession? { archive.active }
    var history: [ExerciseSession] { archive.history }
    var supported: Bool { CMPedometer.isStepCountingAvailable() }
    var distanceSupported: Bool { CMPedometer.isDistanceAvailable() }

    init(userID: String) {
        self.userID = userID
        let key = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exercise/\(key).json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do { archive = try decoder.decode(ExerciseArchive.self, from: Data(contentsOf: file)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { }
        catch { readable = false; message = String(localized: "运动记录暂时无法读取，请重新打开页面后重试。原记录已保留。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
        super.init()
        locator.delegate = self
        locator.desiredAccuracy = kCLLocationAccuracyBest
        locator.distanceFilter = 5
        locator.activityType = .fitness
        locator.pausesLocationUpdatesAutomatically = true
    }

    deinit { locator.stopUpdatingLocation(); pedometer.stopUpdates() }

    @discardableResult private func save(sensorUpdate: Bool = false) -> Bool {
        guard readable else { return false }
        if sensorUpdate {
            guard Date().timeIntervalSince(lastSensorSave) >= 5 else { return true }
            lastSensorSave = Date()
            let snapshot = archive, target = file
            persistence.async { [weak self] in
                do {
                    try snapshot.write(to: target)
                    Task { @MainActor in NotificationCenter.default.post(name: .exerciseRecordsChanged, object: nil) }
                }
                catch {
                    let detail = error.localizedDescription
                    Task { @MainActor [weak self] in
                        self?.message = String(localized: "运动记录尚未保存：\(detail)。请保留页面并重试保存。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
                    }
                }
            }
            return true
        }
        do {
            let snapshot = archive, target = file
            try persistence.sync { try snapshot.write(to: target) }
            if Date().timeIntervalSince(lastNotice) >= 5 || active == nil {
                lastNotice = Date(); NotificationCenter.default.post(name: .exerciseRecordsChanged, object: nil)
            }
            return true
        } catch { message = String(localized: "运动记录尚未保存：\(error.localizedDescription)。请保留页面并重试保存。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return false }
    }
    func retrySave() { guard readable else { return }; message = nil; save() }

    func deleteRecord(id: UUID) {
        guard readable, !busy, archive.history.contains(where: { $0.id == id }) else { return }
        do { try persistence.sync { try archive.deleteHistoryRecord(id: id, file: file) }
            Task { await sync() } }
        catch {
            message = String(localized: "删除失败，运动记录已保留，请稍后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        }
    }

    private var shareUpload: Task<Void, Never>?
    private var lastShareUpload = Date.distantPast
    private var shareUploadGeneration = UUID()

    func friendShare(for workout: UUID) -> UUID? { archive.friendShares?[workout] }

    func bindFriendShare(_ code: UUID, to workout: UUID) {
        if archive.friendShares == nil { archive.friendShares = [:] }
        archive.friendShares?[workout] = code
        save()
    }

    func clearFriendShare(for workout: UUID) {
        archive.friendShares?.removeValue(forKey: workout)
        save()
    }

    func uploadFriendTrack(_ record: ExerciseSession, code: UUID) async throws {
        guard let api, archive.friendShares?[record.id] == code else { return }
        let points = record.routePoints
        guard !points.isEmpty else { return }
        let step = max(1, (points.count + 1997) / 1999)
        var sampled = stride(from: 0, to: points.count - 1, by: step).map { points[$0] }
        if let last = points.last { sampled.append(last) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try JSONSerialization.jsonObject(with: encoder.encode(sampled))
        _ = try await api.call("/api/exercise/shares/\(code.uuidString)/track", method: "PUT",
                               body: ["workoutId": record.id.uuidString, "points": body], timeout: 15)
    }

    private func scheduleFriendTrack(_ record: ExerciseSession, force: Bool = false) {
        guard let code = friendShare(for: record.id),
              force || (shareUpload == nil && Date().timeIntervalSince(lastShareUpload) >= 15) else { return }
        let previous = shareUpload
        let generation = UUID()
        shareUploadGeneration = generation
        lastShareUpload = .now
        shareUpload = Task { [weak self] in
            _ = await previous?.result
            guard let self, !Task.isCancelled else { return }
            defer { if self.shareUploadGeneration == generation { self.shareUpload = nil } }
            try? await self.uploadFriendTrack(record, code: code)
        }
    }

    func joinFriendShare(_ code: UUID, kind: String, name: String) async throws {
        guard let api, active == nil, readable, !busy else { return }
        busy = true
        defer { busy = false }
        let now = Date()
        let proposed = UUID()
        let response = try await api.call("/api/exercise/shares/\(code.uuidString)/member", method: "PUT",
                                          body: ["name": name, "workoutId": proposed.uuidString], timeout: 15) as? [String: Any]
        guard let value = response?["workoutId"] as? String, let id = UUID(uuidString: value) else {
            throw CocoaError(.coderReadCorrupt)
        }
        try Task.checkCancellation()
        if let prior = history.first(where: { $0.id == id }) {
            continueRecordAfterJoining(prior, code: code)
        } else {
            archive.active = ExerciseSession(id: id, kind: kind, startedAt: now,
                                             intervals: [ExerciseInterval(start: now)], routeEnabled: true)
            bindFriendShare(code, to: id)
        }
        observe()
        updateLocationTracking()
    }

    private func continueRecordAfterJoining(_ record: ExerciseSession, code: UUID) {
        archive.active = record.continuation(at: Date())
        archive.active?.routeEnabled = true
        bindFriendShare(code, to: record.id)
    }

    func editWorkout(id: UUID, kind: String, activity target: ExerciseActivity?) async throws {
        guard readable, !busy, !syncing else {
            throw APIError.message(String(localized: "运动正在同步，请稍后重试。", bundle: AgentIdentityLanguage.appBundle()))
        }
        if var current = active, current.id == id {
            current.kind = kind
            current.activity = target
            current.activityText = nil
            archive.active = current
            save()
            refreshTrackingAfterEdit()
            return
        }
        guard let api, let index = archive.history.firstIndex(where: { $0.id == id }) else { throw CancellationError() }
        let original = archive.history[index]
        busy = true
        defer { busy = false }
        var edited = original
        edited.kind = kind
        edited.activity = target
        edited.activityText = nil
        edited.activityText = edited.activitySummary
        if let source = original.activity, let target {
            let moment = archive.activityShares?[id] ?? id
            let path = "/api/dear/social/tenants/\(source.tenantID.uuidString)/activities/\(source.id.uuidString)/moments/\(moment.uuidString)/activity"
            do {
                let result = try await api.call(path, method: "PUT", body: [
                    "activityId": target.id.uuidString, "text": edited.activitySummary
                ]) as? [String: Any]
                if let value = result?["id"] as? String, let momentID = UUID(uuidString: value) {
                    if archive.activityShares == nil { archive.activityShares = [:] }
                    archive.activityShares?[id] = momentID
                }
            } catch APIError.http(404, _) {
                archive.activityShares?.removeValue(forKey: id)
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadata = try JSONSerialization.jsonObject(with: encoder.encode(edited)) as? [String: Any] ?? [:]
        let recordPath = "/api/exercise/records/\(id.uuidString)"
        do {
            _ = try await api.call(recordPath + "/metadata", method: "PATCH", body: [
                "kind": kind, "activity": metadata["activity"] ?? NSNull(), "activityText": edited.activitySummary
            ])
        } catch APIError.http(404, _) {
            _ = try await api.call(recordPath, method: "PUT", body: metadata)
        }
        try Task.checkCancellation()
        guard DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID),
              let index = archive.history.firstIndex(where: { $0.id == id }) else { throw CancellationError() }
        archive.history[index] = edited
        if !save() { throw CocoaError(.fileWriteUnknown) }
        NotificationCenter.default.post(name: .exerciseActivityPublished, object: nil)
        Task { await sync() }
    }

    private func refreshTrackingAfterEdit() {
        stopObserving()
        observe()
        updateLocationTracking()
    }

    func start(kind: String, activity: ExerciseActivity? = nil) {
        guard readable, active == nil, !busy else { return }
        let now = Date()
        archive.active = ExerciseSession(kind: kind, startedAt: now, intervals: [ExerciseInterval(start: now)], activity: activity, routeEnabled: true)
        save(); observe(); updateLocationTracking()
    }
    func continueRecord(_ record: ExerciseSession) {
        guard readable, active == nil, !busy, history.contains(where: { $0.id == record.id }) else { return }
        archive.active = record.continuation(at: Date())
        archive.active?.routeEnabled = true
        save(); observe(); updateLocationTracking()
    }
    @discardableResult func importWatchRecords(_ records: [ExerciseSession]) -> Bool {
        guard readable else { return false }
        for var record in records where !(archive.importedWatchIDs ?? []).contains(record.id) {
            if record.activityText == nil { record.activityText = record.activitySummary }
            if !archive.history.contains(where: { $0.id == record.id }) && !(archive.pendingDeletions ?? []).contains(record.id) { archive.history.append(record) }
            archive.importedWatchIDs = (archive.importedWatchIDs ?? []) + [record.id]
        }
        archive.history.sort { $0.startedAt > $1.startedAt }; return save()
    }
    func resume() {
        guard readable, !busy else { return }
        archive.active?.resume(at: Date()); save(); observe(); updateLocationTracking()
    }
    func pause() async {
        guard active?.running == true, !busy else { return }
        stopLocationTracking()
        stopObserving()
        archive.active?.pause(at: Date()); save()
        await reconcile()
    }
    func finish() async {
        guard active != nil, !busy else { return }
        stopLocationTracking()
        stopObserving()
        let now = Date()
        archive.active?.pause(at: now)
        save()
        await reconcile()
        guard var completed = archive.active else { return }
        completed.endedAt = now
        completed.route = completed.route?.filter { point in completed.intervals.contains { point.recordedAt >= $0.start && point.recordedAt <= ($0.end ?? now) } }
        completed.activityText = completed.activitySummary
        scheduleFriendTrack(completed, force: true)
        archive.history.insert(completed, at: 0)
        archive.active = nil
        save()
        await sync()
    }
    func refresh() async {
        guard readable, !busy else { return }
        stopObserving()
        await reconcile()
        if active?.running == true { observe(); updateLocationTracking() }
    }
    func stopObserving() { generation = UUID(); pedometer.stopUpdates() }

    func connect(_ store: FamilyStore) { api = store; store.exerciseStore = self }
    func accountDidChange() { shareUpload?.cancel(); api = nil; stopLocationTracking(); stopObserving(); Self.stores.removeValue(forKey: userID) }
    func enableRoute() {
        guard active != nil, readable else { return }
        archive.active?.routeEnabled = true; save(); updateLocationTracking()
    }
    private func stopLocationTracking() {
        locator.stopUpdatingLocation(); tracking = false; lastLocation = nil; routeSegment = UUID()
    }
    private func updateLocationTracking() {
        guard readable, active?.running == true, active?.routeEnabled == true else { stopLocationTracking(); return }
        switch locator.authorizationStatus {
        case .notDetermined: locator.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard !tracking else { return }
            routeSegment = UUID(); lastLocation = nil; tracking = true
            locator.allowsBackgroundLocationUpdates = true
            locator.showsBackgroundLocationIndicator = true
            locator.startUpdatingLocation(); locationMessage = String(localized: "正在记录轨迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .denied, .restricted: stopLocationTracking(); locationMessage = String(localized: "未开启定位，可在系统设置中允许位置访问。计时与计步仍可使用。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        @unknown default: locationMessage = String(localized: "定位暂不可用", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { updateLocationTracking() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard tracking, let active, active.running, active.routeEnabled == true else { return }
        let usesGPSDistance = active.kind == "滑雪" || active.kind == "飞行"
        let maxSpeed: Double = active.kind == "飞行" ? 360 : (usesGPSDistance ? 50 : 20)
        var changed = false
        for location in locations {
            let age = Date().timeIntervalSince(location.timestamp)
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 65, age >= -5, age <= 15,
                  location.timestamp > lastLocationAt else { continue }
            if let previous = lastLocation {
                let dt = location.timestamp.timeIntervalSince(previous.timestamp)
                if dt > 60 { routeSegment = UUID(); lastLocation = nil }
                else if dt < 3 || location.distance(from: previous) < 3 || location.distance(from: previous) / dt > maxSpeed { continue }
            }
            let point = ExerciseRoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                recordedAt: location.timestamp, segment: routeSegment,
                altitudeMeters: location.verticalAccuracy >= 0 && location.altitude.isFinite ? location.altitude : nil,
                verticalAccuracyMeters: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil)
            if archive.active?.appendRoute(point) == true {
                if usesGPSDistance, let previous = lastLocation, let index = active.intervals.indices.last {
                    let distance = archive.active?.intervals[index].distanceMeters ?? 0
                    archive.active?.intervals[index].distanceMeters = distance + location.distance(from: previous)
                }
                lastLocation = location; lastLocationAt = location.timestamp; changed = true
                locationMessage = String(localized: "正在记录轨迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
            }
        }
        if changed {
            save(sensorUpdate: true)
            if let tracked = archive.active { scheduleFriendTrack(tracked) }
        }
        else if let last = locations.last, last.horizontalAccuracy > 65 { locationMessage = String(localized: "定位精度不足，可在系统设置中开启精确位置。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
        if (archive.active?.route?.count ?? 0) >= 20_000 { stopLocationTracking(); locationMessage = String(localized: "本次轨迹已达记录上限，计时与计步继续。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { locationMessage = String(localized: "正在获取 GPS 信号", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return }
        locationMessage = String(localized: "定位暂不可用，请检查系统定位权限。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    func sync() async {
        guard readable, let api, !userID.isEmpty, DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID) else { return }
        if syncing { syncAgain = true; return }
        syncing = true; syncMessage = nil
        defer {
            syncing = false
            if syncAgain { syncAgain = false; Task { await sync() } }
        }
        do {
            for id in archive.pendingDeletions ?? [] {
                _ = try await api.call("/api/exercise/records/\(id.uuidString)", method: "DELETE")
                guard DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID) else { return }
                archive.pendingDeletions?.removeAll { $0 == id }; save()
            }
            var remote: [UUID: Bool] = [:]; var revisions: [UUID: UUID] = [:]; var cursor: String?
            repeat {
                let page = try await api.call("/api/exercise/records" + (cursor.map { "?after=" + $0 } ?? "")) as? [String: Any] ?? [:]
                guard DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID) else { return }
                for entry in page["records"] as? [[String: Any]] ?? [] {
                    if let raw = entry["id"] as? String, let id = UUID(uuidString: raw) {
                        remote[id] = entry["deleted"] as? Bool ?? false
                        revisions[id] = (entry["metadataRevision"] as? String).flatMap(UUID.init(uuidString:))
                    }
                }
                let next = page["next"] as? String
                if next == cursor && next != nil { throw APIError.message(String(localized: "服务器分页无效，请稍后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                cursor = next
            } while cursor != nil
            for (id, deleted) in remote where deleted {
                archive.history.removeAll { $0.id == id }; archive.uploaded?.removeAll { $0 == id }
            }
            save()
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let decoder = ExerciseSession.syncDecoder()
            for (id, revision) in revisions where remote[id] == false {
                guard archive.history.contains(where: { $0.id == id && $0.metadataRevision != revision }) else { continue }
                let value = try await api.call("/api/exercise/records/\(id.uuidString)")
                let record = try decoder.decode(ExerciseSession.self, from: JSONSerialization.data(withJSONObject: value))
                guard DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID) else { return }
                if let index = archive.history.firstIndex(where: { $0.id == id }), record.id == id, record.endedAt != nil {
                    archive.history[index].kind = record.kind
                    archive.history[index].activity = record.activity
                    archive.history[index].activityText = record.activityText
                    archive.history[index].metadataRevision = record.metadataRevision
                }
            }
            var conflictingRecords = Set<UUID>()
            for record in archive.history where remote[record.id] == nil || !(archive.uploaded ?? []).contains(record.id) {
                guard !(archive.pendingDeletions ?? []).contains(record.id) else { continue }
                let body = try JSONSerialization.jsonObject(with: encoder.encode(record)) as! [String: Any]
                do {
                    _ = try await api.call("/api/exercise/records/\(record.id.uuidString)", method: "PUT", body: body)
                } catch APIError.http(409, _) {
                    conflictingRecords.insert(record.id)
                    continue
                }
                guard DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID) else { return }
                if archive.history.contains(where: { $0.id == record.id }) { archive.uploaded = Array(Set((archive.uploaded ?? []) + [record.id])); save() }
            }
            for (id, deleted) in remote where !deleted && !archive.history.contains(where: { $0.id == id }) && !(archive.pendingDeletions ?? []).contains(id) {
                let value = try await api.call("/api/exercise/records/\(id.uuidString)")
                let record = try decoder.decode(ExerciseSession.self, from: JSONSerialization.data(withJSONObject: value))
                guard DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID), record.id == id, record.endedAt != nil else { return }
                if !(archive.pendingDeletions ?? []).contains(id) && !archive.history.contains(where: { $0.id == id }) {
                    archive.history.append(record); archive.uploaded = Array(Set((archive.uploaded ?? []) + [id])); save()
                }
            }
            var activityShareError: String?
            for record in archive.history where !conflictingRecords.contains(record.id) && record.activity != nil && archive.activityShares?[record.id] == nil {
                guard let linked = record.activity, !(archive.pendingDeletions ?? []).contains(record.id), DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID) else { continue }
                do {
                let response = try await api.call("/api/dear/social/tenants/\(linked.tenantID.uuidString)/activities/\(linked.id.uuidString)/moments", method: "POST", body: ["text": record.activitySummary, "requestId": record.id.uuidString, "recordedAt": ISO8601DateFormatter().string(from: record.startedAt)]) as? [String: Any] ?? [:]
                guard DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID) else { return }
                guard let raw = response["id"] as? String, let id = UUID(uuidString: raw) else { throw APIError.message(String(localized: "活动动态未返回有效记录标识。", bundle: AgentIdentityLanguage.appBundle())) }
                if archive.activityShares == nil { archive.activityShares = [:] }; archive.activityShares?[record.id] = id; save()
                NotificationCenter.default.post(name: .exerciseActivityPublished, object: nil)
                } catch { activityShareError = String(localized: "运动已同步，活动动态待重试：\(error.localizedDescription)", bundle: AgentIdentityLanguage.appBundle()) }
            }
            archive.history.sort { $0.startedAt > $1.startedAt }
            save()
            conflicts = archive.history.filter { conflictingRecords.contains($0.id) }
            if !conflicts.isEmpty { syncMessage = activityShareError; return }
            syncMessage = activityShareError ?? String(localized: "已同步到当前账号", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        } catch is CancellationError { }
        catch { syncMessage = String(localized: "同步未完成，本机记录已保留：\(error.localizedDescription)", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }

    func resolveConflict(_ record: ExerciseSession, keepBoth: Bool) async {
        guard !syncing, let api, conflicts.contains(where: { $0.id == record.id }),
              DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID) else { return }
        syncing = true
        defer {
            syncing = false
            if syncAgain { syncAgain = false; Task { await sync() } }
        }
        do {
            let path = "/api/exercise/records/\(record.id.uuidString)"
            let response = try await api.call(path)
            let cloud = try ExerciseSession.syncDecoder().decode(
                ExerciseSession.self, from: JSONSerialization.data(withJSONObject: response))
            guard DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID),
                  cloud.id == record.id, cloud.endedAt != nil,
                  let local = archive.history.first(where: { $0.id == record.id }),
                  !(archive.pendingDeletions ?? []).contains(record.id) else { return }
            var resolved = archive
            resolved.history.removeAll { $0.id == record.id }
            resolved.history.append(cloud)
            resolved.uploaded = Array(Set((resolved.uploaded ?? []) + [cloud.id]))
            if keepBoth {
                var copy = local
                copy.id = UUID()
                resolved.history.append(copy)
                if let share = resolved.activityShares?[local.id] {
                    resolved.activityShares?[copy.id] = share
                }
            }
            resolved.history.sort { $0.startedAt > $1.startedAt }
            let snapshot = resolved
            try persistence.sync { try snapshot.write(to: file) }
            archive = snapshot
            conflicts.removeAll { $0.id == record.id }
            syncMessage = nil
            NotificationCenter.default.post(name: .exerciseRecordsChanged, object: nil)
            syncAgain = true
        } catch {
            syncMessage = String(localized: "未能解决冲突：\(momentDisplayError(error))", bundle: AgentIdentityLanguage.appBundle())
        }
    }

    private func observe() {
        stopObserving()
        guard let active, active.running, active.kind != "滑雪", active.kind != "飞行", let index = active.intervals.indices.last else { return }
        guard supported else { message = String(localized: "此设备不支持计步，可继续使用运动计时。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return }
        if CMPedometer.authorizationStatus() == .denied || CMPedometer.authorizationStatus() == .restricted {
            message = String(localized: "未获得运动与健身权限，可在系统设置中开启；计时仍可使用。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return
        }
        let revision = generation
        pedometer.startUpdates(from: active.intervals[index].start) { [weak self] data, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == revision, self.active?.id == active.id else { return }
                if let data {
                    self.archive.active?.intervals[index].steps = data.numberOfSteps.intValue
                    self.archive.active?.intervals[index].distanceMeters = data.distance?.doubleValue
                    self.save(sensorUpdate: true)
                }
                if let error { self.message = String(localized: "计步暂不可用：\(error.localizedDescription)。计时仍可使用。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
            }
        }
    }
    private func reconcile() async {
        guard let active, active.kind != "滑雪", active.kind != "飞行", supported else { return }
        // Query each active interval independently, excluding all paused time.
        busy = true
        defer { busy = false }
        for index in active.intervals.indices {
            let interval = active.intervals[index]
            let end = interval.end ?? Date()
            if interval.end != nil && interval.steps != nil && (!distanceSupported || interval.distanceMeters != nil) { continue }
            if end.timeIntervalSince(interval.start) >= 7 * 86400 || interval.start < Date().addingTimeInterval(-7 * 86400) {
                if interval.end == nil {
                    archive.active?.intervals[index].steps = nil
                    archive.active?.intervals[index].distanceMeters = nil
                }
                message = String(localized: "部分运动已超过系统数据保留期，步数或距离无法完整获取。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); continue
            }
            let result: (CMPedometerData?, Error?) = await withCheckedContinuation { continuation in
                pedometer.queryPedometerData(from: interval.start, to: end) { continuation.resume(returning: ($0, $1)) }
            }
            guard archive.active?.id == active.id else { return }
            if let data = result.0 {
                archive.active?.intervals[index].steps = data.numberOfSteps.intValue
                archive.active?.intervals[index].distanceMeters = data.distance?.doubleValue
            }
            if let error = result.1 { message = String(localized: "计步暂不可用：\(error.localizedDescription)。已保留计时记录。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
        }
        save()
    }
}

struct ExerciseView: View {
    @StateObject private var exercise: ExerciseStore
    @EnvironmentObject private var family: FamilyStore
    @Environment(\.scenePhase) private var phase
    @StateObject private var health = ExerciseHealth()
    @State private var showingHistory = false
    @State private var showingFriendWorkout = false
    @State private var workoutInvitation: UUID?
    @State private var workoutToShare: ExerciseSession?
    @State private var workoutToEdit: ExerciseSession?
    @State private var selectedRoute: ExerciseSession?
    @State private var kind = "散步"
    @State private var activity: ExerciseActivity?
    @State private var confirmFinish = false
    @State private var pendingDeletion: ExerciseSession?
    @State private var showingSyncConflict = false
    init(userID: String) { _exercise = StateObject(wrappedValue: ExerciseStore.shared(userID: userID)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if let linked = exercise.active?.activity ?? activity {
                    HStack {
                        Text(family.exerciseActivityTitle(linked)).lineLimit(1)
                        Spacer()
                        if exercise.active == nil {
                            Button(String(localized: "取消关联", bundle: AgentIdentityLanguage.appBundle())) { activity = nil; family.watchExerciseActivity = nil }
                        }
                    }
                }
                if exercise.active == nil {
                    Group {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                            exerciseTile("散步", icon: "figure.walk")
                            exerciseTile("慢跑", icon: "figure.run")
                            exerciseTile("徒步", icon: "figure.hiking")
                            exerciseTile("爬山", icon: "mountain.2")
                            exerciseTile("滑雪", icon: "figure.skiing.downhill")
                            exerciseTile("飞行", icon: "airplane")
                            exerciseTile("自由运动", icon: "figure.mixed.cardio")
                        }
                        .padding(.vertical, 4)
                    }
                }
                Group {
                    if let active = exercise.active {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 4) {
                                Text(ExerciseSession.clock(active.duration(at: context.date)))
                                    .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                                    .accessibilityLabel(String(localized: "运动时长", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                Text(active.distanceMeters == nil && !exercise.distanceSupported ? String(localized: "此设备不支持距离估算", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : exerciseDistanceTitle(active))
                                    .font(.title.bold()).monospacedDigit()
                                    .accessibilityLabel(String(localized: "运动距离，\(exerciseDistanceTitle(active))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                if active.kind != "滑雪", active.kind != "飞行" {
                                    Text(active.steps.map { String(localized: "\($0) 步", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) } ?? String(localized: "步数待获取", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                        .font(.title2).monospacedDigit()
                                }
                                if let speed = recentSpeed(active.routePoints, at: context.date), active.running {
                                    Label(String(format: "速度 %.1f 公里/小时", speed), systemImage: "speedometer")
                                        .font(.subheadline).monospacedDigit()
                                }
                                if let updated = family.watchMetricsUpdatedAt,
                                   updated >= active.startedAt, abs(context.date.timeIntervalSince(updated)) < 45 {
                                    if let heartRate = family.watchExerciseMetrics["heart"], heartRate > 0 {
                                        Label(String(format: "心率 %.0f 次/分", heartRate), systemImage: "heart.fill").foregroundStyle(.red)
                                    }
                                    if let energy = family.watchExerciseMetrics["energy"] {
                                        Label(String(format: "手表热量 %.0f 千卡", energy), systemImage: "flame")
                                    }
                                }
                                if let altitude = active.routePoints.last?.altitudeMeters { Text(String(format: String(localized: "海拔 %.1f 米", bundle: AgentIdentityLanguage.appBundle()), altitude)).font(.subheadline) }
                                Text(active.running ? String(localized: "运动中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "已暂停", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(active.running ? .teal : .secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        HStack {
                            Button(active.running ? String(localized: "暂停", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "继续", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                                if active.running { Task { await exercise.pause() } } else { exercise.resume() }
                            }.buttonStyle(.borderedProminent)
                            Spacer()
                            Button(String(localized: "结束并保存", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { confirmFinish = true }.buttonStyle(.bordered)
                        }.disabled(exercise.busy)
                    } else {
                        HStack(spacing: 8) {
                            Button {
                                exercise.start(kind: kind, activity: activity)
                                if exercise.active != nil { activity = nil; family.watchExerciseActivity = nil }
                            } label: {
                                Text(String(localized: "开始\(exerciseKindTitle(kind))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(exercise.busy)
                        }
                    }
                    Group {
                        ExerciseRouteMap(points: exercise.active?.routePoints ?? [], live: exercise.active?.running == true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(-1).clipShape(RoundedRectangle(cornerRadius: 14))
                        if let message = exercise.locationMessage, exercise.active != nil {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if exercise.active == nil && kind == "爬山" {
                        NavigationLink(String(localized: "附近山峰与导入路线", bundle: AgentIdentityLanguage.appBundle())) { HikingPlacesView(family: family) }
                    }

                }
                if let message = exercise.message {
                    Menu {
                        Button(String(localized: "重试读取步数与距离", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await exercise.refresh() } }
                        Button(String(localized: "重试保存记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { exercise.retrySave() }
                        Button(String(localized: "打开系统设置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    } label: {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.footnote).lineLimit(2)
                    }
                }

            }.padding(.horizontal).padding(.vertical, 8).navigationBarTitleDisplayMode(.inline).navigationTitle(String(localized: "运动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).readablePage()
                .toolbar {
                    if let current = exercise.active {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { workoutToEdit = current } label: {
                                Label(String(localized: "修改运动", bundle: AgentIdentityLanguage.appBundle()), systemImage: "pencil")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { workoutInvitation = nil; showingFriendWorkout = true } label: {
                            Label(String(localized: "好友运动", bundle: AgentIdentityLanguage.appBundle()), systemImage: "person.2")
                                .labelStyle(.iconOnly)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingHistory = true } label: {
                            Label(String(localized: "运动记录", bundle: AgentIdentityLanguage.appBundle()), systemImage: "clock.arrow.circlepath")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                .sheet(isPresented: $showingFriendWorkout) {
                    ExerciseFriendShareView(exercise: exercise, family: family, workout: workoutInvitation == nil ? exercise.active : nil, invitation: workoutInvitation)
                }
                .onChange(of: family.pendingWorkoutInvitation, initial: true) { _, invitation in
                    guard let invitation else { return }
                    exercise.connect(family)
                    workoutInvitation = invitation
                    showingFriendWorkout = true
                    family.pendingWorkoutInvitation = nil
                }
                .sheet(item: $workoutToEdit) { record in
                    ExerciseActivityEditor(store: family, scope: record.activity?.tenantID,
                                           selected: record.activity?.id, workoutKind: record.kind) { target, kind in
                        try await exercise.editWorkout(id: record.id, kind: kind ?? record.kind, activity: target)
                    }
                }
                .navigationDestination(isPresented: $showingHistory) { exerciseHistory }
                .confirmationDialog(String(localized: "结束本次运动并保存记录？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: $confirmFinish, titleVisibility: .visible) {
                    Button(String(localized: "结束并保存", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await exercise.finish() } }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        if exercise.syncing { ProgressView().controlSize(.small) }
                        Text(exercise.syncMessage ?? String(localized: "完成运动后自动同步", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        if !exercise.conflicts.isEmpty {
                            Button("解决冲突") { showingSyncConflict = true }.disabled(exercise.syncing)
                        }
                        Button(String(localized: "同步", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await exercise.sync() } }.disabled(exercise.syncing)
                    }.padding(.horizontal).padding(.vertical, 8).background(.bar)
                }
                .onChange(of: exercise.conflicts.first?.id, initial: true) { _, id in
                    showingSyncConflict = id != nil
                }
                .alert("运动同步冲突", isPresented: $showingSyncConflict, presenting: exercise.conflicts.first) { record in
                    Button("保留两份") { Task { await exercise.resolveConflict(record, keepBoth: true) } }
                    Button("使用云端记录", role: .destructive) { Task { await exercise.resolveConflict(record, keepBoth: false) } }
                    Button("稍后处理", role: .cancel) {}
                } message: { record in
                    Text("\(exerciseKindTitle(record.kind)) · \(record.startedAt.formatted())。本机与云端记录不同，请选择保留哪份。")
                }
                .task {
                    exercise.connect(family)
                    exercise.enableRoute()
                    receiveActivity()
                    if let id = family.pendingExerciseContinuation, let record = exercise.history.first(where: { $0.id == id }) { exercise.continueRecord(record); family.pendingExerciseContinuation = nil }
                    await family.refreshExerciseActivityTitles(); await exercise.refresh(); await refreshHealth()
                }
                .onChange(of: family.pendingExerciseContinuation) { _, value in
                    if let id = value, let record = exercise.history.first(where: { $0.id == id }) { exercise.continueRecord(record); family.pendingExerciseContinuation = nil }
                }
                .onChange(of: family.pendingExerciseActivity) { _, _ in receiveActivity() }
                .onChange(of: family.profile?.text("unifiedUserId")) { _, _ in activity = nil; exercise.accountDidChange() }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await family.refreshExerciseActivityTitles(); await exercise.refresh(); await refreshHealth() } }
                    else { exercise.stopObserving() }
                }
                .onDisappear { exercise.stopObserving() }
        }
    }
    private func refreshHealth(request: Bool = false) async {
        if request { await health.authorize() }
        let records = await health.watchRecords(userID: family.profile?.text("unifiedUserId") ?? "")
        exercise.importWatchRecords(records)
        await exercise.sync()
        if let record = exercise.active ?? exercise.history.first { await health.read(record) }
    }
    private var exerciseHistory: some View {
        List {
        Section {
            if exercise.history.isEmpty {
                ContentUnavailableView(String(localized: "还没有运动记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "figure.walk", description: Text(String(localized: "完成一次运动后，时长、步数和公里数会保存在这里。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))))
            }
            ForEach(exercise.history) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(exerciseKindTitle(item.kind)).bold()
                        Spacer()
                        Text(ExerciseSession.clock(item.duration(at: item.endedAt ?? .now))).monospacedDigit()
                        Button(role: .destructive) { pendingDeletion = item } label: {
                            Label(String(localized: "删除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "trash")
                        }.buttonStyle(.borderless).disabled(exercise.busy)
                    }
                    Button(String(localized: "继续\(item.kind)", bundle: AgentIdentityLanguage.appBundle())) { exercise.continueRecord(item); if exercise.active != nil { showingHistory = false } }.buttonStyle(.borderless).disabled(exercise.active != nil || exercise.busy)
                    if let linked = item.activity { Text(family.exerciseActivityTitle(linked)).font(.subheadline).foregroundStyle(.secondary) }
                    Text(exerciseDistanceTitle(item)).font(.headline).monospacedDigit()
                    if let altitude = item.altitudeRange { Text(String(format: String(localized: "海拔 %.1f–%.1f 米", bundle: AgentIdentityLanguage.appBundle()), altitude.lowerBound, altitude.upperBound)).font(.caption) }
                    Button { workoutToEdit = item } label: {
                        Label(String(localized: "修改运动", bundle: AgentIdentityLanguage.appBundle()), systemImage: "pencil")
                    }.buttonStyle(.borderless)
                    Button { workoutToShare = item } label: {
                        Label(String(localized: "分享运动", bundle: AgentIdentityLanguage.appBundle()), systemImage: "person.2")
                    }.buttonStyle(.borderless)
                    if !item.routePoints.isEmpty {
                        Button { selectedRoute = item } label: { Label(String(localized: "查看轨迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "map") }.buttonStyle(.borderless)
                    }
                    HStack {
                        Text(item.startedAt, format: .dateTime.year().month().day().hour().minute())
                        Spacer()
                        if item.kind != "滑雪", item.kind != "飞行" {
                            Text(item.steps.map { String(localized: "\($0) 步", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) } ?? String(localized: "步数未获取", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
                    .swipeActions(allowsFullSwipe: false) {
                        Button(String(localized: "删除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { pendingDeletion = item }
                            .disabled(exercise.busy)
                    }
            }
        } header: { Text(String(localized: "运动记录 · 当地时间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) } footer: { Text(String(localized: "运动记录及轨迹仅同步到当前账号。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        }
        .navigationTitle(String(localized: "运动记录", bundle: AgentIdentityLanguage.appBundle()))
        .navigationBarTitleDisplayMode(.inline)
                .alert(String(localized: "删除这条运动记录？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ), presenting: pendingDeletion) { item in
                    Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .cancel) { pendingDeletion = nil }
                    Button(String(localized: "删除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) {
                        exercise.deleteRecord(id: item.id)
                        pendingDeletion = nil
                    }
                } message: { item in
                    Text(String(localized: "将删除这条\(item.kind)记录及轨迹，并同步到其他设备，删除后无法恢复。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                }
                .sheet(item: $workoutToShare) { workout in
                    ExerciseFriendShareView(exercise: exercise, family: family, workout: workout)
                }
                .sheet(item: $selectedRoute) { item in
                    NavigationStack {
                        ExerciseRouteReplay(points: item.routePoints)
                            .navigationTitle(exerciseKindTitle(item.kind))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { selectedRoute = nil } } }
                    }
                }
    }

    private func exerciseTile(_ value: String, icon: String) -> some View {
        let selected = kind == value
        return Button { kind = value } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(exerciseKindTitle(value)).font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 66)
            .foregroundStyle(selected ? Color.teal : Color.primary)
            .background(selected ? Color.teal.opacity(0.13) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func receiveActivity() {
        guard let pending = family.pendingExerciseActivity else { return }
        family.pendingExerciseActivity = nil
        guard exercise.active == nil else {
            exercise.message = String(localized: "请先结束当前运动，再从活动创建运动。", bundle: AgentIdentityLanguage.appBundle())
            return
        }
        activity = pending
        family.watchExerciseActivity = pending
        kind = "徒步"
    }

}

private func exerciseKindTitle(_ value: String) -> String {
    let locale = Locale(identifier: AgentIdentityLanguage.current)
    switch value {
    case "爬山": return String(localized: "爬山", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
    case "散步": return String(localized: "散步", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
    case "飞行": return String(localized: "飞行", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
    case "滑雪": return String(localized: "滑雪", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
    case "徒步": return String(localized: "徒步", bundle: AgentIdentityLanguage.appBundle())
    case "慢跑": return String(localized: "慢跑", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
    case "自由运动": return String(localized: "自由运动", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
    default: return value
    }
}


private struct ExerciseRouteReplay: View {
    let points: [ExerciseRoutePoint]
    @State private var progress = 0.0
    @State private var playing = false

    var body: some View {
        let lastIndex = max(0, points.count - 1)
        VStack(spacing: 12) {
            ExerciseRouteMap(points: points, live: false, replayIndex: points.isEmpty ? nil : Int(progress))
            if lastIndex > 0 {
                HStack {
                    Button {
                        if !playing && progress >= Double(lastIndex) { progress = 0 }
                        playing.toggle()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .frame(width: 44, height: 44)
                    }.accessibilityLabel(Text(playing ? String(localized: "暂停回放", bundle: AgentIdentityLanguage.appBundle()) : String(localized: "播放轨迹", bundle: AgentIdentityLanguage.appBundle())))
                    Slider(value: $progress, in: 0...Double(lastIndex), onEditingChanged: { editing in
                        if editing { playing = false }
                    }).accessibilityLabel(Text(String(localized: "轨迹进度", bundle: AgentIdentityLanguage.appBundle())))
                    Text(ExerciseSession.clock(points[Int(progress)].recordedAt.timeIntervalSince(points[0].recordedAt)))
                        .monospacedDigit()
                }.padding(.horizontal)
            }
        }
        .task(id: playing) {
            guard playing else { return }
            let step = max(1, Double(lastIndex) / 300)
            while !Task.isCancelled && progress < Double(lastIndex) {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                progress = min(Double(lastIndex), progress + step)
            }
            playing = false
        }
    }
}

private struct ExerciseRouteMap: View {
    let points: [ExerciseRoutePoint]
    let live: Bool
    var replayIndex: Int? = nil
    @State private var position: MapCameraPosition = .automatic
    private struct Segment: Identifiable {
        let id: UUID
        let points: [ExerciseRoutePoint]
    }
    private var segments: [Segment] {
        Dictionary(grouping: points, by: \.segment).map { Segment(id: $0.key, points: $0.value) }
            .sorted { ($0.points.first?.recordedAt ?? .distantPast) < ($1.points.first?.recordedAt ?? .distantPast) }
    }
    private func coordinate(_ point: ExerciseRoutePoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }
    var body: some View {
        Map(position: $position) {
            ForEach(segments) { segment in
                if segment.points.count > 1 {
                    MapPolyline(coordinates: segment.points.map(coordinate)).stroke(.teal, lineWidth: 5)
                }
            }
            if let first = points.first { Marker(String(localized: "起点", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "flag.fill", coordinate: coordinate(first)).tint(.green) }
            if let last = points.last { Marker(live ? String(localized: "当前位置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "终点", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "figure.walk", coordinate: coordinate(last)).tint(.teal) }
            if let replayIndex, points.indices.contains(replayIndex) {
                let point = points[replayIndex]
                let clock = Date.FormatStyle(date: .omitted, time: .standard, timeZone: .autoupdatingCurrent)
                let fullTime = Date.FormatStyle(date: .abbreviated, time: .standard, timeZone: .autoupdatingCurrent)
                let spansDays = points.first.flatMap { first in
                    points.last.map { !Calendar.autoupdatingCurrent.isDate(first.recordedAt, inSameDayAs: $0.recordedAt) }
                } ?? false
                let speed = replaySpeed(points, at: replayIndex)
                let speedLabel = speed.map {
                    $0.formatted(.number.precision(.fractionLength(1))) + " km/h"
                }
                Annotation("", coordinate: coordinate(point), anchor: .bottom) {
                    VStack(spacing: 4) {
                        VStack(spacing: 2) {
                            Text(point.recordedAt, format: spansDays ? fullTime : clock)
                            if let speedLabel { Text(speedLabel).foregroundStyle(.secondary) }
                        }
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                        Image(systemName: "location.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .orange)
                            .background(.white, in: Circle())
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(Text(String(localized: "回放位置", bundle: AgentIdentityLanguage.appBundle())))
                    .accessibilityValue(Text([point.recordedAt.formatted(fullTime), speedLabel].compactMap { $0 }.joined(separator: ", ")))
                }
            }
            if live { UserAnnotation() }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .overlay(alignment: .topTrailing) {
            Button { position = points.isEmpty ? .userLocation(fallback: .automatic) : .automatic } label: {
                Image(systemName: "scope").padding(10).background(.regularMaterial, in: Circle())
            }.accessibilityLabel(String(localized: "查看完整轨迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).padding(12)
        }
        .overlay(alignment: .bottom) {
            if points.isEmpty { Text(live ? String(localized: "等待 GPS 轨迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "开始运动后记录轨迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).padding(8).background(.regularMaterial, in: Capsule()).padding(10) }
        }
        .onAppear { position = points.isEmpty && live ? .userLocation(fallback: .automatic) : .automatic }
        .onChange(of: points.isEmpty) { wasEmpty, isEmpty in
            guard live, wasEmpty, !isEmpty, let point = points.last else { return }
            position = .region(MKCoordinateRegion(center: coordinate(point),
                                                  latitudinalMeters: 500, longitudinalMeters: 500))
        }
    }
}

private func recentSpeed(_ points: [ExerciseRoutePoint], at date: Date) -> Double? {
    guard let last = points.last, points.count >= 2, abs(date.timeIntervalSince(last.recordedAt)) < 30 else { return nil }
    return routeSpeed(from: points[points.count - 2], to: last)
}

private func replaySpeed(_ points: [ExerciseRoutePoint], at index: Int) -> Double? {
    if index > 0, let speed = routeSpeed(from: points[index - 1], to: points[index]) {
        return speed
    }
    guard index + 1 < points.count else { return nil }
    return routeSpeed(from: points[index], to: points[index + 1])
}

private func routeSpeed(from previous: ExerciseRoutePoint, to last: ExerciseRoutePoint) -> Double? {
    let interval = last.recordedAt.timeIntervalSince(previous.recordedAt)
    guard previous.segment == last.segment, interval > 0, interval < 30 else { return nil }
    let first = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
    let end = CLLocation(latitude: last.latitude, longitude: last.longitude)
    return end.distance(from: first) / interval * 3.6
}

private func exerciseDistanceTitle(_ session: ExerciseSession) -> String {
    guard let distance = session.distanceMeters else {
        return String(localized: "距离未获取", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    let format = String(localized: "%.2f 公里", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    return String(format: format, locale: Locale(identifier: AgentIdentityLanguage.current), distance / 1000)
}

extension Notification.Name { static let exerciseActivityPublished = Notification.Name("moment.exerciseActivityPublished"); static let exerciseRecordsChanged = Notification.Name("moment.exerciseRecordsChanged") }

@MainActor final class ExerciseHealth: ObservableObject {
    private let store = HKHealthStore()
    @Published var steps: Double?
    @Published var distance: Double?
    @Published var heartRate: Double?
    @Published var energy: Double?
    @Published var message: String?
    func authorize() async {
        guard HKHealthStore.isHealthDataAvailable() else { message = String(localized: "此设备不支持 Apple 健康。", bundle: AgentIdentityLanguage.appBundle()); return }
        do {
            let types: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning)]
            try await store.requestAuthorization(toShare: [], read: types)
            message = String(localized: "已完成授权请求，数据以系统实际允许读取的项目为准。", bundle: AgentIdentityLanguage.appBundle())
        } catch { message = String(localized: "健康授权未完成：\(error.localizedDescription)", bundle: AgentIdentityLanguage.appBundle()) }
    }
    func read(_ record: ExerciseSession) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        heartRate = nil; energy = nil; steps = nil; distance = nil
        let predicates = record.intervals.map { HKQuery.predicateForSamples(withStart: $0.start, end: $0.end ?? Date(), options: .strictStartDate) }
        guard !predicates.isEmpty else { return }
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        heartRate = await value(.heartRate, predicate: predicate, options: .discreteAverage, unit: HKUnit.count().unitDivided(by: .minute()))
        energy = await value(.activeEnergyBurned, predicate: predicate, options: .cumulativeSum, unit: .kilocalorie())
        steps = await value(.stepCount, predicate: predicate, options: .cumulativeSum, unit: .count())
        distance = await value(.distanceWalkingRunning, predicate: predicate, options: .cumulativeSum, unit: .meter())
        if heartRate == nil && energy == nil { message = String(localized: "暂无可读取的健康数据；请检查授权并等待手表同步。", bundle: AgentIdentityLanguage.appBundle()) }
    }
    private func value(_ identifier: HKQuantityTypeIdentifier, predicate: NSPredicate, options: HKStatisticsOptions, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { continuation in
            store.execute(HKStatisticsQuery(quantityType: HKQuantityType(identifier), quantitySamplePredicate: predicate, options: options) { _, statistics, _ in
                let quantity = options == .cumulativeSum ? statistics?.sumQuantity() : statistics?.averageQuantity()
                continuation.resume(returning: quantity?.doubleValue(for: unit))
            })
        }
    }
    func watchRecords(userID: String) async -> [ExerciseSession] {
        guard HKHealthStore.isHealthDataAvailable(), !userID.isEmpty else { return [] }
        let owner = UUID(uuidString: userID)?.uuidString ?? userID
        let predicate = HKQuery.predicateForObjects(withMetadataKey: "net.impx.moment.owner", allowedValues: [owner])
        let samples: [HKSample] = await withCheckedContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in continuation.resume(returning: samples ?? []) })
        }
        return samples.compactMap { sample in
            guard let workout = sample as? HKWorkout, workout.metadata?["net.impx.moment.delivery"] as? String != "watch-connectivity", let text = workout.metadata?["net.impx.moment.record"] as? String,
                  let data = text.data(using: .utf8), let record = try? ExerciseSession.syncDecoder().decode(ExerciseSession.self, from: data), record.endedAt != nil else { return nil }
            return record
        }
    }
}

struct ActivityExerciseRecords: View {
    @EnvironmentObject private var family: FamilyStore
    let activityID: String
    @State private var records: [ExerciseSession] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(records) { record in
                HStack {
                    Label("\(record.kind) · \(record.distanceText) · \(ExerciseSession.clock(record.duration(at: record.endedAt ?? .now)))", systemImage: "figure.hiking")
                    if record.endedAt != nil {
                        Button(String(localized: "继续", bundle: AgentIdentityLanguage.appBundle())) { family.pendingExerciseContinuation = record.id }.buttonStyle(.borderless)
                    } else { Text(record.running ? String(localized: "进行中", bundle: AgentIdentityLanguage.appBundle()) : String(localized: "已暂停", bundle: AgentIdentityLanguage.appBundle())) }
                }.font(.caption).foregroundStyle(.teal)
            }
        }.task { reload() }.onReceive(NotificationCenter.default.publisher(for: .exerciseRecordsChanged)) { _ in reload() }
    }
    private func reload() {
        guard let id = UUID(uuidString: activityID), let owner = family.profile?.text("unifiedUserId"), !owner.isEmpty else { records = []; return }
        let hash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        let url = ExerciseSession.archiveURL(userID: hash)
        guard let data = try? Data(contentsOf: url), let archive = try? ExerciseSession.syncDecoder().decode(ExerciseArchive.self, from: data) else { records = []; return }
        records = ([archive.active].compactMap { $0 } + archive.history).filter { $0.activity?.id == id }
    }
}


struct ActivityExerciseTimelineRow: View {
    let record: ExerciseSession
    let onContinue: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(exerciseKindTitle(record.kind), systemImage: "figure.hiking").font(.headline)
            Text(record.startedAt, style: .date).font(.caption).foregroundStyle(.secondary)
            Text(record.startedAt, style: .time).font(.caption).foregroundStyle(.secondary)
            Text("\(record.distanceText) · \(ExerciseSession.clock(record.duration(at: record.endedAt ?? .now)))")
            if record.endedAt == nil {
                Text(record.running ? String(localized: "进行中", bundle: AgentIdentityLanguage.appBundle()) : String(localized: "已暂停", bundle: AgentIdentityLanguage.appBundle())).font(.caption).foregroundStyle(.teal)
            }
            if !record.routePoints.isEmpty {
                NavigationLink {
                    ExerciseRouteReplay(points: record.routePoints)
                        .navigationTitle(exerciseKindTitle(record.kind))
                } label: { Label(String(localized: "查看完整轨迹", bundle: AgentIdentityLanguage.appBundle()), systemImage: "map") }
            }
            if record.endedAt != nil {
                Button(String(localized: "继续", bundle: AgentIdentityLanguage.appBundle()), action: onContinue).buttonStyle(.borderless)
            }
        }.padding(.vertical, 6)
    }
}


struct ExerciseWatchConnectionView: View {
    @ObservedObject var family: FamilyStore
    @Environment(\.openURL) private var openURL
    @State private var scanningLogin = false
    @State private var loginApprovalURL: URL?
    @StateObject private var health = ExerciseHealth()
    var body: some View {
        List {
            Section {
                Button { scanningLogin = true } label: { Label(String(localized: "扫码登录", bundle: AgentIdentityLanguage.appBundle()), systemImage: "qrcode.viewfinder") }
                    .sheet(isPresented: $scanningLogin, onDismiss: {
                        if let url = loginApprovalURL { loginApprovalURL = nil; openURL(url) }
                    }) {
                        WatchCodeScanner(loginOrigin: URL(string: "https://happylife.ai.impx.net")!) { payload in loginApprovalURL = URL(string: payload) }
                    }
            }
                Section(String(localized: "健康与手表", bundle: AgentIdentityLanguage.appBundle())) {
                    if !family.watchExerciseMetrics.isEmpty {
                        Text(String(localized: "手表运动数据", bundle: AgentIdentityLanguage.appBundle())).font(.headline)
                        if let updated = family.watchMetricsUpdatedAt { Text(updated, style: .time).font(.caption).foregroundStyle(.secondary) }
                        if let value = family.watchExerciseMetrics["heart"] { Text(String(format: String(localized: "心率 %.0f 次/分", bundle: AgentIdentityLanguage.appBundle()), value)) }
                        if let value = family.watchExerciseMetrics["energy"] { Text(String(format: String(localized: "活动能量 %.0f 千卡", bundle: AgentIdentityLanguage.appBundle()), value)) }
                        if let value = family.watchExerciseMetrics["distance"] { Text(String(format: String(localized: "距离 %.2f 公里", bundle: AgentIdentityLanguage.appBundle()), value / 1000)) }
                    }
                    Button(String(localized: "连接 Apple 健康与手表数据", bundle: AgentIdentityLanguage.appBundle())) { Task { await refresh(request: true) } }
                    if let status = health.message { Text(status).font(.caption).foregroundStyle(.secondary) }
                    if let value = health.steps { Text(String(format: String(localized: "%.0f 步", bundle: AgentIdentityLanguage.appBundle()), value)) }
                    if let value = health.distance { Text(String(format: String(localized: "距离 %.2f 公里", bundle: AgentIdentityLanguage.appBundle()), value / 1000)) }
                    if let heart = health.heartRate { Text(String(format: String(localized: "平均心率 %.0f 次/分", bundle: AgentIdentityLanguage.appBundle()), heart)) }
                    if let energy = health.energy { Text(String(format: String(localized: "活动能量 %.0f 千卡", bundle: AgentIdentityLanguage.appBundle()), energy)) }
                    Text(String(localized: "健康数据由系统授权读取。手表运动保存后同步到 iPhone；未授权或尚未同步时不显示测量值。", bundle: AgentIdentityLanguage.appBundle())).font(.caption).foregroundStyle(.secondary)
                }
        }
        .navigationTitle(String(localized: "连接手表", bundle: AgentIdentityLanguage.appBundle()))
        .task { await refresh() }
    }
    private func refresh(request: Bool = false) async {
        guard let owner = family.profile?.text("unifiedUserId"), !owner.isEmpty else { return }
        let exercise = ExerciseStore.shared(userID: owner)
        exercise.connect(family)
        if request { await health.authorize() }
        let records = await health.watchRecords(userID: owner)
        guard family.profile?.text("unifiedUserId") == owner else { return }
        exercise.importWatchRecords(records)
        await exercise.sync()
        if let record = exercise.active ?? exercise.history.first { await health.read(record) }
    }
}

@MainActor private final class HikingLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var failed = false
    private let manager = CLLocationManager()
    override init() { super.init(); manager.delegate = self }
    func locate() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: failed = true
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { coordinate = locations.last?.coordinate }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { failed = true }
}

private struct HikingPlacesView: View {
    @Environment(\.openURL) private var openURL
    let family: FamilyStore
    @StateObject private var location = HikingLocation()
    @State private var places: [HikingPlace] = []
    @State private var message = ""
    @State private var busy = false
    @State private var importing = false
    @State private var imported: [[CLLocationCoordinate2D]] = []
    @State private var highest: Double?
    private struct HikingPlace: Decodable, Identifiable {
        let id: String; let name: String; let address: String
        let latitude: Double; let longitude: Double; let distanceMeters: Double
    }
    var body: some View {
        List {
            Section {
                Text(String(localized: "地点搜索不代表开放或允许攀登；海拔、路面和登顶时长需核实。", bundle: AgentIdentityLanguage.appBundle()))
                Button(String(localized: "定位搜索附近的山（30公里）", bundle: AgentIdentityLanguage.appBundle())) { location.locate() }
                Button(String(localized: "导入 GPX 路线", bundle: AgentIdentityLanguage.appBundle())) { importing = true }
                if busy { ProgressView() }
                if !message.isEmpty { Text(message) }
                if location.failed { Text(String(localized: "无法定位，请检查定位权限后重试。", bundle: AgentIdentityLanguage.appBundle())) }
            }
            if !imported.isEmpty {
                Section(String(localized: "导入路线预览 · WGS84", bundle: AgentIdentityLanguage.appBundle())) {
                    Map {
                        ForEach(imported.indices, id: \.self) { index in MapPolyline(coordinates: imported[index]).stroke(.teal, lineWidth: 4) }
                    }.frame(height: 320)
                    if let highest { Text(String(format: String(localized: "文件中的最高海拔：%.0f 米，不等于山峰高度", bundle: AgentIdentityLanguage.appBundle()), highest)) }
                    Text(String(localized: "路线只作预览，不计入运动记录。路面和预计时长需向发布者核实。", bundle: AgentIdentityLanguage.appBundle()))
                }
            }
            ForEach(places) { place in
                Section(place.name) {
                    Text(place.address)
                    Text(String(format: String(localized: "直线距离约 %.1f 公里", bundle: AgentIdentityLanguage.appBundle()), place.distanceMeters / 1000))
                    Text(String(localized: "海拔：未核实 · 台阶/山路：未核实 · 登山时长：未核实", bundle: AgentIdentityLanguage.appBundle()))
                    Button(String(localized: "高德查看位置并导航", bundle: AgentIdentityLanguage.appBundle())) {
                        var url = URLComponents(string: "https://uri.amap.com/navigation")!
                        url.queryItems = [URLQueryItem(name: "to", value: "\(place.longitude),\(place.latitude),\(place.name)"), URLQueryItem(name: "mode", value: "car"), URLQueryItem(name: "coordinate", value: "gaode")]
                        if let url = url.url { openURL(url) }
                    }
                    Button(String(localized: "查看周边景点（5公里）", bundle: AgentIdentityLanguage.appBundle())) { Task { await search(latitude: place.latitude, longitude: place.longitude, scenic: true) } }
                }
            }
            Text(String(localized: "地点来源：高德地图 · 不代表登山路线推荐", bundle: AgentIdentityLanguage.appBundle()))
        }.navigationTitle(String(localized: "爬山", bundle: AgentIdentityLanguage.appBundle())).disabled(busy)
            .onReceive(location.$coordinate) { coordinate in
                if let point = coordinate { Task { await search(latitude: point.latitude, longitude: point.longitude) } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first, url.pathExtension.lowercased() == "gpx" else { return }
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 5_000_000 else { throw CocoaError(.fileReadTooLarge) }
                    let data = try Data(contentsOf: url); guard data.count <= 5_000_000 else { throw CocoaError(.fileReadTooLarge) }
                    let reader = HikingGPXReader(); let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = reader
                    guard !String(decoding: data, as: UTF8.self).uppercased().contains("<!DOCTYPE"), parser.parse(), !reader.failed, reader.segments.flatMap({ $0 }).count >= 2 else { throw CocoaError(.fileReadCorruptFile) }
                    imported = reader.segments; highest = reader.highest; message = String(localized: "GPX 已导入，仅保留在本次预览中。", bundle: AgentIdentityLanguage.appBundle())
                } catch { message = String(localized: "无法导入，请选择有效 GPX 文件（最多500万字节、2万个点）。", bundle: AgentIdentityLanguage.appBundle()) }
            }
    }
    @MainActor private func search(latitude: Double, longitude: Double, scenic: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            struct Response: Decodable { let places: [HikingPlace] }
            let result = try await family.call("/api/hiking/nearby", method: "POST", body: ["latitude": latitude, "longitude": longitude, "scenic": scenic])
            places = try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: result)).places
            message = places.isEmpty ? String(localized: "附近暂未找到结果。", bundle: AgentIdentityLanguage.appBundle()) : String(localized: "地点来源：高德地图", bundle: AgentIdentityLanguage.appBundle())
        } catch { message = String(localized: "地点查询失败，请检查网络及地图服务配置后重试。", bundle: AgentIdentityLanguage.appBundle()) }
    }
}

private final class HikingGPXReader: NSObject, XMLParserDelegate {
    var segments: [[CLLocationCoordinate2D]] = []; var highest: Double?; var failed = false
    private var segment: [CLLocationCoordinate2D] = []; private var active = false; private var count = 0
    private var point: CLLocationCoordinate2D?; private var elevation = false; private var text = ""
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if element == "trkseg" || element == "rte" { active = true; segment = [] }
        if active && (element == "trkpt" || element == "rtept") {
            guard let lat = Double(attributes["lat"] ?? ""), let lon = Double(attributes["lon"] ?? ""), lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180, count < 20000 else { failed = true; parser.abortParsing(); return }
            point = CLLocationCoordinate2D(latitude: lat, longitude: lon); count += 1
        }
        if element == "ele" && point != nil { elevation = true; text = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if elevation { text += string } }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName qName: String?) {
        if element == "ele" && elevation { if let value = Double(text), value.isFinite, abs(value) < 20000 { highest = max(highest ?? value, value) }; elevation = false }
        if element == "trkpt" || element == "rtept" { if let point { segment.append(point) }; point = nil }
        if element == "trkseg" || element == "rte" { if !segment.isEmpty { segments.append(segment) }; active = false }
    }
}

private struct ExerciseFriendShareView: View {
    private struct Track: Decodable, Identifiable {
        let id: Int
        let name: String
        let points: [ExerciseRoutePoint]
        var color: Color {
            let colors: [Color] = [.blue, .orange, .purple, .green, .red, .cyan, .indigo, .mint, .pink, .brown, .teal, .gray]
            return colors[id >= 0 ? id % colors.count : 0]
        }
    }

    private struct Board: Decodable {
        let kind: String
        let workoutId: UUID?
        let isOwner: Bool
        let tracks: [Track]
    }

    @ObservedObject var exercise: ExerciseStore
    let family: FamilyStore
    let workout: ExerciseSession?
    var invitation: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var code: UUID?
    @State private var board: Board?
    @State private var hidden = Set<Int>()
    @State private var busy = false
    @State private var error = ""
    @State private var camera: MapCameraPosition = .automatic

    private var path: String { "/api/exercise/shares" }
    private var name: String {
        let username = family.profile?.text("username") ?? ""
        let nickname = family.profile?.text("displayName") ?? ""
        let label = nickname.isEmpty ? username : nickname
        return label.isEmpty ? String(localized: "活动成员", bundle: AgentIdentityLanguage.appBundle()) : String(label.prefix(100))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let board {
                    Text(exerciseKindTitle(board.kind)).font(.headline)
                    trackMap(board)
                    if board.workoutId == nil {
                        Button(String(localized: "加入并记录轨迹", bundle: AgentIdentityLanguage.appBundle())) {
                            perform {
                                guard let code, exercise.active == nil else { return }
                                try await exercise.joinFriendShare(code, kind: board.kind, name: name)
                                try await refresh(code)
                            }
                        }.buttonStyle(.borderedProminent).disabled(busy || exercise.active != nil)
                    }
                    if let code, let workoutID = board.workoutId {
                        if board.isOwner {
                            ShareLink(item: WorkoutInvitation.url(for: code)) {
                                Label(String(localized: "分享运动", bundle: AgentIdentityLanguage.appBundle()), systemImage: "square.and.arrow.up")
                            }.buttonStyle(.bordered)
                        }
                        Button(board.isOwner ? String(localized: "停止共享", bundle: AgentIdentityLanguage.appBundle()) : String(localized: "退出共享", bundle: AgentIdentityLanguage.appBundle()), role: .destructive) {
                            perform {
                                let suffix = board.isOwner ? "" : "/member"
                                _ = try await family.call(path + "/\(code.uuidString)" + suffix, method: "DELETE")
                                exercise.clearFriendShare(for: workoutID)
                                self.code = nil
                                self.board = nil
                            }
                        }.disabled(busy)
                    }
                } else {
                    if let workout {
                        Button(String(localized: "创建运动分享", bundle: AgentIdentityLanguage.appBundle())) {
                            perform {
                                let response = try await family.call(path, method: "POST", body: [
                                    "kind": workout.kind, "name": name, "workoutId": workout.id.uuidString
                                ]) as? [String: Any]
                                guard let value = response?["code"] as? String, let id = UUID(uuidString: value) else { throw CocoaError(.coderReadCorrupt) }
                                exercise.bindFriendShare(id, to: workout.id)
                                code = id
                                try await refresh(id)
                                try await exercise.uploadFriendTrack(current(workout), code: id)
                            }
                        }.buttonStyle(.borderedProminent).disabled(busy)
                    }
                    TextField(String(localized: "好友运动邀请码", bundle: AgentIdentityLanguage.appBundle()), text: $input)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button(String(localized: "仅查看", bundle: AgentIdentityLanguage.appBundle())) {
                        guard let id = UUID(uuidString: input.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                        perform {
                            try await refresh(id)
                            code = id
                        }
                    }.buttonStyle(.bordered).disabled(busy || UUID(uuidString: input.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                    Spacer()
                }
                if (workout != nil && board == nil) || (board?.workoutId == nil && board != nil) {
                    Text(String(localized: "创建或加入后，持有邀请码并已登录的人可以查看你的运动轨迹。", bundle: AgentIdentityLanguage.appBundle()))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let status = error.isEmpty ? nil : error {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }.padding()
            .navigationTitle(String(localized: "好友运动", bundle: AgentIdentityLanguage.appBundle()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成", bundle: AgentIdentityLanguage.appBundle())) { dismiss() }
                }
            }
            .task(id: invitation) {
                if let invitation {
                    hidden.removeAll()
                    board = nil
                    code = invitation
                    input = invitation.uuidString
                } else if let workout, let saved = exercise.friendShare(for: workout.id) { code = saved }
            }
            .task(id: code) {
                guard let code else { return }
                while !Task.isCancelled {
                    do {
                        try await refresh(code)
                        error = ""
                    } catch is CancellationError { return }
                    catch let APIError.http(status, _) where status == 404 {
                        error = String(localized: "运动分享已失效", bundle: AgentIdentityLanguage.appBundle())
                        if let workout, exercise.friendShare(for: workout.id) == code { exercise.clearFriendShare(for: workout.id) }
                        board = nil
                        self.code = nil
                        return
                    } catch { self.error = error.localizedDescription }
                    do { try await Task.sleep(for: .seconds(12)) } catch { return }
                }
            }
        }
    }

    private func current(_ fallback: ExerciseSession) -> ExerciseSession {
        if let active = exercise.active, active.id == fallback.id { return active }
        return exercise.history.first { $0.id == fallback.id } ?? fallback
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = ""
        Task {
            defer { busy = false }
            do { try await operation() }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func refresh(_ code: UUID) async throws {
        let raw = try await family.call(path + "/\(code.uuidString)", timeout: 10)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let next = try decoder.decode(Board.self, from: JSONSerialization.data(withJSONObject: raw))
        try Task.checkCancellation()
        board = next
    }

    private func trackMap(_ board: Board) -> some View {
        Map(position: $camera) {
            ForEach(board.tracks.filter { !hidden.contains($0.id) }) { track in
                ForEach(segments(track), id: \.id) { segment in
                    if segment.points.count > 1 {
                        MapPolyline(coordinates: segment.points.map(coordinate)).stroke(track.color, lineWidth: 4)
                    }
                }
                if let point = track.points.last {
                    Marker(track.name, systemImage: "location.fill", coordinate: coordinate(point)).tint(track.color)
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .top) {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(board.tracks) { track in
                            let shown = !hidden.contains(track.id)
                            Button {
                                if shown { hidden.insert(track.id) } else { hidden.remove(track.id) }
                                camera = .automatic
                            } label: {
                                Label(track.name, systemImage: shown ? "circle.fill" : "circle")
                                    .foregroundStyle(shown ? track.color : .secondary)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 8).padding(.vertical, 7)
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(shown ? .isSelected : [])
                        }
                    }.padding(.horizontal, 8)
                }.scrollIndicators(.hidden).background(.regularMaterial)
            }
    }

    private struct ShareSegment {
        let id: UUID
        let points: [ExerciseRoutePoint]
    }

    private func segments(_ track: Track) -> [ShareSegment] {
        Dictionary(grouping: track.points, by: \.segment).map { ShareSegment(id: $0.key, points: $0.value) }
    }

    private func coordinate(_ point: ExerciseRoutePoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }
}

struct ExerciseActivityEditor: View {
    let store: FamilyStore
    let scope: UUID?
    let selected: UUID?
    let workoutKind: String?
    let save: (ExerciseActivity?, String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var targets: [ExerciseActivity] = []
    @State private var selection: UUID?
    @State private var kind = ""
    @State private var loading = true
    @State private var saving = false
    @State private var error = ""

    private var choices: [String] { ["散步", "慢跑", "徒步", "爬山", "滑雪", "飞行", "自由运动"] }

    var body: some View {
        NavigationStack {
            Form {
                if let workoutKind {
                    Picker(String(localized: "运动类型", bundle: AgentIdentityLanguage.appBundle()), selection: $kind) {
                        ForEach(choices.contains(workoutKind) ? choices : choices + [workoutKind], id: \.self) {
                            Text(exerciseKindTitle($0)).tag($0)
                        }
                    }
                }
                Section(String(localized: "所属活动", bundle: AgentIdentityLanguage.appBundle())) {
                    if loading { ProgressView() }
                    if !targets.isEmpty {
                        Picker(String(localized: "所属活动", bundle: AgentIdentityLanguage.appBundle()), selection: $selection) {
                            if selected == nil {
                                Text(String(localized: "未关联活动", bundle: AgentIdentityLanguage.appBundle())).tag(nil as UUID?)
                            }
                            ForEach(targets) { Text($0.title).tag(Optional($0.id)) }
                        }.labelsHidden()
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(workoutKind == nil
                ? String(localized: "更改所属活动", bundle: AgentIdentityLanguage.appBundle())
                : String(localized: "修改运动", bundle: AgentIdentityLanguage.appBundle()))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", bundle: AgentIdentityLanguage.appBundle())) { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存", bundle: AgentIdentityLanguage.appBundle())) {
                        saving = true
                        Task {
                            defer { saving = false }
                            do {
                                try await save(targets.first { $0.id == selection }, workoutKind == nil ? nil : kind)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(saving || loading || (selection == selected && (workoutKind == nil || kind == workoutKind)) ||
                               (selection != nil && !targets.contains { $0.id == selection }))
                }
            }
            .task {
                selection = selected
                kind = workoutKind ?? ""
                var local = store.localExerciseActivities(scope: scope)
                if let owner = store.profile?.text("unifiedUserId"), !owner.isEmpty {
                    let exercise = ExerciseStore.shared(userID: owner)
                    let linked = exercise.history.compactMap(\.activity) + [exercise.active?.activity].compactMap { $0 }
                    local += linked.filter { scope == nil || $0.tenantID == scope }
                }
                var byID: [UUID: ExerciseActivity] = [:]
                for activity in local { byID[activity.id] = activity }
                targets = byID.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                loading = false
                do {
                    let rows = try await store.call("/api/dear/social/activities/joined") as? [[String: Any]] ?? []
                    let remote = rows.compactMap { row -> ExerciseActivity? in
                        guard let tenant = (row["sourceTenantId"] as? String).flatMap(UUID.init(uuidString:)),
                              scope == nil || scope == tenant,
                              let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                              let title = row["title"] as? String else { return nil }
                        return ExerciseActivity(tenantID: tenant, id: id, title: title)
                    }
                    for activity in remote { byID[activity.id] = activity }
                    targets = byID.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                } catch {
                    if targets.isEmpty { self.error = error.localizedDescription }
                }
            }
        }
    }
}
