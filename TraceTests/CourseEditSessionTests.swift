import XCTest
@testable import Trace

@MainActor
final class CourseEditSessionTests: XCTestCase {
    private let A = CourseCoordinate(latitude: 37.50, longitude: 127.00)
    private let B = CourseCoordinate(latitude: 37.51, longitude: 127.00)
    private let C = CourseCoordinate(latitude: 37.52, longitude: 127.00)
    private let D = CourseCoordinate(latitude: 37.53, longitude: 127.00)

    // MARK: - reversed()

    func testReversedTapped() {
        let seg = CourseSegment.tapped(coordinates: [A, B], distanceMeters: 100)
        let rev = seg.reversed()
        XCTAssertEqual(rev.coordinates, [B, A])
        XCTAssertEqual(rev.distanceMeters, 100)
    }

    func testReversedDrawn() {
        let seg = CourseSegment.drawn(coordinates: [A, B, C], distanceMeters: 200)
        let rev = seg.reversed()
        XCTAssertEqual(rev.coordinates, [C, B, A])
    }

    // MARK: - attach: no existing course

    func testAttachFirstSegment_appendsDirectly() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let seg = CourseSegment.tapped(coordinates: [A, B], distanceMeters: 100)
        try await session.attach(seg, using: service)
        XCTAssertEqual(session.segments.count, 1)
        XCTAssertEqual(session.segments.first?.coordinates.first, A)
        XCTAssertEqual(session.segments.first?.coordinates.last, B)
        XCTAssertEqual(service.routeCallCount, 0, "gap 라우팅 없어야 함")
    }

    // MARK: - attach: append (new start near existing end)

    func testAttach_appendNoGap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        // New: B→C (start near existing end B → append, no gap)
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        try await session.attach(.tapped(coordinates: [near_B, C], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, A)
    }

    // MARK: - attach: prepend (new end near existing start)

    func testAttach_prependNoGap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: B→C
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        // New: A→B (end near existing start B → prepend, no gap)
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        try await session.attach(.tapped(coordinates: [A, near_B], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        // prepend되므로 전체 경로 시작이 A여야 함
        XCTAssertEqual(session.course?.coordinates.first, A)
    }

    // MARK: - attach: reversed append (new end near existing end)

    func testAttach_reversedAppend() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        // New: C→B (end near existing end B → reverse to B→C, then append)
        let near_B = CourseCoordinate(latitude: B.latitude + 0.0001, longitude: B.longitude)
        try await session.attach(.tapped(coordinates: [C, near_B], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        // 두 번째 세그먼트는 reversed되어 near_B→C 순서여야 함
        XCTAssertEqual(session.segments.last?.coordinates.last, C)
    }

    // MARK: - undo

    func testUndo_removesLastSegment() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 2)
        session.undo()
        XCTAssertEqual(session.segments.count, 1)
    }

    func testUndo_empty_doesNothing() {
        let session = CourseEditSession()
        session.undo()
        XCTAssertTrue(session.segments.isEmpty)
    }

    // MARK: - clear

    func testClear_removesAll() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        session.clear()
        XCTAssertTrue(session.segments.isEmpty)
        XCTAssertNil(session.course)
    }

    // MARK: - undo is exact unit (no dangling gap)

    func testUndo_withGap_removesGapAndSegmentTogether() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        // 거리가 먼 곳 C→D (gap B→C 라우팅됨)
        try await session.attach(.tapped(coordinates: [C, D], distanceMeters: 100), using: service)
        // undo → gap+segment 합쳐진 하나가 제거되어야 함
        session.undo()
        XCTAssertEqual(session.segments.count, 1, "gap이 병합됐으므로 undo 1번에 하나만 남아야 함")
        XCTAssertEqual(session.course?.coordinates.last, B)
    }

    // MARK: - undo after prepend (시간순 vs 공간순)

    func testUndo_afterPrepend_removesMostRecentlyAttachedNotSpatialLast() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // Seed: A→B, then B→C (append) → 공간 순서: A-B-C
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        // D→A를 prepend (기존 시작 A 근처) → 공간 순서: D-A-B-C, 하지만 시간상 가장 최근 attach는 D→A
        let near_A = CourseCoordinate(latitude: A.latitude - 0.0001, longitude: A.longitude)
        try await session.attach(.tapped(coordinates: [D, near_A], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segments.count, 3)
        XCTAssertEqual(session.course?.coordinates.first, D)

        session.undo()

        XCTAssertEqual(session.segments.count, 2, "가장 최근 attach(D→A)만 제거되어야 함")
        XCTAssertEqual(session.course?.coordinates.first, A, "prepend로 붙인 최근 세그먼트가 제거되어야 함")
        XCTAssertEqual(session.course?.coordinates.last, C, "공간적 마지막 세그먼트(B→C)는 남아있어야 함")
    }

    // MARK: - segmentColorKeys (attach 순서 기반, prepend에도 안정적)

    func testSegmentColorKeys_stableAcrossPrepend() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(.tapped(coordinates: [A, B], distanceMeters: 100), using: service)
        try await session.attach(.tapped(coordinates: [B, C], distanceMeters: 100), using: service)
        XCTAssertEqual(session.segmentColorKeys, [0, 1])

        let near_A = CourseCoordinate(latitude: A.latitude - 0.0001, longitude: A.longitude)
        try await session.attach(.tapped(coordinates: [D, near_A], distanceMeters: 100), using: service)

        // prepend는 배열 맨 앞에 삽입되지만, colorKey(생성 순서)는 기존 세그먼트의 것이 유지되어야 함
        XCTAssertEqual(session.segmentColorKeys, [2, 0, 1])
    }
}

// MARK: - Stub

@MainActor
private final class StubCourseService: CoursePlanningServiceProtocol {
    var routeCallCount = 0
    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        routeCallCount += 1
        return PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)])
    }
}
