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

    func start(kind: String, map: Bool, activity: ExerciseActivity? = nil) {
        guard readable, active == nil, !busy else { return }
        let now = Date()
        archive.active = ExerciseSession(kind: kind, startedAt: now, intervals: [ExerciseInterval(start: now)], activity: activity, routeEnabled: map)
        save(); observe(); updateLocationTracking()
    }
    func continueRecord(_ record: ExerciseSession) {
        guard readable, active == nil, !busy, history.contains(where: { $0.id == record.id }) else { return }
        archive.active = record.continuation(at: Date())
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
    func accountDidChange() { api = nil; stopLocationTracking(); stopObserving(); Self.stores.removeValue(forKey: userID) }
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
        guard tracking, active?.running == true, active?.routeEnabled == true else { return }
        var changed = false
        for location in locations {
            let age = Date().timeIntervalSince(location.timestamp)
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 65, age >= -5, age <= 15,
                  location.timestamp > lastLocationAt else { continue }
            if let previous = lastLocation {
                let dt = location.timestamp.timeIntervalSince(previous.timestamp)
                if dt > 60 { routeSegment = UUID(); lastLocation = nil }
                else if dt < 3 || location.distance(from: previous) < 3 || location.distance(from: previous) / dt > 20 { continue }
            }
            let point = ExerciseRoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                recordedAt: location.timestamp, segment: routeSegment,
                altitudeMeters: location.verticalAccuracy >= 0 && location.altitude.isFinite ? location.altitude : nil,
                verticalAccuracyMeters: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil)
            if archive.active?.appendRoute(point) == true {
                lastLocation = location; lastLocationAt = location.timestamp; changed = true
                locationMessage = String(localized: "正在记录轨迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
            }
        }
        if changed { save(sensorUpdate: true) }
        else if let last = locations.last, last.horizontalAccuracy > 65 { locationMessage = String(localized: "定位精度不足，可在系统设置中开启精确位置。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
        if (active?.route?.count ?? 0) >= 20_000 { stopLocationTracking(); locationMessage = String(localized: "本次轨迹已达记录上限，计时与计步继续。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
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
            var remote: [UUID: Bool] = [:]; var cursor: String?
            repeat {
                let page = try await api.call("/api/exercise/records" + (cursor.map { "?after=" + $0 } ?? "")) as? [String: Any] ?? [:]
                guard DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID) else { return }
                for entry in page["records"] as? [[String: Any]] ?? [] {
                    if let raw = entry["id"] as? String, let id = UUID(uuidString: raw) { remote[id] = entry["deleted"] as? Bool ?? false }
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
            for record in archive.history where remote[record.id] == nil || !(archive.uploaded ?? []).contains(record.id) {
                guard !(archive.pendingDeletions ?? []).contains(record.id) else { continue }
                let body = try JSONSerialization.jsonObject(with: encoder.encode(record)) as! [String: Any]
                _ = try await api.call("/api/exercise/records/\(record.id.uuidString)", method: "PUT", body: body)
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
            for record in archive.history where record.activity != nil && archive.activityShares?[record.id] == nil {
                guard let linked = record.activity, !(archive.pendingDeletions ?? []).contains(record.id), DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID) else { continue }
                do {
                let response = try await api.call("/api/dear/social/tenants/\(linked.tenantID.uuidString)/activities/\(linked.id.uuidString)/moments", method: "POST", body: ["text": record.activitySummary, "requestId": record.id.uuidString, "recordedAt": ISO8601DateFormatter().string(from: record.startedAt)]) as? [String: Any] ?? [:]
                guard DiningAccount.identity(api.profile?.text("unifiedUserId") ?? "") == DiningAccount.identity(userID) else { return }
                guard let raw = response["id"] as? String, let id = UUID(uuidString: raw) else { throw APIError.message(String(localized: "活动动态未返回有效记录标识。", bundle: AgentIdentityLanguage.appBundle())) }
                if archive.activityShares == nil { archive.activityShares = [:] }; archive.activityShares?[record.id] = id; save()
                NotificationCenter.default.post(name: .exerciseActivityPublished, object: nil)
                } catch { activityShareError = String(localized: "运动已同步，活动动态待重试：\(error.localizedDescription)", bundle: AgentIdentityLanguage.appBundle()) }
            }
            archive.history.sort { $0.startedAt > $1.startedAt }; save(); syncMessage = activityShareError ?? String(localized: "已同步到当前账号", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        } catch is CancellationError { }
        catch { syncMessage = String(localized: "同步未完成，本机记录已保留：\(error.localizedDescription)", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }

    private func observe() {
        stopObserving()
        guard let active, active.running, let index = active.intervals.indices.last else { return }
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
        guard let active, supported else { return }
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
    @State private var mapMode = false
    @State private var selectedRoute: ExerciseSession?
    @State private var kind = "散步"
    @State private var activity: ExerciseActivity?
    @State private var confirmFinish = false
    @State private var pendingDeletion: ExerciseSession?
    init(userID: String) { _exercise = StateObject(wrappedValue: ExerciseStore.shared(userID: userID)) }

    var body: some View {
        NavigationStack {
            List {
                if let linked = exercise.active?.activity ?? activity {
                    Section(String(localized: "关联活动", bundle: AgentIdentityLanguage.appBundle())) {
                        Text(linked.title)
                        if exercise.active == nil {
                            Button(String(localized: "取消关联", bundle: AgentIdentityLanguage.appBundle())) { activity = nil; family.watchExerciseActivity = nil }
                        }
                    }
                }
                Section {
                    Picker(String(localized: "显示模式", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $mapMode) {
                        Label(String(localized: "数据", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "figure.walk").tag(false)
                        Label(String(localized: "地图", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "map").tag(true)
                    }.pickerStyle(.segmented)
                    if mapMode {
                        ExerciseRouteMap(points: exercise.active?.routePoints ?? [], live: exercise.active?.running == true)
                            .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 14))
                        if let message = exercise.locationMessage, exercise.active != nil {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section(exercise.active.map { exerciseKindTitle($0.kind) } ?? String(localized: "开始运动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    if let active = exercise.active {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 12) {
                                Text(ExerciseSession.clock(active.duration(at: context.date)))
                                    .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                                    .accessibilityLabel(String(localized: "运动时长", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                Text(active.distanceMeters == nil && !exercise.distanceSupported ? String(localized: "此设备不支持距离估算", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : exerciseDistanceTitle(active))
                                    .font(.title.bold()).monospacedDigit()
                                    .accessibilityLabel(String(localized: "运动距离，\(exerciseDistanceTitle(active))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                Text(active.steps.map { String(localized: "\($0) 步", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) } ?? String(localized: "步数待获取", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                    .font(.title2).monospacedDigit()
                                if let altitude = active.routePoints.last?.altitudeMeters { Text(String(format: String(localized: "海拔 %.1f 米", bundle: AgentIdentityLanguage.appBundle()), altitude)).font(.subheadline) }
                                Text(active.running ? String(localized: "运动中", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "已暂停", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).foregroundStyle(active.running ? .teal : .secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 18)
                        }
                        HStack {
                            Button(active.running ? String(localized: "暂停", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "继续", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                                if active.running { Task { await exercise.pause() } } else { exercise.resume() }
                            }.buttonStyle(.borderedProminent)
                            Spacer()
                            Button(String(localized: "结束并保存", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { confirmFinish = true }.buttonStyle(.bordered)
                        }.disabled(exercise.busy)
                    } else {
                        Picker(String(localized: "运动项目", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), selection: $kind) {
                            Text(String(localized: "散步", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("散步"); Text(String(localized: "慢跑", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("慢跑"); Text(String(localized: "自由运动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).tag("自由运动")
                            Text(String(localized: "徒步", bundle: AgentIdentityLanguage.appBundle())).tag("徒步")
                            Text(String(localized: "爬山", bundle: AgentIdentityLanguage.appBundle())).tag("爬山")
                        }.pickerStyle(.menu)
                        if kind == "爬山" { NavigationLink(String(localized: "附近山峰与导入路线", bundle: AgentIdentityLanguage.appBundle())) { HikingPlacesView(family: family) } }
                        Button {
                            exercise.start(kind: kind, map: mapMode, activity: activity)
                            if exercise.active != nil { activity = nil; family.watchExerciseActivity = nil }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill").accessibilityHidden(true)
                                Text(String(localized: "开始\(exerciseKindTitle(kind))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                                    .multilineTextAlignment(.center)
                                Image(systemName: "play.fill").hidden().accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent)
                    }
                    Text(String(localized: "距离由系统计步估算。地图模式使用 GPS 记录轨迹，暂停时停止定位。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message = exercise.message {
                    Section(String(localized: "提示", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                        Text(message).font(.footnote)
                        Button(String(localized: "重试读取步数与距离", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await exercise.refresh() } }
                        Button(String(localized: "重试保存记录", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { exercise.retrySave() }
                        Button(String(localized: "打开系统设置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }
                }
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
                            Button(String(localized: "继续\(item.kind)", bundle: AgentIdentityLanguage.appBundle())) { exercise.continueRecord(item) }.buttonStyle(.borderless).disabled(exercise.active != nil || exercise.busy)
                            if let linked = item.activity { Text(linked.title).font(.subheadline).foregroundStyle(.secondary) }
                            Text(exerciseDistanceTitle(item)).font(.headline).monospacedDigit()
                            if let altitude = item.altitudeRange { Text(String(format: String(localized: "海拔 %.1f–%.1f 米", bundle: AgentIdentityLanguage.appBundle()), altitude.lowerBound, altitude.upperBound)).font(.caption) }
                            if !item.routePoints.isEmpty {
                                Button { selectedRoute = item } label: { Label(String(localized: "查看轨迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "map") }.buttonStyle(.borderless)
                            }
                            HStack {
                                Text(item.startedAt, format: .dateTime.year().month().day().hour().minute())
                                Spacer()
                                Text(item.steps.map { String(localized: "\($0) 步", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) } ?? String(localized: "步数未获取", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
                            }.font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                            .swipeActions(allowsFullSwipe: false) {
                                Button(String(localized: "删除", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), role: .destructive) { pendingDeletion = item }
                                    .disabled(exercise.busy)
                            }
                    }
                } header: { Text(String(localized: "运动记录 · 当地时间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) } footer: { Text(String(localized: "运动记录及轨迹仅同步到当前账号。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            }.navigationTitle(String(localized: "运动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).readablePage()
                .confirmationDialog(String(localized: "结束本次运动并保存记录？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), isPresented: $confirmFinish, titleVisibility: .visible) {
                    Button(String(localized: "结束并保存", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await exercise.finish() } }
                }
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
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        if exercise.syncing { ProgressView().controlSize(.small) }
                        Text(exercise.syncMessage ?? String(localized: "完成运动后自动同步", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        Button(String(localized: "同步", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await exercise.sync() } }.disabled(exercise.syncing)
                    }.padding(.horizontal).padding(.vertical, 8).background(.bar)
                }
                .sheet(item: $selectedRoute) { item in
                    NavigationStack {
                        ExerciseRouteMap(points: item.routePoints, live: false)
                            .navigationTitle(exerciseKindTitle(item.kind))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { selectedRoute = nil } } }
                    }
                }
                .task {
                    exercise.connect(family)
                    mapMode = exercise.active?.routeEnabled == true
                    receiveActivity()
                    if let id = family.pendingExerciseContinuation, let record = exercise.history.first(where: { $0.id == id }) { exercise.continueRecord(record); family.pendingExerciseContinuation = nil }
                    await exercise.refresh(); await refreshHealth()
                }
                .onChange(of: family.pendingExerciseContinuation) { _, value in
                    if let id = value, let record = exercise.history.first(where: { $0.id == id }) { exercise.continueRecord(record); family.pendingExerciseContinuation = nil }
                }
                .onChange(of: family.pendingExerciseActivity) { _, _ in receiveActivity() }
                .onChange(of: family.profile?.text("unifiedUserId")) { _, _ in activity = nil; exercise.accountDidChange() }
                .onChange(of: mapMode) { _, value in if value { exercise.enableRoute() } }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await exercise.refresh(); await refreshHealth() } }
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
        mapMode = true
    }

}

private func exerciseKindTitle(_ value: String) -> String {
    let locale = Locale(identifier: AgentIdentityLanguage.current)
    switch value {
    case "爬山": return String(localized: "爬山", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
    case "散步": return String(localized: "散步", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
    case "徒步": return String(localized: "徒步", bundle: AgentIdentityLanguage.appBundle())
    case "慢跑": return String(localized: "慢跑", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
    case "自由运动": return String(localized: "自由运动", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
    default: return value
    }
}


private struct ExerciseRouteMap: View {
    let points: [ExerciseRoutePoint]
    let live: Bool
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
    }
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
                    ExerciseRouteMap(points: record.routePoints, live: record.endedAt == nil)
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
