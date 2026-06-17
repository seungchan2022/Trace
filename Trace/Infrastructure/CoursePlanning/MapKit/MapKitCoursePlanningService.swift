import CoreLocation
import Foundation
import MapKit

final class MapKitCoursePlanningService: CoursePlanningServiceProtocol {
    func route(
        from start: CourseCoordinate,
        to destination: CourseCoordinate
    ) async throws -> PlannedCourse {
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

            return PlannedCourse(
                coordinates: coordinates.map(CourseCoordinate.init),
                distanceMeters: route.distance
            )
        } catch let error as CoursePlanningError {
            throw error
        } catch {
            throw CoursePlanningError.requestFailed
        }
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
