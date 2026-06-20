import XCTest
@testable import Trace

final class DrawnPathSamplerTests: XCTestCase {
    func testEmptyReturnsEmpty() {
        XCTAssertTrue(DrawnPathSampler.sample([], minSpacingMeters: 120).isEmpty)
    }

    func testSinglePointPreserved() {
        let p = CourseCoordinate(latitude: 37.5, longitude: 127.0)
        XCTAssertEqual(DrawnPathSampler.sample([p], minSpacingMeters: 120), [p])
    }

    func testEndpointsAlwaysPreservedEvenIfClose() {
        let a = CourseCoordinate(latitude: 37.5000, longitude: 127.0000)
        let b = CourseCoordinate(latitude: 37.5001, longitude: 127.0000) // ~11m
        XCTAssertEqual(DrawnPathSampler.sample([a, b], minSpacingMeters: 120), [a, b])
    }

    func testDownsamplesByMinSpacing() {
        // 위도 0.001 ≈ 111m 간격으로 5점 → 120m 간격 다운샘플 시 중간 점들이 솎임
        let raw = (0..<5).map { CourseCoordinate(latitude: 37.5 + Double($0) * 0.001, longitude: 127.0) }
        let result = DrawnPathSampler.sample(raw, minSpacingMeters: 120)
        XCTAssertEqual(result.first, raw.first)
        XCTAssertEqual(result.last, raw.last)
        XCTAssertLessThan(result.count, raw.count)
        // 인접 결과 간 간격이 모두 최소 간격 이상(끝점 보정 구간 제외)
        for i in 0..<(result.count - 2) {
            XCTAssertGreaterThanOrEqual(result[i].distanceMeters(to: result[i + 1]), 120)
        }
    }
}
