import CoreLocation
import Foundation

@MainActor
final class CoreLocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    // 부트스트랩(.task)과 "내 위치로 이동" 버튼이 겹쳐 호출될 수 있어, 진행 중인 요청이 있으면
    // 새 요청을 거부하는 대신 같은 결과를 함께 기다리게 한다. (겹쳐 호출 시 즉시 실패 버그 수정)
    private let broadcaster = ContinuationBroadcaster<CourseCoordinate>()

    func currentLocation() async throws -> CourseCoordinate {
        try await withCheckedThrowingContinuation { continuation in
            guard broadcaster.addWaiter(continuation) else { return }
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
        broadcaster.resumeAll(with: result)
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
