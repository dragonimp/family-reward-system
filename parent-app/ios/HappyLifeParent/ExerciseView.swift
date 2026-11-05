import AgentIdentity
import SwiftUI
import CoreMotion
import CryptoKit
import MapKit
import CoreLocation

@MainActor final class ExerciseStore: NSObject, ObservableObject, CLLocationManagerDelegate {
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

    private func save() {
        guard readable else { return }
        do {
            try archive.write(to: file)
        } catch { message = String(localized: "运动记录尚未保存：\(error.localizedDescription)。请保留页面并重试保存。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }
    func retrySave() { guard readable else { return }; message = nil; save() }

    func deleteRecord(id: UUID) {
        guard readable, !busy, archive.history.contains(where: { $0.id == id }) else { return }
        do { try archive.deleteHistoryRecord(id: id, file: file)
            Task { await sync() } }
        catch {
            message = String(localized: "删除失败，运动记录已保留，请稍后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        }
    }

    func start(kind: String, map: Bool) {
        guard readable, active == nil, !busy else { return }
        let now = Date()
        archive.active = ExerciseSession(kind: kind, startedAt: now, intervals: [ExerciseInterval(start: now)], routeEnabled: map)
        save(); observe(); updateLocationTracking()
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

    func connect(_ store: FamilyStore) { api = store }
    func accountDidChange() { api = nil; stopLocationTracking(); stopObserving() }
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
                recordedAt: location.timestamp, segment: routeSegment)
            if archive.active?.appendRoute(point) == true {
                lastLocation = location; lastLocationAt = location.timestamp; changed = true
                locationMessage = String(localized: "正在记录轨迹", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
            }
        }
        if changed { save() }
        else if let last = locations.last, last.horizontalAccuracy > 65 { locationMessage = String(localized: "定位精度不足，可在系统设置中开启精确位置。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
        if (active?.route?.count ?? 0) >= 20_000 { stopLocationTracking(); locationMessage = String(localized: "本次轨迹已达记录上限，计时与计步继续。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { locationMessage = String(localized: "正在获取 GPS 信号", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return }
        locationMessage = String(localized: "定位暂不可用，请检查系统定位权限。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
    }
    func sync() async {
        guard readable, let api, !userID.isEmpty, api.profile?.text("unifiedUserId") == userID else { return }
        if syncing { syncAgain = true; return }
        syncing = true; syncMessage = nil
        defer {
            syncing = false
            if syncAgain { syncAgain = false; Task { await sync() } }
        }
        do {
            for id in archive.pendingDeletions ?? [] {
                _ = try await api.call("/api/exercise/records/\(id.uuidString)", method: "DELETE")
                guard api.profile?.text("unifiedUserId") == userID else { return }
                archive.pendingDeletions?.removeAll { $0 == id }; save()
            }
            var remote: [UUID: Bool] = [:]; var cursor: String?
            repeat {
                let page = try await api.call("/api/exercise/records" + (cursor.map { "?after=" + $0 } ?? "")) as? [String: Any] ?? [:]
                guard api.profile?.text("unifiedUserId") == userID else { return }
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
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            for record in archive.history where remote[record.id] == nil || !(archive.uploaded ?? []).contains(record.id) {
                guard !(archive.pendingDeletions ?? []).contains(record.id) else { continue }
                let body = try JSONSerialization.jsonObject(with: encoder.encode(record)) as! [String: Any]
                _ = try await api.call("/api/exercise/records/\(record.id.uuidString)", method: "PUT", body: body)
                guard api.profile?.text("unifiedUserId") == userID else { return }
                if archive.history.contains(where: { $0.id == record.id }) { archive.uploaded = Array(Set((archive.uploaded ?? []) + [record.id])); save() }
            }
            for (id, deleted) in remote where !deleted && !archive.history.contains(where: { $0.id == id }) && !(archive.pendingDeletions ?? []).contains(id) {
                let value = try await api.call("/api/exercise/records/\(id.uuidString)")
                let record = try decoder.decode(ExerciseSession.self, from: JSONSerialization.data(withJSONObject: value))
                guard api.profile?.text("unifiedUserId") == userID, record.id == id, record.endedAt != nil else { return }
                if !(archive.pendingDeletions ?? []).contains(id) && !archive.history.contains(where: { $0.id == id }) {
                    archive.history.append(record); archive.uploaded = Array(Set((archive.uploaded ?? []) + [id])); save()
                }
            }
            archive.history.sort { $0.startedAt > $1.startedAt }; save(); syncMessage = String(localized: "已同步到当前账号", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
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
                    self.save()
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
    @State private var mapMode = false
    @State private var selectedRoute: ExerciseSession?
    @State private var kind = "散步"
    @State private var confirmFinish = false
    @State private var pendingDeletion: ExerciseSession?
    init(userID: String) { _exercise = StateObject(wrappedValue: ExerciseStore(userID: userID)) }

    var body: some View {
        NavigationStack {
            List {
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
                        }.pickerStyle(.segmented)
                        Button { exercise.start(kind: kind, map: mapMode) } label: {
                            Label(String(localized: "开始\(exerciseKindTitle(kind))", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
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
                            Text(exerciseDistanceTitle(item)).font(.headline).monospacedDigit()
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
                    await exercise.refresh(); await exercise.sync()
                }
                .onChange(of: family.profile?.text("unifiedUserId")) { _, _ in exercise.accountDidChange() }
                .onChange(of: mapMode) { _, value in if value { exercise.enableRoute() } }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await exercise.refresh(); await exercise.sync() } }
                    else { exercise.stopObserving() }
                }
                .onDisappear { exercise.stopObserving() }
        }
    }
}

private func exerciseKindTitle(_ value: String) -> String {
    let locale = Locale(identifier: AgentIdentityLanguage.current)
    switch value {
    case "散步": return String(localized: "散步", bundle: AgentIdentityLanguage.appBundle(), locale: locale)
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
