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

    func testRoundTripCase_exposesCoordinatesAndDistance() {
        let a = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
        let b = CourseCoordinate(latitude: 37.5670, longitude: 126.9790)
        let seg = CourseSegment.roundTrip(coordinates: [b, a, b], distanceMeters: 240)
        XCTAssertEqual(seg.coordinates, [b, a, b])
        XCTAssertEqual(seg.distanceMeters, 240)
        XCTAssertTrue(seg.isRoundTrip)
        XCTAssertFalse(CourseSegment.tapped(coordinates: [a, b], distanceMeters: 120).isRoundTrip)
    }

    func testRoundTripReversed_reversesCoordinatesKeepingCase() {
        let a = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
        let b = CourseCoordinate(latitude: 37.5670, longitude: 126.9790)
        let c = CourseCoordinate(latitude: 37.5675, longitude: 126.9795)
        let reversed = CourseSegment.roundTrip(coordinates: [a, b, c], distanceMeters: 240).reversed()
        XCTAssertEqual(reversed, .roundTrip(coordinates: [c, b, a], distanceMeters: 240))
    }
}
