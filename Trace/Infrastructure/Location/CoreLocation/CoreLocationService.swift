import CoreLocation
import Foundation

@MainActor
final class CoreLocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    // 부트스트랩(.task)과 "내 위치로 이동" 버튼이 겹쳐 호출될 수 있어, 진행 중인 요청이 있으면
    // 새 요청을 거부하는 대신 같은 결과를 함께 기다리게 한다. (겹쳐 호출 시 즉시 실패 버그 수정)
    private let broadcaster = ContinuationBroadcaster<CourseCoordinate>()

    // ⚠️ 클래스의 @MainActor와 중복이 아니다 — 지우면 컴파일이 깨진다.
    // nonisolated한 async 프로토콜 요구사항을 witness하면 클래스 @MainActor가 이 멤버에
    // 적용되지 않는다(SE-0461 + SWIFT_APPROACHABLE_CONCURRENCY). 명시가 추론을 이긴다.
    // 지워도 되는지 확인하는 법: 이 줄을 지우고 빌드한다. 통과하면 Swift가 바뀐 것이다.
    // 근거·해법 매트릭스: docs/solutions/conventions/mainactor-witness-inference-overrides-class-isolation.md
    @MainActor
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
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedAlways, .authorizedWhenInUse: self.manager.requestLocation()
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
