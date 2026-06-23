import XCTest
@testable import Trace

@MainActor
final class RouteCacheTests: XCTestCase {
    func testCacheHitSkipsAPICall() async throws {
        let service = SpyMapKitService()
        let start = CourseCoordinate(latitude: 37.50000, longitude: 127.00000)
        let end = CourseCoordinate(latitude: 37.51000, longitude: 127.00000)

        let first = try await service.route(from: start, to: end)
        let second = try await service.route(from: start, to: end)

        XCTAssertEqual(service.apiCallCount, 1)
        XCTAssertEqual(first, second)
    }

    func testCacheMissCallsAPI() async throws {
        let service = SpyMapKitService()
        let a = CourseCoordinate(latitude: 37.50000, longitude: 127.00000)
        let b = CourseCoordinate(latitude: 37.51000, longitude: 127.00000)
        let c = CourseCoordinate(latitude: 37.52000, longitude: 127.00000)

        _ = try await service.route(from: a, to: b)
        _ = try await service.route(from: b, to: c)

        XCTAssertEqual(service.apiCallCount, 2)
    }

    func testRoundingMatchesNearbyCoordinates() async throws {
        let service = SpyMapKitService()
        let start1 = CourseCoordinate(latitude: 37.500001, longitude: 127.000002)
        let end1 = CourseCoordinate(latitude: 37.510003, longitude: 127.000001)
        let start2 = CourseCoordinate(latitude: 37.500004, longitude: 127.000004)
        let end2 = CourseCoordinate(latitude: 37.510001, longitude: 127.000004)

        _ = try await service.route(from: start1, to: end1)
        _ = try await service.route(from: start2, to: end2)

        XCTAssertEqual(service.apiCallCount, 1) // 소수점 5자리 라운딩 → 같은 키
    }
}

@MainActor
private final class SpyMapKitService: CoursePlanningServiceProtocol {
    var apiCallCount = 0
    private var cache: [String: PlannedCourse] = [:]

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        let key = cacheKey(from: start, to: destination)
        if let cached = cache[key] { return cached }
        apiCallCount += 1
        let result = PlannedCourse(coordinates: [start, destination], distanceMeters: 100)
        cache[key] = result
        return result
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
