import AgentIdentity
import SwiftUI
import MapKit
import CoreLocation
import CryptoKit

@MainActor final class DiningStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var archive = DiningArchive()
    @Published var mood: DiningMood = .automatic
    @Published var result: DiningPlace?
    @Published var resultMood: DiningMood = .automatic
    @Published var busy = false
    @Published var message: String?
    @Published var confirmed = false
    @Published var circleID: UUID?
    @Published var walking: String?
    private let file: URL
    private var readable = true
    private let locator = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocation, Error>?
    private var timeout: Task<Void, Never>?
    private var search: MKLocalSearch?
    private var directions: MKDirections?
    private var origin: CLLocation?
    private var candidates: [DiningPlace] = []
    private var generation = UUID()
    private var fetchedAt = Date.distantPast

    init(userID: String) {
        let key = SHA256.hash(data: Data(DiningAccount.identity(userID).utf8)).map { String(format: "%02x", $0) }.joined()
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dining/\(key).json")
        super.init()
        locator.delegate = self; locator.desiredAccuracy = kCLLocationAccuracyHundredMeters
        guard !userID.isEmpty else { readable = false; message = String(localized: "用户身份尚未就绪，请重新登录后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do { archive = try decoder.decode(DiningArchive.self, from: Data(contentsOf: file)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { }
        catch { readable = false; message = String(localized: "干饭记录暂时无法读取，原记录已保留，请重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }
    func update(_ transform: (inout DiningArchive) -> Void) -> Bool {
        guard readable else { message = String(localized: "干饭记录暂时无法读取，原记录已保留，请重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return false }
        var next = archive; transform(&next)
        do { try next.write(to: file); archive = next; return true }
        catch { message = String(localized: "记录没有保存成功，请重试。原记录已保留。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return false }
    }
    func confirm() {
        guard let place = result, !confirmed, !busy else { return }
        if update({ $0.choose(place, mood: resultMood) }) { confirmed = true; message = String(localized: "安排好了！选择已记录，吃过后可在干饭记录中确认。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }
    func selectCircle(_ id: UUID?) {
        guard !busy else { return }
        circleID = id; origin = nil; candidates = []; result = nil; walking = nil; confirmed = false
    }
    func saveCircle(_ name: String) async {
        guard !busy else { return }; busy = true; message = nil
        defer { busy = false }
        do {
            let location = try await locate()
            let circle = DiningCircle(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            if update({ value in value.circles.removeAll { $0.name == name }; value.circles.append(circle) }) { selectSavedCircle(circle) }
        } catch is CancellationError { } catch { message = error.localizedDescription }
    }
    private func selectSavedCircle(_ circle: DiningCircle) { circleID = circle.id; origin = nil; candidates = []; result = nil; walking = nil }
    func decide() async {
        guard !busy else { return }; busy = true; message = nil; walking = nil
        let current = generation
        defer { if current == generation { busy = false } }
        do {
            if Date().timeIntervalSince(fetchedAt) > 300 { candidates = [] }
            if candidates.isEmpty {
                let location: CLLocation
                if let circle = archive.circles.first(where: { $0.id == circleID }) { location = CLLocation(latitude: circle.latitude, longitude: circle.longitude) }
                else { location = try await locate() }
                guard current == generation else { return }
                origin = location
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = "restaurant"
                request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 6000, longitudinalMeters: 6000)
                request.resultTypes = .pointOfInterest
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant])
                let operation = MKLocalSearch(request: request); search = operation
                let deadline = Task {
                    do { try await Task.sleep(for: .seconds(12)) } catch { return }
                    operation.cancel()
                }
                defer { deadline.cancel() }
                let response = try await operation.start()
                guard current == generation else { return }
                candidates = response.mapItems.compactMap { item in
                    guard let name = item.name, !name.isEmpty, let spot = item.placemark.location, location.distance(from: spot) <= 3000 else { return nil }
                    let address = [item.placemark.thoroughfare, item.placemark.subThoroughfare, item.placemark.locality].compactMap { $0 }.joined(separator: " ")
                    let raw = name + "|" + String(format: "%.5f|%.5f", spot.coordinate.latitude, spot.coordinate.longitude)
                    let id = "mapkit:" + SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
                    return DiningPlace(id: id, name: name, address: address, latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude, category: "restaurant", provider: "mapkit", distanceMeters: location.distance(from: spot))
                }
                fetchedAt = Date()
            }
            try await Task.sleep(for: .milliseconds(450))
            guard current == generation else { return }
            guard let next = DiningRecommendation.pick(candidates, mood: mood, archive: archive, excluding: result?.id) else {
                message = String(localized: "附近暂时没有找到餐厅。试试其他生活圈，或稍后重新定位。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return
            }
            if let previous = result, !confirmed { _ = update { $0.habits[previous.id, default: DiningHabit()].skipped += 1 } }
            guard current == generation else { return }
            result = next; resultMood = mood; confirmed = false
            if candidates.count == 1 { message = String(localized: "附近暂时只找到这一家，可换个生活圈再试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
            // The blind box animates only while real location/search work is running.
            busy = false
            await loadWalking(next, generation: current)
        } catch is CancellationError { }
        catch { if current == generation { message = (error as? APIError)?.localizedDescription ?? String(localized: "附近餐厅暂时无法读取，请稍后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) } }
    }
    func refreshLocation() { stop(); circleID = nil; candidates = []; origin = nil; result = nil; walking = nil; confirmed = false }
    func stop() {
        generation = UUID(); search?.cancel(); directions?.cancel(); timeout?.cancel(); locator.stopUpdatingLocation()
        waiting?.resume(throwing: CancellationError()); waiting = nil; busy = false
    }
    private func locate() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else { throw APIError.message(String(localized: "系统定位服务未开启，可使用已保存的生活圈。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        return try await withCheckedThrowingContinuation { continuation in
            waiting = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                self?.finishLocation(.failure(APIError.message(String(localized: "定位超时，请到开阔处重试，或选择已保存的生活圈。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))))
            }
            requestAuthorizedLocation()
        }
    }
    private func requestAuthorizedLocation() {
        switch locator.authorizationStatus {
        case .notDetermined: locator.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locator.requestLocation()
        default: finishLocation(.failure(APIError.message(String(localized: "请在系统设置中允许位置访问，或选择已保存的生活圈。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))))
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if waiting != nil { requestAuthorizedLocation() } }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 60 }) else { return }
        finishLocation(.success(location))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finishLocation(.failure(APIError.message(String(localized: "暂时无法定位，请重试或使用已保存的生活圈。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))))) }
    private func finishLocation(_ result: Result<CLLocation, Error>) { timeout?.cancel(); timeout = nil; let continuation = waiting; waiting = nil; continuation?.resume(with: result) }
    private func loadWalking(_ place: DiningPlace, generation current: UUID) async {
        guard let origin else { return }
        let request = MKDirections.Request(); request.transportType = .walking
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)))
        let operation = MKDirections(request: request); directions?.cancel(); directions = operation
        guard let route = try? await operation.calculate().routes.first, current == generation, result?.id == place.id else { return }
        walking = route.distance.formatted(.number.precision(.fractionLength(0))) + " m · " + String(Int(ceil(route.expectedTravelTime / 60))) + " min"
    }
    func navigate(_ place: DiningPlace) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))); item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

struct DiningView: View {
    @StateObject private var model: DiningStore
    @State private var showingRecords = false
    @State private var showingCircles = false
    @State private var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(userID: String) { _model = StateObject(wrappedValue: DiningStore(userID: userID)) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "今天吃啥？", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.largeTitle.bold())
                        Text(String(localized: "别纠结了，这顿我安排！", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.title3).foregroundStyle(.secondary)
                        Label(model.archive.circles.first(where: { $0.id == model.circleID })?.name ?? String(localized: "当前位置附近", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "location.circle").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if model.result == nil || model.busy {
                    VStack(spacing: 16) {
                        Text("🍚").font(.system(size: 76)).rotationEffect(.degrees(model.busy && spinning ? 12 : -8)).animation(model.busy && !reduceMotion ? .easeInOut(duration: 0.3).repeatForever(autoreverses: true) : .default, value: spinning)
                        Button { Task { await model.decide() } } label: {
                            HStack { if model.busy { ProgressView().tint(.white) }; Text(model.busy ? String(localized: "正在安排这顿饭…", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "🎲 帮我决定", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.title3.bold()).frame(maxWidth: .infinity) }.padding(12)
                        }.buttonStyle(.borderedProminent).tint(.orange).disabled(model.busy)
                        Text(String(localized: "不选条件也可以，一键安排。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) .font(.caption).foregroundStyle(.secondary)
                    }.padding(22).frame(maxWidth: .infinity).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 26))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(DiningMood.allCases, id: \.self) { mood in
                                Button(moodTitle(mood)) { model.mood = mood; if model.result != nil { Task { await model.decide() } } }.buttonStyle(.bordered).tint(model.mood == mood ? .orange : .gray).disabled(model.busy)
                            }
                        }
                    }
                    if let place = model.result { resultCard(place) }
                    if let message = model.message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently) }
                    Text(String(localized: "附近餐厅来自 Apple 地图；人均与评分缺失时不作推测。位置仅用于本次地图搜索，习惯与记录保存在当前账号的本机空间。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) .font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle(String(localized: "干饭", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(String(localized: "干饭记录与收藏", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "clock") { showingRecords = true }
                        Button(String(localized: "我的生活圈", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "location.circle") { showingCircles = true }
                        Button(String(localized: "重新定位", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "location") { model.refreshLocation() }
                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(String(localized: "干饭菜单", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                    .disabled(model.busy)
                }
            }
            .sheet(isPresented: $showingRecords) { records }
            .sheet(isPresented: $showingCircles) { circles }
            .onChange(of: model.busy) { _, busy in spinning = busy }
            .onDisappear { model.stop() }
        }
    }
    private func resultCard(_ place: DiningPlace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "命运安排好了，走，干饭！", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.headline).foregroundStyle(.orange)
            Text(place.name).font(.title2.bold()).textSelection(.enabled)
            if !place.address.isEmpty { Label(place.address, systemImage: "mappin.and.ellipse").font(.subheadline) }
            if let walking = model.walking { Label(walking, systemImage: "figure.walk") }
            else { Text(String(localized: "直线距离估算：", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) + place.distanceMeters.formatted(.number.precision(.fractionLength(0))) + " m") .font(.subheadline).foregroundStyle(.secondary) }
            Text(String(localized: "人均与评分暂无可靠数据", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).font(.caption).foregroundStyle(.secondary)
            Text(reason(place)).font(.subheadline)
            Button(model.confirmed ? String(localized: "已选好，走，干饭！", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "✅ 就吃这家！", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { model.confirm() }.buttonStyle(.borderedProminent).tint(.orange).disabled(model.confirmed || model.busy)
            Button(String(localized: "🎲 不行，再来一家！", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await model.decide() } }.buttonStyle(.bordered).disabled(model.busy)
            HStack {
                Button(String(localized: "带我过去！", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "map") { model.navigate(place) }
                Spacer()
                Button { _ = model.update { $0.toggleFavorite(place) } } label: { Image(systemName: model.archive.favorites.contains(where: { $0.id == place.id }) ? "heart.fill" : "heart").accessibilityLabel(String(localized: "收藏餐厅", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
            }.disabled(model.busy)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
    private func reason(_ place: DiningPlace) -> String {
        switch model.resultMood {
        case .familiar: return (model.archive.habits[place.id]?.selected ?? 0) > 0 ? String(localized: "你以前选择过这里，熟悉的味道值得再试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "还没有常吃记录，先从附近这家开始。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .fresh: return (model.archive.habits[place.id]?.selected ?? 0) == 0 ? String(localized: "你的干饭记录里还没有这家，来点新鲜的！", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "附近的新选择有限，熟悉的店也保留机会。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .budget, .treat: return String(localized: "暂未获取可靠的人均价格，点单前记得向店家确认。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .spicy: return String(localized: "按店名与菜系线索挑选，具体辣度请向店家确认。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .automatic: return (model.archive.habits[place.id]?.selected ?? 0) > 0 ? String(localized: "你以前选择过这里，熟悉的味道值得再试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "从附近真实餐厅中，为你挑了这一家。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        }
    }
    private func moodTitle(_ mood: DiningMood) -> String {
        switch mood {
        case .automatic: return String(localized: "🎲 随便安排", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .familiar: return String(localized: "❤️ 还是老样子", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .fresh: return String(localized: "✨ 来点新鲜的", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .budget: return String(localized: "💰 今天省点钱", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .treat: return String(localized: "😋 今天吃点好的", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .spicy: return String(localized: "🌶️ 想吃点刺激的", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        }
    }
    private var records: some View {
        NavigationStack {
            List {
                Section(String(localized: "我的收藏", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    ForEach(model.archive.favorites) { place in
                        HStack { VStack(alignment: .leading) { Text(place.name); Text(place.address).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(String(localized: "导航", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { model.navigate(place) } }
                    }
                    if model.archive.favorites.isEmpty { Text(String(localized: "还没有收藏餐厅", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                }
                Section(String(localized: "干饭记录 · 当地时间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    ForEach(model.archive.history) { choice in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(choice.place.name).font(.headline)
                            Text(choice.selectedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            if choice.eatenAt != nil { Label(String(localized: "吃过了", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "checkmark.circle.fill").foregroundStyle(.orange) }
                            else { Button(String(localized: "我吃过了", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { _ = model.update { $0.confirmEaten(choice.id) } } }
                        }
                    }
                    if model.archive.history.isEmpty { Text(String(localized: "选好餐厅后，记录会保存在这里。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                }
                Section { Text(String(localized: "记录与习惯仅保存在本机，切换账号相互隔离。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) .font(.caption).foregroundStyle(.secondary) }
                if let message = model.message { Text(message).foregroundStyle(.secondary) }
            }.navigationTitle(String(localized: "干饭记录与收藏", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { showingRecords = false } } }
        }
    }
    private var circles: some View {
        NavigationStack {
            List {
                Button(String(localized: "使用当前位置", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { model.selectCircle(nil); showingCircles = false }
                ForEach(model.archive.circles) { circle in
                    HStack { Button(circle.name) { model.selectCircle(circle.id); showingCircles = false }; Spacer(); if model.circleID == circle.id { Image(systemName: "checkmark") } }
                }.onDelete { indices in
                    let removed = indices.map { model.archive.circles[$0].id }
                    if model.update({ $0.circles.removeAll { removed.contains($0.id) } }), let selected = model.circleID, removed.contains(selected) { model.selectCircle(nil) }
                }
                Section(String(localized: "将当前位置保存为生活圈", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    Button(String(localized: "🏠 家附近", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await model.saveCircle(String(localized: "家附近", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) } }
                    Button(String(localized: "🏢 公司附近", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { Task { await model.saveCircle(String(localized: "公司附近", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) } }
                    Text(String(localized: "保存后可直接发现该区域餐厅，无需每次重新定位。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) .font(.caption).foregroundStyle(.secondary)
                }.disabled(model.busy)
                if model.busy { ProgressView() }
                if let message = model.message { Text(message).foregroundStyle(.secondary) }
            }.navigationTitle(String(localized: "我的生活圈", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "完成", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { showingCircles = false } } }
        }
    }
}
