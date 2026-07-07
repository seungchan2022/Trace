import XCTest
@testable import Trace

final class SwiftDataCourseRepositoryTests: XCTestCase {
    private func coord(_ lat: Double, _ lon: Double) -> CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }

    private func sampleDraft() -> CourseDraft {
        let segID = UUID()
        return CourseDraft(
            entries: [
                CourseDraft.Entry(
                    id: segID, order: 0, placedAtFront: false, anchorID: nil,
                    segment: .tapped(
                        coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000
                    )
                ),
                CourseDraft.Entry(
                    id: UUID(), order: 1, placedAtFront: false, anchorID: segID,
                    segment: .roundTrip(
                        coordinates: [coord(37.51, 127.00), coord(37.50, 127.00), coord(37.51, 127.00)],
                        distanceMeters: 2000
                    )
                )
            ],
            nextOrder: 2
        )
    }

    func testDraft_saveLoad_roundTripsAllFields() async throws {
        let repo = SwiftDataCourseRepository(inMemory: true)
        let draft = sampleDraft()
        try await repo.saveDraft(draft)
        let loaded = await repo.loadDraft()
        XCTAssertEqual(loaded, draft) // id·order·placedAtFront·anchorID·세그먼트 케이스 전부 보존
    }

    func testDraft_secondSaveOverwritesFirst() async throws {
        let repo = SwiftDataCourseRepository(inMemory: true)
        try await repo.saveDraft(sampleDraft())
        try await repo.saveDraft(.empty)
        let loaded = await repo.loadDraft()
        XCTAssertEqual(loaded, .empty) // 단일 슬롯 — 마지막 저장이 이긴다
    }

    func testDraft_loadWithoutSave_returnsNil() async {
        let repo = SwiftDataCourseRepository(inMemory: true)
        let loaded = await repo.loadDraft()
        XCTAssertNil(loaded)
    }

    func testCourses_saveFetchDelete() async throws {
        let repo = SwiftDataCourseRepository(inMemory: true)
        let older = SavedCourse(
            id: UUID(), name: "한강 5km", createdAt: Date(timeIntervalSince1970: 1000),
            segments: [.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 5000)]
        )
        let newer = SavedCourse(
            id: UUID(), name: "남산 왕복", createdAt: Date(timeIntervalSince1970: 2000),
            segments: [.drawn(coordinates: [coord(37.55, 126.99), coord(37.56, 126.99)], distanceMeters: 3000)]
        )
        try await repo.saveCourse(older)
        try await repo.saveCourse(newer)

        let fetched = await repo.fetchCourses()
        XCTAssertEqual(fetched.map(\.id), [newer.id, older.id]) // 최신순
        XCTAssertEqual(fetched.first?.name, "남산 왕복")
        XCTAssertEqual(fetched.last?.segments, older.segments)

        try await repo.deleteCourse(id: older.id)
        let afterDelete = await repo.fetchCourses()
        XCTAssertEqual(afterDelete.map(\.id), [newer.id])
    }

    func testCourses_duplicateNamesAllowed() async throws {
        let repo = SwiftDataCourseRepository(inMemory: true)
        let a = SavedCourse(
            id: UUID(), name: "아침 코스", createdAt: Date(timeIntervalSince1970: 1000),
            segments: [.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000)]
        )
        let b = SavedCourse(
            id: UUID(), name: "아침 코스", createdAt: Date(timeIntervalSince1970: 2000),
            segments: a.segments
        )
        try await repo.saveCourse(a)
        try await repo.saveCourse(b)
        let fetched = await repo.fetchCourses()
        XCTAssertEqual(fetched.count, 2) // 같은 이름 중복 허용 (스펙 §2)
    }

    func testDecodeDraft_garbageData_returnsNil() {
        let garbage = Data("not json".utf8)
        XCTAssertNil(SwiftDataCourseRepository.decodeDraft(garbage)) // 손상 blob → nil (스펙 §2)
    }

    func testDecodeCourse_futureVersion_returnsNil() throws {
        // version=999 blob — 미래 포맷은 손상과 동일하게 취급 (스펙 §2 버전 필드)
        let payload = Data(#"{"version":999,"segments":[]}"#.utf8)
        XCTAssertNil(SwiftDataCourseRepository.decodeCourseSegments(payload))
    }
}
