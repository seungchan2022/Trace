import XCTest
@testable import Trace

@MainActor
final class CourseDraftSnapshotTests: XCTestCase {
    private func coord(_ lat: Double, _ lon: Double) -> CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }

    private func makeSessionWithTwoSegments() async throws -> (CourseEditSession, StubCourseService) {
        let session = CourseEditSession()
        let service = StubCourseService()
        try await session.attach(
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            using: service
        )
        try await session.attach(
            .tapped(coordinates: [coord(37.51, 127.00), coord(37.52, 127.00)], distanceMeters: 1000),
            using: service
        )
        return (session, service)
    }

    func testSnapshotRestore_roundTripsCourseAndUndo() async throws {
        let (session, _) = try await makeSessionWithTwoSegments()
        let draft = session.snapshot()

        let restored = CourseEditSession()
        restored.restore(from: draft)
        XCTAssertEqual(restored.segments, session.segments)
        XCTAssertEqual(restored.segmentColorKeys, session.segmentColorKeys)

        // 복원 후 undo가 시간순 최신(두 번째 구간)을 제거해야 한다
        restored.undo()
        XCTAssertEqual(restored.segments.count, 1)
        XCTAssertEqual(restored.segments.first?.coordinates.first, coord(37.50, 127.00))
    }

    func testSnapshot_emptySession_isEmptyDraft() {
        let session = CourseEditSession()
        XCTAssertTrue(session.snapshot().isEmpty)
    }

    func testRestore_emptyDraft_clearsSession() async throws {
        let (session, _) = try await makeSessionWithTwoSegments()
        session.restore(from: .empty)
        XCTAssertTrue(session.segments.isEmpty)
        XCTAssertFalse(session.canRedo)
    }

    func testRestore_preservesEntryIDs() async throws {
        let (session, _) = try await makeSessionWithTwoSegments()
        let draft = session.snapshot()
        let restored = CourseEditSession()
        restored.restore(from: draft)
        XCTAssertEqual(restored.snapshot().entries.map(\.id), draft.entries.map(\.id))
    }

    func testRestore_dropsRedoStack() async throws {
        let (session, _) = try await makeSessionWithTwoSegments()
        session.undo()
        XCTAssertTrue(session.canRedo)
        let draft = session.snapshot()
        let restored = CourseEditSession()
        restored.restore(from: draft)
        XCTAssertFalse(restored.canRedo) // 스냅샷에 redo가 없으므로 복원 후 비활성 (스펙 §1 제외 사항)
    }

    func testLoadSegments_reassignsSequentialOrders() {
        let session = CourseEditSession()
        let segs: [CourseSegment] = [
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            .drawn(coordinates: [coord(37.51, 127.00), coord(37.52, 127.00)], distanceMeters: 1000)
        ]
        session.load(segments: segs)
        XCTAssertEqual(session.segments, segs)
        XCTAssertEqual(session.segmentColorKeys, [0, 1])
        session.undo() // 공간순 마지막이 시간순 최신
        XCTAssertEqual(session.segments.count, 1)
    }
}

// StubCourseService: CourseEditSessionTests.swift의 것과 동일 형태 (private라 파일별 재정의)
private final class StubCourseService: CoursePlanningServiceProtocol {
    func route(
        from start: CourseCoordinate,
        to destination: CourseCoordinate
    ) async throws -> PlannedCourse {
        PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 500)])
    }
}
