#if os(macOS) && !PUBLIC_API_ONLY
import CoreLocation
import TopologyCore

/// One-shot Core Location fetch that backs Clock Mode's "Use current location" button. Best-effort:
/// on denial, restriction, or any error the completion is called with nil and the user falls back to
/// entering latitude/longitude by hand. Kilometre accuracy is plenty — solar anchors move by well
/// under a minute across a city.
final class ClockLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pendingCompletion: ((GeoCoordinate?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Requests a single location fix, prompting for permission the first time. Core Location
    /// delivers its delegate callbacks on the main thread (the manager is created there), so
    /// `completion` runs on the main thread exactly once.
    func requestOnce(_ completion: @escaping (GeoCoordinate?) -> Void) {
        guard pendingCompletion == nil else {
            completion(nil)
            return
        }
        pendingCompletion = completion
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()  // resolves via the delegate below
        default:
            finish(with: nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pendingCompletion != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            return  // still waiting on the user's choice
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        default:
            finish(with: nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            finish(with: nil)
            return
        }
        finish(with: GeoCoordinate(latitude: location.coordinate.latitude,
                                   longitude: location.coordinate.longitude))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }

    private func finish(with coordinate: GeoCoordinate?) {
        guard let completion = pendingCompletion else { return }
        pendingCompletion = nil
        completion(coordinate)
    }
}
#endif
