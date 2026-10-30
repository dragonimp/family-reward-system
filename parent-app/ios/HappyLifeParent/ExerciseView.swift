import SwiftUI
import CoreMotion
import CryptoKit

@MainActor final class ExerciseStore: ObservableObject {
    private struct Archive: Codable {
        var active: ExerciseSession?
        var history: [ExerciseSession] = []
    }
    @Published private var archive = Archive()
    @Published var message: String?
    @Published var busy = false
    private let pedometer = CMPedometer()
    private let file: URL
    private var generation = UUID()
    private var readable = true
    var active: ExerciseSession? { archive.active }
    var history: [ExerciseSession] { archive.history }
    var supported: Bool { CMPedometer.isStepCountingAvailable() }
    var distanceSupported: Bool { CMPedometer.isDistanceAvailable() }

    init(userID: String) {
        let key = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exercise/\(key).json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do { archive = try decoder.decode(Archive.self, from: Data(contentsOf: file)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { }
        catch { readable = false; message = "运动记录暂时无法读取，请重新打开页面后重试。原记录已保留。" }
    }

    private func save() {
        guard readable else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(archive).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { message = "运动记录尚未保存：\(error.localizedDescription)。请保留页面并重试保存。" }
    }
    func retrySave() { guard readable else { return }; message = nil; save() }

    func start(kind: String) {
        guard readable, active == nil, !busy else { return }
        let now = Date()
        archive.active = ExerciseSession(kind: kind, startedAt: now, intervals: [ExerciseInterval(start: now)])
        save(); observe()
    }
    func resume() {
        guard readable, !busy else { return }
        archive.active?.resume(at: Date()); save(); observe()
    }
    func pause() async {
        guard active?.running == true, !busy else { return }
        stopObserving()
        archive.active?.pause(at: Date()); save()
        await reconcile()
    }
    func finish() async {
        guard active != nil, !busy else { return }
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
    }
    func refresh() async {
        guard readable, !busy else { return }
        stopObserving()
        await reconcile()
        if active?.running == true { observe() }
    }
    func stopObserving() { generation = UUID(); pedometer.stopUpdates() }

    private func observe() {
        stopObserving()
        guard let active, active.running, let index = active.intervals.indices.last else { return }
        guard supported else { message = "此设备不支持计步，可继续使用运动计时。"; return }
        if CMPedometer.authorizationStatus() == .denied || CMPedometer.authorizationStatus() == .restricted {
            message = "未获得运动与健身权限，可在系统设置中开启；计时仍可使用。"; return
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
                if let error { self.message = "计步暂不可用：\(error.localizedDescription)。计时仍可使用。" }
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
                message = "部分运动已超过系统数据保留期，步数或距离无法完整获取。"; continue
            }
            let result: (CMPedometerData?, Error?) = await withCheckedContinuation { continuation in
                pedometer.queryPedometerData(from: interval.start, to: end) { continuation.resume(returning: ($0, $1)) }
            }
            guard archive.active?.id == active.id else { return }
            if let data = result.0 {
                archive.active?.intervals[index].steps = data.numberOfSteps.intValue
                archive.active?.intervals[index].distanceMeters = data.distance?.doubleValue
            }
            if let error = result.1 { message = "计步暂不可用：\(error.localizedDescription)。已保留计时记录。" }
        }
        save()
    }
}

struct ExerciseView: View {
    @StateObject private var exercise: ExerciseStore
    @Environment(\.scenePhase) private var phase
    @State private var kind = "散步"
    @State private var confirmFinish = false
    init(userID: String) { _exercise = StateObject(wrappedValue: ExerciseStore(userID: userID)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("动一动，记录自己的节奏", systemImage: "figure.walk")
                        .font(.title3.bold()).padding(.vertical, 8)
                    Text("带上手机，随时开始一场散步或轻运动。").foregroundStyle(.secondary)
                }
                Section(exercise.active?.kind ?? "开始运动") {
                    if let active = exercise.active {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 12) {
                                Text(ExerciseSession.clock(active.duration(at: context.date)))
                                    .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                                    .accessibilityLabel("运动时长")
                                Text(active.distanceMeters == nil && !exercise.distanceSupported ? "此设备不支持距离估算" : active.distanceText)
                                    .font(.title.bold()).monospacedDigit()
                                    .accessibilityLabel("运动距离，\(active.distanceText)")
                                Text(active.steps.map { "\($0) 步" } ?? "步数待获取")
                                    .font(.title2).monospacedDigit()
                                Text(active.running ? "运动中" : "已暂停").foregroundStyle(active.running ? .teal : .secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 18)
                        }
                        HStack {
                            Button(active.running ? "暂停" : "继续") {
                                if active.running { Task { await exercise.pause() } } else { exercise.resume() }
                            }.buttonStyle(.borderedProminent)
                            Spacer()
                            Button("结束并保存", role: .destructive) { confirmFinish = true }.buttonStyle(.bordered)
                        }.disabled(exercise.busy)
                    } else {
                        Picker("运动项目", selection: $kind) {
                            Text("散步").tag("散步"); Text("慢跑").tag("慢跑"); Text("自由运动").tag("自由运动")
                        }.pickerStyle(.segmented)
                        Button { exercise.start(kind: kind) } label: {
                            Label("开始\(kind)", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent)
                    }
                    Text("暂停期间不计时、不计步、不累计距离。锁屏后计时继续，返回时读取系统数据。公里数由系统根据步行或跑步估算，非 GPS 轨迹；数据可能稍有延迟，不支持时显示未获取。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message = exercise.message {
                    Section("提示") {
                        Text(message).font(.footnote)
                        Button("重试读取步数与距离") { Task { await exercise.refresh() } }
                        Button("重试保存记录") { exercise.retrySave() }
                        Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }
                }
                Section {
                    if exercise.history.isEmpty {
                        ContentUnavailableView("还没有运动记录", systemImage: "figure.walk", description: Text("完成一次运动后，时长、步数和公里数会保存在这里。"))
                    }
                    ForEach(exercise.history) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(item.kind).bold(); Spacer(); Text(ExerciseSession.clock(item.duration(at: item.endedAt ?? .now))).monospacedDigit() }
                            Text(item.distanceText).font(.headline).monospacedDigit()
                            HStack {
                                Text(item.startedAt, format: .dateTime.year().month().day().hour().minute())
                                Spacer()
                                Text(item.steps.map { "\($0) 步" } ?? "步数未获取")
                            }.font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                } header: { Text("运动记录 · 当地时间") } footer: { Text("记录按当前账号保存在此手机，暂不跨设备同步。") }
            }.navigationTitle("运动").readablePage()
                .confirmationDialog("结束本次运动并保存记录？", isPresented: $confirmFinish, titleVisibility: .visible) {
                    Button("结束并保存") { Task { await exercise.finish() } }
                }
                .task { await exercise.refresh() }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await exercise.refresh() } }
                    else { exercise.stopObserving() }
                }
                .onDisappear { exercise.stopObserving() }
        }
    }
}
