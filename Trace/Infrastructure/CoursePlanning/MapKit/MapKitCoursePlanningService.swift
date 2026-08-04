import CoreLocation
import Foundation
import MapKit

@MainActor
final class MapKitCoursePlanningService: CoursePlanningServiceProtocol {
    private var cache: [String: PlannedCourse] = [:]

    // ⚠️ 클래스의 @MainActor와 중복이 아니다 — 지우면 컴파일이 깨진다.
    // nonisolated한 async 프로토콜 요구사항을 witness하면 클래스 @MainActor가 이 멤버에
    // 적용되지 않는다(SE-0461 + SWIFT_APPROACHABLE_CONCURRENCY). 명시가 추론을 이긴다.
    // 지워도 되는지 확인하는 법: 이 줄을 지우고 빌드한다. 통과하면 Swift가 바뀐 것이다.
    // 근거·해법 매트릭스: docs/solutions/conventions/mainactor-witness-inference-overrides-class-isolation.md
    @MainActor
    func route(
        from start: CourseCoordinate,
        to destination: CourseCoordinate
    ) async throws -> PlannedCourse {
        let key = cacheKey(from: start, to: destination)
        if let cached = cache[key] { return cached }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(start)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(destination)))
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw CoursePlanningError.routeNotFound
            }

            var coordinates = Array(
                repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                count: route.polyline.pointCount
            )
            route.polyline.getCoordinates(
                &coordinates,
                range: NSRange(location: 0, length: route.polyline.pointCount)
            )

            let result = PlannedCourse(
                segments: [.tapped(
                    coordinates: coordinates.map(CourseCoordinate.init),
                    distanceMeters: route.distance
                )]
            )
            cache[key] = result
            return result
        } catch let error as CoursePlanningError {
            throw error
        } catch {
            let nsError = error as NSError
            let isThrottled =
                (nsError.domain == "GEOErrorDomain" && nsError.code == -3) ||
                (nsError.domain == "MKErrorDomain" && nsError.code == 3) ||
                (nsError.domain == MKError.errorDomain && nsError.code == MKError.loadingThrottled.rawValue)
            if isThrottled {
                throw CoursePlanningError.throttled
            }
            #if DEBUG
            print("[MapKitCoursePlanning] Unhandled error: "
                  + "domain=\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
            #endif
            throw CoursePlanningError.requestFailed
        }
    }

    private func cacheKey(from start: CourseCoordinate, to end: CourseCoordinate) -> String {
        let startKey = "\(round(start.latitude, 5)),\(round(start.longitude, 5))"
        let endKey = "\(round(end.latitude, 5)),\(round(end.longitude, 5))"
        return "\(startKey)->\(endKey)"
    }

    private func round(_ value: Double, _ places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (value * multiplier).rounded() / multiplier
    }
}

private extension CLLocationCoordinate2D {
    init(_ coordinate: CourseCoordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

private extension CourseCoordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
