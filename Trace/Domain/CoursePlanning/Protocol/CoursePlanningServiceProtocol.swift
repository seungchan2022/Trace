import Foundation

@MainActor
protocol CoursePlanningServiceProtocol {
    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse
    func snappedRoute(through points: [CourseCoordinate]) async throws -> PlannedCourse
}

extension CoursePlanningServiceProtocol {
    /// 그린 마커 좌표열을 인접 구간 도보 경로로 이어붙여 하나의 코스로 만든다.
    func snappedRoute(through points: [CourseCoordinate]) async throws -> PlannedCourse {
        guard points.count >= 2 else { throw CoursePlanningError.routeNotFound }

        var coordinates: [CourseCoordinate] = []
        var distance = 0.0
        for index in 0..<(points.count - 1) {
            let leg = try await routeWithRetry(from: points[index], to: points[index + 1])
            // 구간 접합부 좌표 중복 제거
            coordinates.append(contentsOf: coordinates.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst()))
            distance += leg.distanceMeters
        }
        return PlannedCourse(coordinates: coordinates, distanceMeters: distance)
    }

    private func routeWithRetry(
        from start: CourseCoordinate,
        to destination: CourseCoordinate,
        attempts: Int = 2
    ) async throws -> PlannedCourse {
        var lastError: Error = CoursePlanningError.requestFailed
        for attempt in 0..<attempts {
            do {
                return try await route(from: start, to: destination)
            } catch CoursePlanningError.throttled {
                throw CoursePlanningError.throttled
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
        throw lastError
    }
}
