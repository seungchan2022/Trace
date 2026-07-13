import CoreLocation
import Foundation

/// 러닝용 연속 위치 스트림 — 기존 CoreLocationService(단발 조회)와 별개.
/// CLLocationManager는 런루프 있는 스레드 생성이 필요해 기존 선례대로 @MainActor 격리(스펙 §4).
@MainActor
final class RunLocationTracker: NSObject, RunLocationStreamProtocol, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: AsyncStream<RunSample>.Continuation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.distanceFilter = 5
    }

    func currentAccuracy() -> RunLocationAccuracy {
        manager.accuracyAuthorization == .fullAccuracy ? .full : .reduced
    }

    func requestSessionFullAccuracy() async -> RunLocationAccuracy {
        // purposeKey는 Config/Trace-Info.plist의 NSLocationTemporaryUsageDescriptionDictionary 키와 일치해야 한다
        try? await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "RunTracking")
        return currentAccuracy()
    }

    func startUpdates() -> AsyncStream<RunSample> {
        let (stream, continuation) = AsyncStream.makeStream(of: RunSample.self)
        self.continuation = continuation
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization() // 결과는 didChangeAuthorization에서
        case .restricted, .denied:
            finishStream()
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdating()
        @unknown default:
            finishStream()
        }
        return stream
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        finishStream()
    }

    private func beginUpdating() {
        // Background Modes(location) capability가 있어야 크래시 없이 동작(Task 3 Step 1)
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    private func finishStream() {
        continuation?.finish()
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse: self.beginUpdating()
            case .restricted, .denied: self.stopUpdates() // 러닝 도중 회수 포함 — 스트림 종료로 전파
            case .notDetermined: break
            @unknown default: self.stopUpdates()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map { location in
            RunSample(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitudeMeters: location.altitude,
                speedMetersPerSecond: location.speed,
                horizontalAccuracyMeters: location.horizontalAccuracy,
                verticalAccuracyMeters: location.verticalAccuracy
            )
        }
        Task { @MainActor in
            for sample in samples { self.continuation?.yield(sample) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let isDenied = (error as? CLError)?.code == .denied
        Task { @MainActor in
            if isDenied { self.stopUpdates() }
            // 일시적 위치 실패(kCLErrorLocationUnknown 등)는 무시 — 스트림 유지, 필터가 처리
        }
    }
}
