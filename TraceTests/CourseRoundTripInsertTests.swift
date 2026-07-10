import XCTest
@testable import Trace

nonisolated final class CourseRoundTripInsertTests: XCTestCase {
    private func coord(_ lat: Double, _ lon: Double) -> CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }

    // 코스: A→B (order 0), B→C (order 1), C→D (order 2)
    @MainActor
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

    // MARK: - 자유 끝 제한 (2026-07-08 정정: 중간 구간은 불가)

    @MainActor
    func testCanInsertRoundTrip_falseForMiddleSegment() async throws {
        let session = try await makeThreeSegmentSession()
        XCTAssertFalse(session.canInsertRoundTrip(afterOrder: 1)) // B→C, 중간 구간
        session.insertRoundTrip(afterOrder: 1)
        XCTAssertEqual(session.segments.count, 3) // no-op
    }

    // MARK: - 뒤쪽 끝: append, 코스 끝이 대상 구간 시작점으로 이동

    @MainActor
    func testInsertRoundTrip_lastSegment_appendsReversedWithSameDistance() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 2) // C→D 대상

        XCTAssertEqual(session.segments.count, 4)
        let inserted = session.segments[3]
        XCTAssertTrue(inserted.isRoundTrip)
        // 왕복 좌표: D→C(대상 구간의 역방향뿐), 거리는 대상과 동일(1×)
        XCTAssertEqual(inserted.coordinates, [coord(37.53, 127.00), coord(37.52, 127.00)])
        XCTAssertEqual(inserted.distanceMeters, 1000)
        // 연결 유지: 왕복 시작(D) == 대상 구간 끝(D)
        XCTAssertEqual(inserted.coordinates.first, session.segments[2].coordinates.last)
        // 총 거리 = 3000 + 1000(대상 구간만큼 추가) = 4000
        XCTAssertEqual(session.course?.distanceMeters, 4000)
        // 코스 끝이 대상 구간 시작점(C)으로 이동
        XCTAssertEqual(session.course?.coordinates.last, coord(37.52, 127.00))
    }

    @MainActor
    func testInsertRoundTrip_undoOnce_removesRoundTrip() async throws {
        let session = try await makeThreeSegmentSession()
        let before = session.segments
        session.insertRoundTrip(afterOrder: 2)
        session.undo()
        XCTAssertEqual(session.segments, before)
    }

    @MainActor
    func testInsertRoundTrip_undoRedo_restoresAfterAnchor() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 2)
        let after = session.segments
        session.undo()
        session.redo()
        XCTAssertEqual(session.segments, after)
    }

    @MainActor
    func testInsertRoundTrip_clearsRedoStack() async throws {
        let session = try await makeThreeSegmentSession()
        session.undo() // order 2(C→D) 제거 — 남은 뒤쪽 끝은 order 1(B→C)
        XCTAssertTrue(session.canRedo)
        session.insertRoundTrip(afterOrder: 1)
        XCTAssertFalse(session.canRedo)
    }

    // MARK: - 앞쪽 끝: prepend, 코스 시작이 대상 구간 끝점으로 이동

    @MainActor
    func testInsertRoundTrip_frontSegment_prependsReversedBeforeIt() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 0) // A→B 대상

        XCTAssertEqual(session.segments.count, 4)
        let inserted = session.segments[0] // 공간순 맨 앞에 삽입됨
        XCTAssertTrue(inserted.isRoundTrip)
        XCTAssertEqual(inserted.coordinates, [coord(37.51, 127.00), coord(37.50, 127.00)])
        XCTAssertEqual(inserted.distanceMeters, 1000)
        // 연결 유지: 왕복 끝(A) == 원래 대상 구간(A→B) 시작(A)
        XCTAssertEqual(inserted.coordinates.last, session.segments[1].coordinates.first)
        // 코스 시작이 대상 구간 끝점(B)으로 이동
        XCTAssertEqual(session.course?.coordinates.first, coord(37.51, 127.00))
        XCTAssertEqual(session.course?.distanceMeters, 4000)
    }

    @MainActor
    func testInsertRoundTrip_frontSegment_undoRedo_restoresBeforeAnchor() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 0)
        let after = session.segments
        session.undo()
        session.redo()
        XCTAssertEqual(session.segments, after) // 맨 뒤가 아니라 anchor 바로 앞으로 복원
    }

    // MARK: - 경계 케이스

    @MainActor
    func testInsertRoundTrip_onRoundTripSegment_allowed() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertRoundTrip(afterOrder: 2) // 뒤쪽 끝에 왕복(order 3) 삽입
        // 방금 삽입된 왕복도 새로운 뒤쪽 끝이므로 다시 왕복 가능 — 특수 케이스 없음
        XCTAssertTrue(session.canInsertRoundTrip(afterOrder: 3))
        session.insertRoundTrip(afterOrder: 3)
        XCTAssertEqual(session.segments.count, 5)
        XCTAssertEqual(session.segments[4].coordinates.first, session.segments[3].coordinates.last)
    }

    @MainActor
    func testCanInsertRoundTrip_falseForUnknownOrder() async throws {
        let session = try await makeThreeSegmentSession()
        XCTAssertFalse(session.canInsertRoundTrip(afterOrder: 99))
        session.insertRoundTrip(afterOrder: 99) // no-op이어야 함
        XCTAssertEqual(session.segments.count, 3)
    }

    @MainActor
    func testCanInsertRoundTrip_falseWhenExceedingCoordinateCap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        // 좌표 15,000개짜리 단일 구간 — 왕복 시 +15,000으로 상한(20,000) 초과
        let bigCoords = (0..<15_000).map { coord(37.50 + Double($0) * 0.00001, 127.00) }
        try await session.attach(.drawn(coordinates: bigCoords, distanceMeters: 15_000), using: service)
        XCTAssertFalse(session.canInsertRoundTrip(afterOrder: 0))
        session.insertRoundTrip(afterOrder: 0)
        XCTAssertEqual(session.segments.count, 1) // no-op
    }

    @MainActor
    func testInsertRoundTrip_singleSegmentCourse_appends() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let a = coord(37.50, 127.00), b = coord(37.51, 127.00)
        try await session.attach(.tapped(coordinates: [a, b], distanceMeters: 1000), using: service)
        session.insertRoundTrip(afterOrder: 0) // 유일 구간 — 앞뒤 둘 다 해당, append로 처리
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.segments[1].coordinates, [b, a])
        XCTAssertEqual(session.course?.distanceMeters, 2000)
    }

    @MainActor
    func testInsertRoundTrip_closedCourse_keepsClosure() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let a = coord(37.50, 127.00), b = coord(37.51, 127.00)
        // 닫힌 코스: A→B→A (첫·끝 좌표 동일 = 임계값 이내)
        try await session.attach(.drawn(coordinates: [a, b, a], distanceMeters: 2000), using: service)
        session.insertRoundTrip(afterOrder: 0)
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.course?.coordinates.first, a)
        XCTAssertEqual(session.course?.coordinates.last, a)
        XCTAssertEqual(session.course?.distanceMeters, 4000)
    }

    // MARK: - 전체 왕복 (2026-07-08 추가)

    @MainActor
    func testCanInsertWholeCourseRoundTrip_falseForEmptyCourse() {
        let session = CourseEditSession()
        XCTAssertFalse(session.canInsertWholeCourseRoundTrip())
    }

    @MainActor
    func testInsertWholeCourseRoundTrip_appendsFullReversedCourse() async throws {
        let session = try await makeThreeSegmentSession()
        session.insertWholeCourseRoundTrip()

        XCTAssertEqual(session.segments.count, 4)
        let inserted = session.segments[3]
        XCTAssertTrue(inserted.isRoundTrip)
        // 전체 코스(A,B,C,D — 경계 중복 제거)를 뒤집은 D,C,B,A
        XCTAssertEqual(
            inserted.coordinates,
            [coord(37.53, 127.00), coord(37.52, 127.00), coord(37.51, 127.00), coord(37.50, 127.00)]
        )
        XCTAssertEqual(inserted.distanceMeters, 3000) // 기존 코스 총 거리와 동일
        XCTAssertEqual(session.course?.coordinates.first, coord(37.50, 127.00))
        XCTAssertEqual(session.course?.coordinates.last, coord(37.50, 127.00))
        XCTAssertEqual(session.course?.distanceMeters, 6000)
    }

    @MainActor
    func testInsertWholeCourseRoundTrip_undo_removesWholeSegment() async throws {
        let session = try await makeThreeSegmentSession()
        let before = session.segments
        session.insertWholeCourseRoundTrip()
        session.undo()
        XCTAssertEqual(session.segments, before)
    }

    @MainActor
    func testCanInsertWholeCourseRoundTrip_falseWhenExceedingCoordinateCap() async throws {
        let session = CourseEditSession()
        let service = StubCourseService()
        let bigCoords = (0..<15_000).map { coord(37.50 + Double($0) * 0.00001, 127.00) }
        try await session.attach(.drawn(coordinates: bigCoords, distanceMeters: 15_000), using: service)
        XCTAssertFalse(session.canInsertWholeCourseRoundTrip())
        session.insertWholeCourseRoundTrip()
        XCTAssertEqual(session.segments.count, 1) // no-op
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
