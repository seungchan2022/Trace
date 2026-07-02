import XCTest
@testable import Trace

final class OverlapOffsetResolverTests: XCTestCase {
    private let base = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)

    private func point(east: Double, north: Double) -> CourseCoordinate {
        CourseCoordinate(
            latitude: base.latitude + north / 111_320.0,
            longitude: base.longitude + east / (111_320.0 * cos(base.latitude * .pi / 180))
        )
    }

    /// 동서 방향 직선 경로 (from → to, spacing 간격)
    private func line(fromEast: Double, toEast: Double, north: Double, spacing: Double) -> [CourseCoordinate] {
        let step: Double = fromEast <= toEast ? spacing : -spacing
        var coords: [CourseCoordinate] = []
        var east = fromEast
        while (step > 0 && east <= toEast) || (step < 0 && east >= toEast) {
            coords.append(point(east: east, north: north))
            east += step
        }
        return coords
    }

    private func segment(_ coords: [CourseCoordinate]) -> CourseSegment {
        .tapped(coordinates: coords, distanceMeters: 0)
    }

    /// 대응 점끼리의 평균 이동 거리(미터) — run 중앙부만 (테이퍼 경계 제외)
    private func midDisplacement(_ original: [CourseCoordinate], _ display: [CourseCoordinate]) -> Double {
        let mid = original.count / 2
        return original[mid].distanceMeters(to: display[mid])
    }

    // MARK: - 기본 동작

    func testNonOverlappingSegmentsUnchanged() {
        let a = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let b = segment(line(fromEast: 0, toEast: 200, north: 100, spacing: 10)) // 100m 떨어진 평행선
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [a, b], colorKeys: [0, 1], parameters: .init()
        )
        XCTAssertEqual(display[0], a.coordinates)
        XCTAssertEqual(display[1], b.coordinates)
    }

    func testOutAndBackOffsetsLaterCreatedSegmentOnly() {
        // 가는 길(동쪽 0→200m), 오는 길(동쪽 200→0m, 같은 도로)
        let outbound = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let inbound = segment(line(fromEast: 200, toEast: 0, north: 0, spacing: 10))
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [outbound, inbound], colorKeys: [0, 1], parameters: .init()
        )
        // 먼저 생성(colorKey 0)된 가는 길은 도로 위 유지
        XCTAssertEqual(display[0], outbound.coordinates)
        // 오는 길 중앙부는 약 4m 이동
        XCTAssertEqual(midDisplacement(inbound.coordinates, display[1]), 4, accuracy: 1.0)
        // 서쪽 진행의 오른쪽 = 북쪽으로 밀림
        let mid = inbound.coordinates.count / 2
        XCTAssertGreaterThan(display[1][mid].latitude, inbound.coordinates[mid].latitude)
    }

    func testPrependKeepsEarlierCreatedSegmentOnRoad() {
        // 공간 순서 ≠ 생성 순서: 새 구간(colorKey 1)이 prepend되어 배열 맨 앞
        let older = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))    // colorKey 0
        let prepended = segment(line(fromEast: 200, toEast: 0, north: 0, spacing: 10)) // colorKey 1
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [prepended, older], colorKeys: [1, 0], parameters: .init()
        )
        // 먼저 생성된 구간(공간상 뒤)이 도로 위에 남고, prepend된 새 구간이 밀린다
        XCTAssertEqual(display[1], older.coordinates)
        XCTAssertEqual(midDisplacement(prepended.coordinates, display[0]), 4, accuracy: 1.0)
    }

    func testTripleOverlapUsesMultipliedOffset() {
        let first = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let second = segment(line(fromEast: 200, toEast: 0, north: 0, spacing: 10))
        let third = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [first, second, third], colorKeys: [0, 1, 2], parameters: .init()
        )
        XCTAssertEqual(display[0], first.coordinates)
        XCTAssertEqual(midDisplacement(second.coordinates, display[1]), 4, accuracy: 1.0)
        // 세 번째 통과는 앞선 2개와 겹침 → 8m
        XCTAssertEqual(midDisplacement(third.coordinates, display[2]), 8, accuracy: 1.5)
    }

    // MARK: - 감지 방식 (점-대-선분)

    func testSparseVertexPolylineStillDetected() {
        // 라우팅 선처럼 정점이 희소(100m 간격)한 직선 + 그 위를 지나는 조밀(5m)한 그리기 스트로크
        let sparse = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 100)) // 정점 3개
        let dense = segment(line(fromEast: 200, toEast: 0, north: 2, spacing: 5))    // 2m 옆, 점-대-점이면 최대 50m
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [sparse, dense], colorKeys: [0, 1], parameters: .init()
        )
        XCTAssertGreaterThan(midDisplacement(dense.coordinates, display[1]), 3)
    }

    func testShortNoiseCrossingIgnored() {
        // 수직 교차: 임계 안에 드는 점이 1~2개뿐 → run 필터로 무시
        let horizontal = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let crossingCoords = (0...20).map { point(east: 100, north: Double($0) * 10 - 100) } // 남→북 수직선
        let crossing = segment(crossingCoords)
        let display = OverlapOffsetResolver.displayCoordinates(
            segments: [horizontal, crossing], colorKeys: [0, 1], parameters: .init()
        )
        XCTAssertEqual(display[1], crossing.coordinates)
    }

    // MARK: - 불변성

    func testOriginalSegmentsUntouched() {
        let outbound = segment(line(fromEast: 0, toEast: 200, north: 0, spacing: 10))
        let inbound = segment(line(fromEast: 200, toEast: 0, north: 0, spacing: 10))
        let originalInboundCoords = inbound.coordinates
        _ = OverlapOffsetResolver.displayCoordinates(
            segments: [outbound, inbound], colorKeys: [0, 1], parameters: .init()
        )
        XCTAssertEqual(inbound.coordinates, originalInboundCoords)
    }
}
