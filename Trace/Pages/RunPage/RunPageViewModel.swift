import Foundation
import MapKit
import Observation
import SwiftUI

@MainActor
@Observable
final class RunPageViewModel {
    let session: RunSession

    var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    private(set) var displayedCoordinates: [CLLocationCoordinate2D] = []
    var showsAccuracyAlert = false
    var showsPermissionAlert = false
    /// 요약 화면에 보여줄 벽시계 경과 시간 — 트래킹 화면·Live Activity가 보여준 시간과 같은 기준(스펙 리뷰 Fix 2).
    /// `RunTrack.duration`(GPS 샘플 구간)과는 다른 측정치라 별도로 종료 시점에 캡처해 둔다.
    private(set) var summaryElapsedSeconds: TimeInterval?
    private var polylineThrottle = PolylineThrottle()

    init(session: RunSession) {
        self.session = session
    }

    func startTapped() async {
        await session.start()
        switch session.lastStartFailure {
        case .reducedAccuracy: showsAccuracyAlert = true
        case .permissionDenied: showsPermissionAlert = true
        case nil:
            displayedCoordinates = []
            polylineThrottle = PolylineThrottle()
            recenter()
        }
    }

    func endRun() {
        if let startedAt = session.startedAt {
            summaryElapsedSeconds = Date().timeIntervalSince(startedAt)
        }
        session.finish()
        // 요약: 경로 전체가 보이도록 카메라 핏
        let coordinates = session.track.samples.map(\.coordinate)
        displayedCoordinates = coordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        if let region = Self.fittingRegion(for: displayedCoordinates) {
            cameraPosition = .region(region)
        }
    }

    func closeSummary() {
        session.dismissSummary()
        displayedCoordinates = []
        recenter()
    }

    /// 세션 샘플 수 변화 시 View의 onChange에서 호출 — 스로틀을 통과할 때만 폴리라인 재구성
    func refreshPolylineIfDue(now: Date = Date()) {
        guard session.state == .tracking else { return }
        guard polylineThrottle.shouldRefresh(
            now: now, totalDistanceMeters: session.track.totalDistanceMeters
        ) else { return }
        displayedCoordinates = session.track.samples.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    func recenter() {
        cameraPosition = .userLocation(fallback: .automatic)
    }

    func cancelAcquiring() {
        session.finishAcquiringCancelled()
    }

    private static func fittingRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude); maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude); maxLon = max(maxLon, coordinate.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
            )
        )
    }
}
