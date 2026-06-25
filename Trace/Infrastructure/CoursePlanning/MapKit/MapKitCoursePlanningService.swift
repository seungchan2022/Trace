import CoreLocation
import Foundation
import MapKit

final class MapKitCoursePlanningService: CoursePlanningServiceProtocol {
    private var cache: [String: PlannedCourse] = [:]

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
                coordinates: coordinates.map(CourseCoordinate.init),
                distanceMeters: route.distance
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
            print("[MapKitCoursePlanning] Unhandled error: domain=\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
            #endif
            throw CoursePlanningError.requestFailed
        }
    }

    private func cacheKey(from start: CourseCoordinate, to end: CourseCoordinate) -> String {
        let s = "\(round(start.latitude, 5)),\(round(start.longitude, 5))"
        let e = "\(round(end.latitude, 5)),\(round(end.longitude, 5))"
        return "\(s)->\(e)"
    }

    private func round(_ value: Double, _ places: Int) -> Double {
        let m = pow(10.0, Double(places))
        return (value * m).rounded() / m
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
