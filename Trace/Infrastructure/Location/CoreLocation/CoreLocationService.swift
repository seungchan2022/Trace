import CoreLocation
import Foundation

@MainActor
final class CoreLocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CourseCoordinate, Error>?

    func currentLocation() async throws -> CourseCoordinate {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .restricted, .denied:
                finish(.failure(LocationError.denied))
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            @unknown default:
                finish(.failure(LocationError.unavailable))
            }
        }
    }

    private func finish(_ result: Result<CourseCoordinate, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
            case .restricted, .denied: finish(.failure(LocationError.denied))
            case .notDetermined: break
            @unknown default: finish(.failure(LocationError.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        let coord = CourseCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        Task { @MainActor in self.finish(.success(coord)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(LocationError.unavailable)) }
    }
}
