import XCTest
@testable import Trace

final class CourseCoordinateGeoTests: XCTestCase {
    private let base = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)

    /// base에서 동쪽 east(m), 북쪽 north(m) 이동한 좌표
    private func point(east: Double, north: Double) -> CourseCoordinate {
        CourseCoordinate(
            latitude: base.latitude + north / 111_320.0,
            longitude: base.longitude + east / (111_320.0 * cos(base.latitude * .pi / 180))
        )
    }

    // MARK: - distanceMeters(toSegment:)

    func testPointToSegmentUsesPerpendicularDistanceInsideSpan() {
        // 선분: 동쪽으로 0m→100m. 점: 선분 중간(동쪽 50m)에서 북쪽 8m
        let a = point(east: 0, north: 0)
        let b = point(east: 100, north: 0)
        let p = point(east: 50, north: 8)
        XCTAssertEqual(p.distanceMeters(toSegment: a, b), 8, accuracy: 0.5)
    }

    func testPointToSegmentClampsToNearestEndpointOutsideSpan() {
        // 선분 밖(동쪽 130m, 북쪽 0m) → 가까운 끝점 b(동쪽 100m)까지 30m
        let a = point(east: 0, north: 0)
        let b = point(east: 100, north: 0)
        let p = point(east: 130, north: 0)
        XCTAssertEqual(p.distanceMeters(toSegment: a, b), 30, accuracy: 0.5)
    }

    func testPointToDegenerateSegmentFallsBackToPointDistance() {
        // a == b (길이 0 선분)
        let a = point(east: 10, north: 0)
        let p = point(east: 10, north: 5)
        XCTAssertEqual(p.distanceMeters(toSegment: a, a), 5, accuracy: 0.5)
    }

    // MARK: - offset(rightOfHeading:by:)

    func testOffsetRightOfEastHeadingMovesSouth() {
        // 동쪽 진행의 오른쪽 = 남쪽
        let moved = base.offset(rightOfHeading: (dxEast: 1, dyNorth: 0), by: 4)
        XCTAssertEqual(base.distanceMeters(to: moved), 4, accuracy: 0.1)
        XCTAssertLessThan(moved.latitude, base.latitude)
    }

    func testOffsetRightOfWestHeadingMovesNorth() {
        // 서쪽 진행(왕복의 돌아오는 방향)의 오른쪽 = 북쪽 — 가는 선의 반대편
        let moved = base.offset(rightOfHeading: (dxEast: -1, dyNorth: 0), by: 4)
        XCTAssertEqual(base.distanceMeters(to: moved), 4, accuracy: 0.1)
        XCTAssertGreaterThan(moved.latitude, base.latitude)
    }

    func testZeroHeadingOrZeroMetersReturnsSelf() {
        XCTAssertEqual(base.offset(rightOfHeading: (dxEast: 0, dyNorth: 0), by: 4), base)
        XCTAssertEqual(base.offset(rightOfHeading: (dxEast: 1, dyNorth: 0), by: 0), base)
    }

    // MARK: - headingVector(to:)

    func testHeadingVectorEastward() {
        let heading = base.headingVector(to: point(east: 100, north: 0))
        XCTAssertEqual(heading.dxEast, 100, accuracy: 1)
        XCTAssertEqual(heading.dyNorth, 0, accuracy: 1)
    }
}
