import Foundation
import MapKit

@main struct DiningMapSearchCheck {
    static func main() async throws {
        // Public city-center fixture, not the user's location or a simulated restaurant list.
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurant"
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737), latitudinalMeters: 6000, longitudinalMeters: 6000)
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant])
        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: 31.2304, longitude: 121.4737)
        let real = response.mapItems.filter {
            guard !($0.name ?? "").isEmpty, let location = $0.placemark.location else { return false }
            return origin.distance(from: location) <= 3000
        }
        guard !real.isEmpty else { throw NSError(domain: "DiningMapSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: "No real restaurants returned for public test area"]) }
        print("PASS: live Apple Maps returned \(real.count) real restaurants for the public city-center test area")
    }
}
