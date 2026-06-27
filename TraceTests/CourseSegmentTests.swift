import XCTest
@testable import Trace

final class CourseSegmentTests: XCTestCase {
    private let a = CourseCoordinate(latitude: 37.5, longitude: 127.0)
    private let b = CourseCoordinate(latitude: 37.6, longitude: 127.0)

    func testTappedCoordinates() {
        let seg = CourseSegment.tapped(coordinates: [a, b], distanceMeters: 100)
        XCTAssertEqual(seg.coordinates, [a, b])
    }

    func testTappedDistance() {
        let seg = CourseSegment.tapped(coordinates: [a, b], distanceMeters: 500)
        XCTAssertEqual(seg.distanceMeters, 500)
    }

    func testDrawnCoordinates() {
        let seg = CourseSegment.drawn(coordinates: [a, b], distanceMeters: 200)
        XCTAssertEqual(seg.coordinates, [a, b])
    }

    func testDrawnDistance() {
        let seg = CourseSegment.drawn(coordinates: [a, b], distanceMeters: 200)
        XCTAssertEqual(seg.distanceMeters, 200)
    }

    func testEquality() {
        let seg1 = CourseSegment.tapped(coordinates: [a], distanceMeters: 100)
        let seg2 = CourseSegment.tapped(coordinates: [a], distanceMeters: 100)
        XCTAssertEqual(seg1, seg2)
    }
}
