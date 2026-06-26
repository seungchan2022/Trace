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

    func testLoopStrokeNotCollapsedToTwoPoints() {
        // 반지름 ~55m 원 (둘레 ≈ 346m) — 30도 간격 12포인트
        // 누적거리 기반이면 ≥3개 포인트가 나와야 함
        // 기존 구현(직선거리)에서는 원의 지름(~110m) < 120m이므로 [시작, 끝] 2개만 나옴
        let loop = makeCircleCoordinates(
            center: CourseCoordinate(latitude: 37.5, longitude: 127.0),
            radiusLatOffset: 0.0005,
            stepDegrees: 30
        )
        let result = DrawnPathSampler.sample(loop, minSpacingMeters: 120)
        XCTAssertGreaterThan(result.count, 2,
            "루프 획은 시작/끝 2개로 축소되어서는 안 됩니다. 실제 count: \(result.count)")
        XCTAssertEqual(result.first, loop.first, "시작점은 항상 보존")
        XCTAssertEqual(result.last, loop.last, "끝점은 항상 보존")
    }

    func testCumulativeDistancePreservesStrokeOrder() {
        let loop = makeCircleCoordinates(
            center: CourseCoordinate(latitude: 37.5, longitude: 127.0),
            radiusLatOffset: 0.0005,
            stepDegrees: 30
        )
        let result = DrawnPathSampler.sample(loop, minSpacingMeters: 120)
        // 결과 포인트들이 원본 배열에서 단조증가 인덱스로 등장해야 함
        var lastIndex = -1
        for point in result {
            if let idx = loop.firstIndex(of: point) {
                XCTAssertGreaterThan(idx, lastIndex,
                    "샘플 포인트가 원본 획의 순서를 따라야 합니다")
                lastIndex = idx
            }
        }
    }

    // MARK: - Helpers

    private func makeCircleCoordinates(
        center: CourseCoordinate,
        radiusLatOffset: Double,
        stepDegrees: Double
    ) -> [CourseCoordinate] {
        // longitude 보정: 위도에 따라 경도 1도의 실제 거리가 줄어드므로 보정
        let lonScale = cos(center.latitude * .pi / 180)
        return stride(from: 0.0, to: 360.0, by: stepDegrees).map { angle in
            let rad = angle * .pi / 180
            return CourseCoordinate(
                latitude: center.latitude + radiusLatOffset * cos(rad),
                longitude: center.longitude + (radiusLatOffset / lonScale) * sin(rad)
            )
        }
    }
}
