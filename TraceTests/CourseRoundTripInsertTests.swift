import XCTest
@testable import Trace

@MainActor
final class CourseRoundTripInsertTests: XCTestCase {
    private func coord(_ lat: Double, _ lon: Double) -> CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }

    // 코스: A→B (order 0), B→C (order 1), C→D (order 2)
    private func makeThreeSegmentSession() async throws -> CourseEditSession {
        let session = CourseEditSession()
        let service = StubCourseService()
        let a = coord(37.50, 127.00), b = coord(37.51, 127.00)
        let c = coord(37.52, 127.00), d = coord(37.53, 127.00)
        try await session.attach(.tapped(coordinates: [a, b], distanceMeters: 1000), using: service)
        try await session.attach(.tapped(coordinates: [b, c], distanceMeters: 1000), using: service)
        try await session.attach(.tapped(coordinates: [c, d], distanceMeters: 1000), using: service)
        return session
    }

    func testInsertRoundTrip_middleSegment_insertsMergedPairAfterIt() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 1) // B→C 대상

        XCTAssertEqual(session.segments.count, 4)
        let inserted = session.segments[2] // 공간순: [A→B, B→C, 왕복, C→D]
        XCTAssertTrue(inserted.isRoundTrip)
        // 왕복 좌표: C→B→C (역방향 + 정방향 dropFirst), 거리 2배
        XCTAssertEqual(inserted.coordinates, [coord(37.52, 127.00), coord(37.51, 127.00), coord(37.52, 127.00)])
        XCTAssertEqual(inserted.distanceMeters, 2000)
        // 연결 유지: 왕복 끝(C) == 다음 구간 시작(C)
        XCTAssertEqual(inserted.coordinates.last, session.segments[3].coordinates.first)
        // 총 거리 = 3000 + 2000
        XCTAssertEqual(session.course?.distanceMeters, 5000)
    }

    func testInsertRoundTrip_lastSegment_appendsAtEnd() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 2)
        XCTAssertEqual(session.segments.count, 4)
        XCTAssertTrue(session.segments[3].isRoundTrip)
    }

    func testInsertRoundTrip_undoOnce_removesWholeRoundTrip() async throws {
        let session = try await makeThreeSegmentSession()
        let before = session.segments
        session.insertRoundTrip(afterOrder: 1)
        session.undo()
        XCTAssertEqual(session.segments, before) // undo 한 번 = 왕복 전체 취소 (스펙 §4)
    }

    func testInsertRoundTrip_undoRedo_restoresAtAnchorPosition() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 1)
        let after = session.segments
        session.undo()
        session.redo()
        XCTAssertEqual(session.segments, after) // 맨 뒤가 아니라 anchor 바로 뒤로 복원 (스펙 §4)
    }

    func testInsertRoundTrip_onRoundTripSegment_allowed() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 1)
        // 방금 삽입된 왕복(order 3)에 다시 왕복 — 특수 케이스 없음 (스펙 §4)
        session.insertRoundTrip(afterOrder: 3)
        XCTAssertEqual(session.segments.count, 5)
        XCTAssertEqual(session.segments[3].coordinates.first, session.segments[2].coordinates.last)
    }

    func testInsertRoundTrip_clearsRedoStack() async throws {
        let session = try await makeThreeSegmentSession()
        session.undo()
        XCTAssertTrue(session.canRedo)
        session.insertRoundTrip(afterOrder: 1)
        XCTAssertFalse(session.canRedo)
    }

    func testCanInsertRoundTrip_falseForUnknownOrder() async throws {
        let session = try await makeThreeSegmentSession()
        XCTAssertFalse(session.canInsertRoundTrip(afterOrder: 99))
        session.insertRoundTrip(afterOrder: 99) // no-op이어야 함
        XCTAssertEqual(session.segments.count, 3)
    }

    func testCanInsertRoundTrip_falseWhenExceedingCoordinateCap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // 좌표 15,000개짜리 구간 — 왕복 시 +29,999로 상한(20,000) 초과
        let bigCoords = (0..<15_000).map { coord(37.50 + Double($0) * 0.00001, 127.00) }
        try await session.attach(.drawn(coordinates: bigCoords, distanceMeters: 15_000), using: service)
        XCTAssertFalse(session.canInsertRoundTrip(afterOrder: 0))
        session.insertRoundTrip(afterOrder: 0)
        XCTAssertEqual(session.segments.count, 1) // no-op
    }

    func testInsertRoundTrip_singleSegmentCourse_appends() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let a = coord(37.50, 127.00), b = coord(37.51, 127.00)
        try await session.attach(.tapped(coordinates: [a, b], distanceMeters: 1000), using: service)
        session.insertRoundTrip(afterOrder: 0)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.segments[1].coordinates, [b, a, b])
        XCTAssertEqual(session.course?.distanceMeters, 3000)
    }

    func testInsertRoundTrip_closedCourse_keepsClosure() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let a = coord(37.50, 127.00), b = coord(37.51, 127.00)
        // 닫힌 코스: A→B→A (첫·끝 좌표 동일 = 임계값 이내)
        try await session.attach(.drawn(coordinates: [a, b, a], distanceMeters: 2000), using: service)
        session.insertRoundTrip(afterOrder: 0)
        XCTAssertEqual(session.segments.count, 2)
        // 삽입 후에도 코스는 A에서 시작해 A에서 끝난다 (닫힘 유지, 스펙 §4)
        XCTAssertEqual(session.course?.coordinates.first, a)
        XCTAssertEqual(session.course?.coordinates.last, a)
    }

    func testSnapshotRestore_preservesRoundTripRedoAnchor() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 1)
        let restored = CourseEditSession()
        restored.restore(from: session.snapshot())
        let after = restored.segments
        restored.undo()
        restored.redo()
        XCTAssertEqual(restored.segments, after) // 복원 후에도 anchor 기반 redo 위치 유지 (스펙 §4)
    }
}

private final class StubCourseService: CoursePlanningServiceProtocol {
    func route(
        from start: CourseCoordinate,
        to destination: CourseCoordinate
    ) async throws -> PlannedCourse {
        PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 500)])
    }
}
