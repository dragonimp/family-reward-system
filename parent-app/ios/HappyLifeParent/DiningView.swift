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
    @Published private(set) var checkingIn = false
    @Published private(set) var checkInPlaces: [DiningPlace] = []
    @Published private(set) var manualPosition: CLLocationCoordinate2D?
    @Published private(set) var manualAddress = ""
    private let checkInGeocoder = CLGeocoder()
    @Published var message: String?
    @Published var confirmed = false
    @Published var circleID: UUID?
    @Published var walking: String?
    @Published private(set) var trip: DiningTrip = .unrestricted
    private var routeTimes: [String: TimeInterval] = [:]
    private var cachedDriving = false
    private let file: URL
    private let family: FamilyStore
    private let accountID: String
    private var syncState = DiningSyncState()
    private var syncing = false
    private var syncAgain = false
    @Published var syncMessage: String?
    private var syncFile: URL { file.appendingPathExtension("sync-v1") }
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func writeSync(_ value: DiningSyncState) throws {
        try FileManager.default.createDirectory(at: syncFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded(value).write(to: syncFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private var ownsAccount: Bool { family.identity.isAuthenticated && DiningAccount.identity(family.identity.accountIdentifier ?? "") == accountID }
    func synchronize() async {
        guard readable, ownsAccount else { return }
        if syncing { syncAgain = true; return }
        syncing = true
        defer { syncing = false }
        do {
            repeat {
                syncAgain = false
                let needsUpload: Bool
                if let base = syncState.baseline { needsUpload = try encoded(base) != encoded(archive) } else { needsUpload = true }
                if syncState.outbox == nil, needsUpload {
                    syncState.archive = archive
                    syncState.outbox = DiningSyncRequest(baseline: syncState.baseline, archive: archive)
                    try writeSync(syncState)
                }
                let sent = syncState.outbox
                let snapshot = archive
                let response: Any
                if let sent {
                    try writeSync(syncState)
                    let body = try JSONSerialization.jsonObject(with: encoded(sent)) as! [String: Any]
                    response = try await family.call("/api/dining/account/sync", method: "POST", body: body)
                } else { response = try await family.call("/api/dining/account") }
                guard ownsAccount else { return }
                try Task.checkCancellation()
                guard let fields = response as? [String: Any], let raw = fields["archive"] as? [String: Any] else { throw APIError.message(String(localized: "干饭同步回执无效。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let remote = try decoder.decode(DiningArchive.self, from: JSONSerialization.data(withJSONObject: raw))
                let unchanged = try encoded(sent?.archive ?? snapshot) == encoded(archive)
                let next = DiningSyncState(archive: unchanged ? remote : archive, baseline: unchanged ? remote : (sent?.archive ?? syncState.baseline), outbox: nil)
                try writeSync(next); syncState = next; archive = next.archive
                syncMessage = nil; syncAgain = !unchanged
            } while syncAgain && ownsAccount && !Task.isCancelled
        } catch is CancellationError { }
        catch { if ownsAccount { syncMessage = String(localized: "干饭记录暂未同步；本机记录已保留，联网后自动重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) } }
    }
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
    @Published private(set) var food: DiningFood = .smart
    private var cachedFood: DiningFood?
    private var hasRequestedRecommendation = false
    private var cachedMeal: DiningMeal?
    @Published private(set) var resultMeal: DiningMeal?
    private var resultOperation = UUID()

    init(userID: String, family: FamilyStore) {
        self.family = family
        self.accountID = DiningAccount.identity(userID)
        let key = SHA256.hash(data: Data(DiningAccount.identity(userID).utf8)).map { String(format: "%02x", $0) }.joined()
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dining/\(key).json")
        super.init()
        locator.delegate = self; locator.desiredAccuracy = kCLLocationAccuracyHundredMeters
        guard !userID.isEmpty else { readable = false; message = String(localized: "用户身份尚未就绪，请重新登录后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do {
            if FileManager.default.fileExists(atPath: syncFile.path) { syncState = try decoder.decode(DiningSyncState.self, from: Data(contentsOf: syncFile)); archive = syncState.archive }
            else { archive = try decoder.decode(DiningArchive.self, from: Data(contentsOf: file)) }
        }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { }
        catch { readable = false; message = String(localized: "干饭记录暂时无法读取，原记录已保留，请重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
    }
    func update(_ transform: (inout DiningArchive) -> Void) -> Bool {
        guard readable else { message = String(localized: "干饭记录暂时无法读取，原记录已保留，请重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return false }
        var next = archive; transform(&next)
        do {
            var state = syncState; state.archive = next; try writeSync(state); syncState = state; archive = next
            Task { await synchronize() }; return true
        }
        catch { message = String(localized: "记录没有保存成功，请重试。原记录已保留。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return false }
    }
    func confirm(operation: UUID) {
        guard let place = result, operation == resultOperation, !confirmed, !busy, !checkingIn else { return }
        confirmed = checkIn(place, mood: resultMood, operation: operation)
    }
    var confirmationOperation: UUID { resultOperation }

    @discardableResult
    func checkIn(_ place: DiningPlace, mood: DiningMood? = nil, operation: UUID, restaurantType: String = "") -> Bool {
        guard update({ $0.checkIn(place, mood: mood, id: operation, restaurantType: restaurantType) }) else { return false }
        message = diningText("打卡成功，已记入干饭记录。")
        return true
    }

    func findCheckInPlaces(manual: Bool = false) async {
        guard !busy, !checkingIn, !Task.isCancelled else { return }
        checkingIn = true
        checkInPlaces = []
        checkInGeocoder.cancelGeocode()
        manualPosition = nil
        manualAddress = ""
        message = nil
        let current = UUID()
        generation = current
        defer { if current == generation { checkingIn = false } }
        do {
            let location = try await locate(accuracy: manual ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters)
            guard current == generation, !Task.isCancelled else { return }
            if manual {
                guard CLLocationCoordinate2DIsValid(location.coordinate) else {
                    message = diningText("无法获取当前位置，请检查定位权限后重试。")
                    return
                }
                manualPosition = location.coordinate
                Task { await resolveCheckInAddress(location, generation: current) }
                return
            }
            guard location.horizontalAccuracy <= 500 else {
                message = diningText("定位精度不足，请开启精确位置后重试。")
                return
            }
            let nearby = try await nearbyPlaces(around: location, radius: 500)
            guard current == generation, !Task.isCancelled else { return }
            var seen = Set<String>()
            checkInPlaces = nearby.sorted { $0.distanceMeters < $1.distanceMeters }
                .filter { seen.insert($0.id).inserted }
            if checkInPlaces.isEmpty { message = diningText("当前位置 500 米内未找到餐厅。") }
        } catch is CancellationError { }
        catch {
            if current == generation, !Task.isCancelled {
                message = manual ? diningText("无法获取当前位置，请检查定位权限后重试。")
                    : diningText("无法读取附近餐厅，请检查定位权限或网络后重试。")
            }
        }
    }

    private func resolveCheckInAddress(_ location: CLLocation, generation current: UUID) async {
        guard current == generation, manualPosition != nil else { return }
        let places = try? await checkInGeocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh-Hans-CN"))
        guard current == generation, manualPosition != nil, let place = places?.first else { return }
        let street = [place.thoroughfare, place.subThoroughfare].compactMap { $0 }.joined()
        let parts = [place.administrativeArea, place.locality, place.subLocality, street.isEmpty ? place.name : street]
        var address: [String] = []
        for part in parts.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) where !part.isEmpty && !address.contains(part) {
            address.append(part)
        }
        manualAddress = address.joined()
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
    func selectTrip(_ trip: DiningTrip) {
        guard !busy, !checkingIn, self.trip != trip else { return }
        if self.trip.driving != trip.driving { routeTimes = [:] }
        self.trip = trip
        refreshRecommendationAfterFilterChange()
    }

    func selectFood(_ food: DiningFood) {
        guard !busy, !checkingIn, self.food != food else { return }
        self.food = food
        refreshRecommendationAfterFilterChange()
    }

    private func refreshRecommendationAfterFilterChange() {
        result = nil; walking = nil; confirmed = false; message = nil
        if hasRequestedRecommendation { Task { await decide() } }
    }

    @Published var selection: DiningSelection = .recommended
    func decide() async {
        guard !busy, !checkingIn else { return }; busy = true; message = nil; walking = nil
        let current = UUID()
        generation = current
        defer { if current == generation { busy = false } }
        hasRequestedRecommendation = true
        let meal = DiningMeal.current()
        let food = self.food
        let mealKey: DiningMeal? = food == .smart ? meal : nil
        let trip = self.trip
        let radius: CLLocationDistance = trip.driving ? 8000 : 3000
        if resultMeal != mealKey { result = nil; confirmed = false }
        do {
            if cachedFood != food || cachedMeal != mealKey || cachedDriving != trip.driving || Date().timeIntervalSince(fetchedAt) > 300 { candidates = [] }
            if candidates.isEmpty {
                let location: CLLocation
                if let circle = archive.circles.first(where: { $0.id == circleID }) { location = CLLocation(latitude: circle.latitude, longitude: circle.longitude) }
                else { location = try await locate() }
                guard current == generation else { return }
                origin = location
                routeTimes = [:]
                async let details = mapDetails(near: location)
                let query = food == .smart ? (meal == .breakfast ? "breakfast" : meal == .afternoonTea ? "dessert" : "restaurant") : food.searchQuery
                let expanded = mealKey == .breakfast || mealKey == .afternoonTea || food == .sweets
                var nearby = try await nearbyPlaces(around: location, radius: radius, query: query, includeCafes: expanded)
                let mapDetails = await details
                if let mapDetails {
                    nearby = mapDetails.applying(to: nearby, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                }
                if mealKey == .afternoonTea, !nearby.contains(where: meal.includes) {
                    guard current == generation else { return }
                    let tea = try await nearbyPlaces(around: location, radius: radius, query: "bubble tea", includeCafes: true)
                    nearby += mapDetails?.applying(to: tea, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) ?? tea
                }
                guard current == generation else { return }
                candidates = nearby.filter { food.includes($0, meal: meal) }
                cachedFood = food
                cachedMeal = mealKey
                cachedDriving = trip.driving
                fetchedAt = Date()
            }
            var eligible = candidates.filter { trip.includesDistance($0.distanceMeters) }
            if trip.limit != nil {
                let nearest = Array(eligible.sorted { $0.distanceMeters < $1.distanceMeters }.prefix(6))
                for place in nearest where routeTimes[place.id] == nil {
                    let seconds = await routeTime(place, driving: trip.driving)
                    guard current == generation else { return }
                    routeTimes[place.id] = seconds
                }
                eligible = nearest.filter { trip.includes(routeTimes[$0.id]) }
            }
            try await Task.sleep(for: .milliseconds(450))
            guard current == generation else { return }
            guard mealKey == nil || DiningMeal.current() == meal else {
                result = nil
                message = diningText("餐段已切换，请重新推荐。")
                return
            }
            guard let next = DiningRecommendation.pick(eligible, mood: mood, archive: archive, excluding: result?.id, selection: selection) else {
                result = nil
                if !candidates.isEmpty && trip != .unrestricted {
                    message = diningText("暂未找到能确认符合路程上限的餐厅。可以放宽上限后重试。")
                } else {
                    message = food == .smart
                        ? diningText("附近暂时没有适合当前餐段的餐厅。试试其他生活圈，或稍后重新定位。")
                        : diningText("附近暂时没有符合所选食物类型的餐厅。")
                }
                return
            }
            if let previous = result, !confirmed { _ = update { $0.habits[previous.id, default: DiningHabit()].skipped += 1 } }
            guard current == generation else { return }
            result = next; resultMood = mood; resultMeal = mealKey; confirmed = false; resultOperation = UUID()
            if eligible.count == 1 { message = String(localized: "附近暂时只找到这一家，可换个生活圈再试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
            // The blind box animates only while real location/search work is running.
            busy = false
            if let seconds = routeTimes[next.id], trip.limit != nil {
                walking = routeLabel(seconds, driving: trip.driving)
            } else {
                let seconds = await routeTime(next, driving: false)
                if let seconds, current == generation, result?.id == next.id {
                    walking = routeLabel(seconds, driving: false)
                }
            }
        } catch is CancellationError { }
        catch { if current == generation { message = (error as? APIError)?.localizedDescription ?? String(localized: "附近餐厅暂时无法读取，请稍后重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) } }
    }
    func closeCheckIn() {
        if checkingIn { stop() }
        checkInGeocoder.cancelGeocode()
        checkInPlaces = []
        manualPosition = nil
        manualAddress = ""
    }

    private func nearbyPlaces(around location: CLLocation, radius: CLLocationDistance, query: String = "restaurant", includeCafes: Bool = false) async throws -> [DiningPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: includeCafes ? [.restaurant, .cafe, .bakery] : [.restaurant])
        let operation = MKLocalSearch(request: request); search = operation
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            operation.cancel()
        }
        defer { deadline.cancel() }
        let response = try await operation.start()
        return response.mapItems.compactMap { item in
            guard let name = item.name, !name.isEmpty, let spot = item.placemark.location, location.distance(from: spot) <= radius else { return nil }
            let address = [item.placemark.thoroughfare, item.placemark.subThoroughfare, item.placemark.locality].compactMap { $0 }.joined(separator: " ")
            let raw = name + "|" + String(format: "%.5f|%.5f", spot.coordinate.latitude, spot.coordinate.longitude)
            let id = "mapkit:" + SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
            let category = switch item.pointOfInterestCategory {
            case .cafe: "咖啡馆"
            case .bakery: "面包店"
            case .restaurant: "restaurant"
            default: ""
            }
            return DiningPlace(id: id, name: name, address: address, latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude, category: category, provider: "mapkit", distanceMeters: location.distance(from: spot))
        }
    }
    private func mapDetails(near location: CLLocation) async -> DiningMapDetails? {
        let body = ["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude]
        guard let response = try? await family.call("/api/dining/nearby", method: "POST", body: body, timeout: 2),
              let data = try? JSONSerialization.data(withJSONObject: response) else { return nil }
        return try? JSONDecoder().decode(DiningMapDetails.self, from: data)
    }
    func refreshLocation() { stop(); circleID = nil; candidates = []; origin = nil; result = nil; walking = nil; confirmed = false }
    func stop() {
        generation = UUID(); search?.cancel(); directions?.cancel(); timeout?.cancel(); locator.stopUpdatingLocation()
        waiting?.resume(throwing: CancellationError()); waiting = nil; busy = false; checkingIn = false
    }
    private func locate(accuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters) async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else { throw APIError.message(String(localized: "系统定位服务未开启，可使用已保存的生活圈。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
        locator.desiredAccuracy = accuracy
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
    private func routeTime(_ place: DiningPlace, driving: Bool) async -> TimeInterval? {
        guard let origin else { return nil }
        let request = MKDirections.Request()
        request.transportType = driving ? .automobile : .walking
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)))
        let operation = MKDirections(request: request); directions?.cancel(); directions = operation
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            operation.cancel()
        }
        defer { deadline.cancel() }
        guard let response = try? await operation.calculateETA(), response.transportType == request.transportType,
              response.expectedTravelTime.isFinite, response.expectedTravelTime > 0 else { return nil }
        return response.expectedTravelTime
    }
    private func routeLabel(_ seconds: TimeInterval, driving: Bool) -> String {
        let minutes = ceil(seconds / 60).formatted()
        return driving ? diningText("预计开车约 \(minutes) 分钟") : diningText("预计步行约 \(minutes) 分钟")
    }
    func navigate(_ place: DiningPlace, driving: Bool = false, provider: String = "apple") {
        if provider != "apple" {
            // MapKit and manual locations are WGS84; explicitly declare GPS input.
            let gps = place.provider != "amap"
            var components = URLComponents()
            components.scheme = provider == "amap" ? "iosamap" : "baidumap"
            components.host = provider == "amap" ? "path" : "map"
            if provider == "amap" {
                components.queryItems = [URLQueryItem(name: "sourceApplication", value: "LinkoMoment"),
                    URLQueryItem(name: "dlat", value: String(place.latitude)), URLQueryItem(name: "dlon", value: String(place.longitude)),
                    URLQueryItem(name: "dname", value: place.name), URLQueryItem(name: "dev", value: gps ? "1" : "0"),
                    URLQueryItem(name: "t", value: driving ? "0" : "2")]
            } else {
                components.path = "/direction"
                components.queryItems = [URLQueryItem(name: "destination", value: "latlng:\(place.latitude),\(place.longitude)|name:\(place.name)"),
                    URLQueryItem(name: "coord_type", value: gps ? "wgs84" : "gcj02"),
                    URLQueryItem(name: "mode", value: driving ? "driving" : "walking"), URLQueryItem(name: "src", value: "ios.net.impx.happylife")]
            }
            guard let url = components.url, UIApplication.shared.canOpenURL(url) else {
                message = String(localized: "请先安装或启用所选地图，也可以重新选择其他地图。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)); return
            }
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                if !opened { Task { @MainActor in self?.message = String(localized: "无法打开所选地图，请重试或选择其他地图。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) } }
            }
            return
        }
        if place.provider == "amap" {
            // Imported Android favorites use GCJ-02. Resolve them through MapKit
            // by name/address rather than interpreting those values as GPS.
            Task {
                let request = MKLocalSearch.Request(); request.naturalLanguageQuery = place.name + " " + place.address
                request.resultTypes = .pointOfInterest
                request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude), latitudinalMeters: 4000, longitudinalMeters: 4000)
                do {
                    let response = try await MKLocalSearch(request: request).start()
                    let candidates = response.mapItems.filter { item in
                        guard item.name?.compare(place.name, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame else { return false }
                        return CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude).distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) < 2000
                    }
                    guard candidates.count == 1 else { throw APIError.message("location") }
                    candidates[0].openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: driving ? MKLaunchOptionsDirectionsModeDriving : MKLaunchOptionsDirectionsModeWalking])
                } catch { message = String(localized: "苹果地图暂时无法确认这家店的位置，请选择高德或百度地图。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) }
            }
            return
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))); item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: driving ? MKLaunchOptionsDirectionsModeDriving : MKLaunchOptionsDirectionsModeWalking])
    }
}

private func diningText(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
}

private struct DiningBowl: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.width, y = rect.height
        return Path { path in
            path.move(to: CGPoint(x: x * 0.09, y: y * 0.49))
            path.addQuadCurve(to: CGPoint(x: x * 0.92, y: y * 0.47), control: CGPoint(x: x * 0.50, y: y * 0.57))
            path.addQuadCurve(to: CGPoint(x: x * 0.52, y: y * 0.92), control: CGPoint(x: x * 0.83, y: y * 0.92))
            path.addQuadCurve(to: CGPoint(x: x * 0.09, y: y * 0.49), control: CGPoint(x: x * 0.21, y: y * 0.92))
            for offset in [0.34, 0.53, 0.72] {
                path.move(to: CGPoint(x: x * offset, y: y * 0.33))
                path.addCurve(to: CGPoint(x: x * (offset + 0.01), y: y * 0.07),
                              control1: CGPoint(x: x * (offset + 0.14), y: y * 0.20),
                              control2: CGPoint(x: x * (offset - 0.09), y: y * 0.16))
            }
        }
    }
}

struct DiningView: View {
    @StateObject private var model: DiningStore
    @State private var showingRecords = false
    @State private var showingCircles = false
    @State private var showingCheckIn = false
    @State private var showingFilters = false
    @State private var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(userID: String, family: FamilyStore) { _model = StateObject(wrappedValue: DiningStore(userID: userID, family: family)) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 4) {
                        shortcut("推荐", icon: "sparkles", selection: .recommended)
                        shortcut("附近", icon: "location", selection: .nearby)
                        shortcut("常去", icon: "heart", selection: .recommended, mood: .familiar)
                        shortcut("随机", icon: "dice", selection: .random)
                    }
                    .padding(4)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    .disabled(model.busy || model.checkingIn)

                    HStack(spacing: 8) {
                        Label(model.archive.circles.first(where: { $0.id == model.circleID })?.name ?? diningText("当前位置附近"), systemImage: "location.circle")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button(diningText("筛选"), systemImage: "slider.horizontal.3") { showingFilters = true }
                            .disabled(model.busy || model.checkingIn)
                    }.font(.subheadline)

                    if let syncMessage = model.syncMessage { Text(syncMessage).font(.caption).foregroundStyle(.secondary) }
                    if let place = model.result {
                        resultCard(place, operation: model.confirmationOperation)
                    } else {
                        VStack(spacing: 12) {
                            DiningBowl()
                                .stroke(.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                .frame(width: 72, height: 60)
                                .rotationEffect(.degrees(spinning && !reduceMotion ? 8 : -8))
                                .animation(.easeInOut(duration: 0.25), value: spinning)
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            Text(diningText("今天吃啥？")).font(.title.bold())
                            Button { Task { await model.decide() } } label: {
                                HStack {
                                    if model.busy { ProgressView().tint(.white) }
                                    Text(model.busy ? diningText("正在安排这顿饭…") : diningText("🎲 帮我决定"))
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent).controlSize(.large).tint(.orange)
                                .disabled(model.busy || model.checkingIn)
                        }.padding(24).frame(maxWidth: .infinity)
                            .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 26))
                    }
                    if model.busy && model.result != nil { ProgressView(diningText("正在安排这顿饭…")).font(.footnote) }
                    if let message = model.message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently) }
                    Text(String(localized: "附近餐厅来自 Apple 地图，菜系及人均可由高德地图补充。搜索位置仅用于本次查询，记录、收藏与偏好按账号跨设备同步。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) .font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle(String(localized: "干饭", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(diningText("到店打卡"), systemImage: "mappin.circle") { showingCheckIn = true }
                        Button(String(localized: "干饭记录与收藏", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "clock") { showingRecords = true }
                        Button(String(localized: "我的生活圈", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "location.circle") { showingCircles = true }
                        Button(String(localized: "重新定位", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "location") { model.refreshLocation() }
                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(String(localized: "干饭菜单", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                    .disabled(model.busy)
                }
            }
            .sheet(isPresented: $showingCheckIn, onDismiss: model.closeCheckIn) { DiningCheckInSheet(model: model) }
            .sheet(isPresented: $showingFilters) { filters }
            .sheet(isPresented: $showingRecords) { records }
            .sheet(isPresented: $showingCircles) { circles }
            .onChange(of: model.busy) { _, busy in spinning = busy }
            .task {
                await model.synchronize()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                    await model.synchronize()
                }
            }
            .onDisappear { model.stop() }
        }
    }
    private func shortcut(_ title: String.LocalizationValue, icon: String, selection: DiningSelection, mood: DiningMood = .automatic) -> some View {
        let selected = model.selection == selection && (selection != .recommended || (model.mood == .familiar) == (mood == .familiar))
        return Button {
            model.selection = selection
            model.mood = mood
            Task { await model.decide() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.subheadline)
                Text(diningText(title)).font(.caption.weight(.semibold))
            }.frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color.orange.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var filters: some View {
        NavigationStack {
            Form {
                Picker(diningText("食物类型"), selection: Binding(get: { model.food }, set: model.selectFood)) {
                    ForEach(DiningFood.allCases, id: \.self) { Text(foodTitle($0)).tag($0) }
                }
                Picker(diningText("路程"), selection: Binding(get: { model.trip }, set: model.selectTrip)) {
                    ForEach(DiningTrip.allCases, id: \.self) { Text(tripTitle($0)).tag($0) }
                }
                Picker(diningText("口味偏好"), selection: $model.mood) {
                    ForEach(DiningMood.allCases, id: \.self) { Text(moodTitle($0)).tag($0) }
                }.onChange(of: model.mood) { _, _ in
                    model.selection = .recommended
                    if model.result != nil { Task { await model.decide() } }
                }
            }.disabled(model.busy)
                .navigationTitle(diningText("筛选"))
                .toolbar { Button(diningText("完成")) { showingFilters = false } }
        }
    }

    private func resultCard(_ place: DiningPlace, operation: UUID) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.resultMeal.map(mealTitle) ?? foodTitle(model.food))
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                Spacer()
                Button { _ = model.update { $0.toggleFavorite(place) } } label: {
                    Image(systemName: model.archive.favorites.contains(where: { $0.id == place.id }) ? "heart.fill" : "heart")
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(diningText("收藏餐厅"))
                }.buttonStyle(.plain)
            }
            Text(place.name).font(.title.bold()).textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            Label(model.walking ?? (diningText("直线距离估算：") + place.distanceMeters.formatted(.number.precision(.fractionLength(0))) + " m"),
                  systemImage: model.walking == nil ? "location" : model.trip.driving ? "car" : "figure.walk")
                .font(.subheadline.weight(.semibold))
            Text(reason(place)).font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            if !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(.secondary) }
            if place.cuisine != nil || (place.cost ?? 0) > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    if place.cuisine != nil { Text(cuisineText(place)) }
                    if let cost = place.cost, cost.isFinite, cost > 0 { Text(priceText(place)) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Button {
                model.confirm(operation: operation)
            } label: {
                Text(model.confirmed ? diningText("已选好，走，干饭！") : diningText("就吃这家"))
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large).tint(.orange).disabled(model.confirmed)
            HStack(spacing: 8) {
                Button { Task { await model.decide() } } label: {
                    Label(diningText("换一家"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                DiningNavigationPicker { provider in
                    model.navigate(place, driving: model.trip.driving, provider: provider)
                }
            }.buttonStyle(.bordered).controlSize(.large)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
            .disabled(model.busy)
    }
    private func cuisineText(_ place: DiningPlace) -> String {
        let bundle = AgentIdentityLanguage.appBundle()
        let locale = Locale(identifier: AgentIdentityLanguage.current)
        guard let cuisine = place.cuisine else {
            return String(localized: "暂无菜系或主打餐品信息。", bundle: bundle, locale: locale)
        }
        return place.category.contains(cuisine)
            ? String(localized: "地图分类显示，这家店属于\(cuisine)。", bundle: bundle, locale: locale)
            : String(localized: "从店名看，这家店可能供应\(cuisine)。", bundle: bundle, locale: locale)
    }
    private func priceText(_ place: DiningPlace) -> String {
        let bundle = AgentIdentityLanguage.appBundle()
        let locale = Locale(identifier: AgentIdentityLanguage.current)
        guard let cost = place.cost, cost.isFinite, cost > 0 else {
            return String(localized: "人均消费暂无数据", bundle: bundle, locale: locale)
        }
        let price = cost.formatted(.currency(code: "CNY").precision(.fractionLength(0...2)).locale(locale))
        return String(localized: "人均约\(price) · 高德地图参考价", bundle: bundle, locale: locale)
    }
    private func foodTitle(_ food: DiningFood) -> String {
        switch food {
        case .smart: diningText("智能推荐")
        case .noodles: diningText("面食")
        case .rice: diningText("米饭")
        case .hotPot: diningText("火锅")
        case .barbecue: diningText("烧烤")
        case .sweets: diningText("甜品饮品")
        }
    }
    private func tripTitle(_ trip: DiningTrip) -> String {
        switch trip {
        case .unrestricted: diningText("不限路程")
        case .walk5: diningText("走路 5 分钟内")
        case .walk10: diningText("走路 10 分钟内")
        case .drive10: diningText("开车 10 分钟内")
        case .drive20: diningText("开车 20 分钟内")
        case .nearby2km: diningText("2 公里内")
        }
    }
    private func mealTitle(_ meal: DiningMeal) -> String {
        switch meal {
        case .breakfast: diningText("早餐推荐")
        case .lunch: diningText("午餐推荐")
        case .afternoonTea: diningText("下午茶推荐")
        case .dinner: diningText("晚餐推荐")
        }
    }
    private func reason(_ place: DiningPlace) -> String {
        if model.selection == .nearby { return diningText("优先挑选符合当前条件的近处餐厅。") }
        if model.selection == .random { return diningText("从符合当前条件的餐厅中随机挑选。") }
        switch model.resultMood {
        case .familiar: return (model.archive.habits[place.id]?.visits ?? 0) > 0 ? String(localized: "这家店在你的干饭记录里，熟悉的味道值得再试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "还没有常吃记录，先从附近这家开始。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .fresh: return (model.archive.habits[place.id]?.visits ?? 0) == 0 ? String(localized: "你的干饭记录里还没有这家，来点新鲜的！", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "附近的新选择有限，熟悉的店也保留机会。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .budget, .treat:
            return place.cost != nil
                ? String(localized: "按地图提供的人均价格挑选，实际消费以店家为准。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
                : String(localized: "按附近距离或以往选择推荐。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .spicy: return String(localized: "按店名与菜系线索挑选，具体辣度请向店家确认。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .automatic: return (model.archive.habits[place.id]?.visits ?? 0) > 0 ? String(localized: "这家店在你的干饭记录里，熟悉的味道值得再试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)) : String(localized: "从附近真实餐厅中，为你挑了这一家。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
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
                        HStack { VStack(alignment: .leading) { Text(place.name); Text(place.address).font(.caption).foregroundStyle(.secondary) }; Spacer(); Menu(String(localized: "导航", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                            Button(String(localized: "高德地图", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { model.navigate(place, driving: model.trip.driving, provider: "amap") }
                            Button(String(localized: "百度地图", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { model.navigate(place, driving: model.trip.driving, provider: "baidu") }
                            Button(String(localized: "苹果地图", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { model.navigate(place, driving: model.trip.driving) }
                        } }
                    }
                    if model.archive.favorites.isEmpty { Text(String(localized: "还没有收藏餐厅", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                }
                Section(String(localized: "干饭记录 · 当地时间", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) {
                    ForEach(model.archive.history) { choice in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(choice.place.name).font(.headline)
                            Text(choice.selectedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            if choice.checkedIn == true {
                                let count = model.archive.habits[choice.place.id]?.checkIns ?? 0
                                Label(diningText("累计打卡 \(count) 次"), systemImage: "checkmark.circle.fill").foregroundStyle(.orange)
                                if let type = choice.restaurantType { Text(type).font(.subheadline) }
                                if choice.place.provider == "manual" {
                                    Text(choice.place.address.isEmpty ? diningText("已记录定位，暂无地址") : choice.place.address)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } else if choice.eatenAt != nil { Label(String(localized: "吃过了", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), systemImage: "checkmark.circle.fill").foregroundStyle(.orange) }
                            else { Button(String(localized: "我吃过了", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) { _ = model.update { $0.confirmEaten(choice.id) } } }
                        }
                    }
                    if model.archive.history.isEmpty { Text(String(localized: "选好餐厅后，记录会保存在这里。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) }
                }
                if let syncMessage = model.syncMessage { Section { Text(syncMessage).font(.caption).foregroundStyle(.secondary) } }
                Section { Text(String(localized: "记录、收藏与偏好按账号跨设备同步；离线修改联网后自动合并。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))) .font(.caption).foregroundStyle(.secondary) }
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


private struct DiningCheckInSheet: View {
    @ObservedObject var model: DiningStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: DiningPlace?
    @State private var restaurantType = ""
    @State private var manual = false
    @State private var restaurantName = ""
    @State private var restaurantAddress = ""
    @State private var operation = UUID()
    @State private var saved = false

    var body: some View {
        NavigationStack {
            List {
                if manual {
                    Section {
                        TextField(diningText("餐厅名称"), text: $restaurantName)
                            .onChange(of: restaurantName) { _, name in
                                if name.count > 100 { restaurantName = String(name.prefix(100)) }
                            }
                        TextField(diningText("餐厅类型（选填）"), text: $restaurantType)
                        if model.manualPosition != nil {
                            Label(diningText("已获取当前位置"), systemImage: "location.fill")
                            TextField(diningText("地址（可修改）"), text: $restaurantAddress)
                        }
                        Button(model.manualPosition == nil ? diningText("获取当前位置") : diningText("重新定位")) {
                            restaurantAddress = ""
                            Task { await model.findCheckInPlaces(manual: true) }
                        }.disabled(model.checkingIn)
                        if model.checkingIn { ProgressView(diningText("正在定位…")) }

                    }
                    Button(diningText("返回附近餐厅")) {
                        model.closeCheckIn()
                        manual = false
                        Task { await model.findCheckInPlaces() }
                    }
                } else if model.checkingIn {
                    manualEntry
                    ProgressView(diningText("正在查找附近餐厅…"))
                } else if let selected {
                    Section {
                        Text(selected.name).font(.headline)
                        if !selected.address.isEmpty { Text(selected.address).foregroundStyle(.secondary) }
                        TextField(diningText("餐厅类型（选填）"), text: $restaurantType)
                        Button(diningText("确认打卡")) {
                            guard !saved else { return }
                            saved = model.checkIn(selected, operation: operation, restaurantType: restaurantType)
                            if saved { dismiss() }
                        }.disabled(saved)
                    }
                    Button(diningText("返回附近餐厅")) { self.selected = nil }
                } else {
                    manualEntry
                    Section(diningText("请选择你所在的餐厅")) {
                        ForEach(model.checkInPlaces) { place in
                            Button {
                                selected = place
                                restaurantType = ""
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.name).font(.headline)
                                    if !place.address.isEmpty { Text(place.address) }
                                    let distance = place.distanceMeters.formatted(.number.precision(.fractionLength(0)))
                                    Text(diningText("约 \(distance) 米"))
                                }.foregroundStyle(.primary)
                            }
                        }
                    }
                    Button(diningText("重新查找")) { Task { await model.findCheckInPlaces() } }
                }
                if let message = model.message { Text(message).foregroundStyle(.secondary) }
            }
            .onChange(of: model.manualAddress) { _, address in
                if manual && restaurantAddress.isEmpty { restaurantAddress = address }
            }
            .safeAreaInset(edge: .bottom) {
                if manual {
                    Button {
                        guard !saved, let position = model.manualPosition,
                              let place = model.archive.manualRestaurant(name: restaurantName, latitude: position.latitude,
                                  longitude: position.longitude, address: restaurantAddress) else { return }
                        saved = model.checkIn(place, operation: operation, restaurantType: restaurantType)
                        if saved { dismiss() }
                    } label: {
                        Text(diningText("确认打卡")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saved || model.manualPosition == nil || !validName)
                    .padding().background(.bar)
                }
            }
            .navigationTitle(diningText("到店打卡"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(diningText("取消")) { dismiss() }
                }
            }
        }
        .task { if !manual { await model.findCheckInPlaces() } }
    }

    private var validName: Bool {
        let name = restaurantName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...100).contains(name.count)
    }

    private var manualEntry: some View {
        Button(diningText("手动填写餐厅"), systemImage: "pencil.and.list.clipboard") {
            model.closeCheckIn()
            model.message = nil
            restaurantType = ""
            restaurantAddress = ""
            manual = true
        }
    }
}


// A native Menu does not honor per-row typography. Keep the existing trigger,
// and use a compact popover so all provider names have an explicit 18 pt size.
private struct DiningNavigationPicker: View {
    let select: (String) -> Void
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            Label(diningText("带我过去"), systemImage: "map").frame(maxWidth: .infinity)
        }
        .popover(isPresented: $presented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(spacing: 0) {
                Text(diningText("选择导航地图"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
                option("高德地图", detail: "打开高德地图规划路线", provider: "amap", symbol: "location.north.fill", color: .blue)
                Divider().padding(.leading, 64)
                option("百度地图", detail: "打开百度地图规划路线", provider: "baidu", symbol: "mappin.and.ellipse", color: .red)
                Divider().padding(.leading, 64)
                option("苹果地图", detail: "使用系统地图规划路线", provider: "apple", symbol: "map.fill", color: .green)
            }
            .frame(minWidth: 260, idealWidth: 304, maxWidth: 304)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 5)
            .padding(8)
            .presentationBackground(.clear)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func option(_ title: String.LocalizationValue, detail: String.LocalizationValue,
                        provider: String, symbol: String, color: Color) -> some View {
        Button {
            presented = false
            select(provider)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(diningText(title)).font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.88))
                    Text(diningText(detail)).font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.50))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.35)).accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(height: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
