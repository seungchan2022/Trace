import XCTest
@testable import Trace

// Task 5·6 공용 목 저장소
actor MockCourseRepository: CourseRepositoryProtocol {
    var savedDrafts: [CourseDraft] = []
    var stubbedDraft: CourseDraft?
    var savedCourses: [SavedCourse] = []
    var draftSaveError: Error?

    func setStubbedDraft(_ draft: CourseDraft?) { stubbedDraft = draft }
    func setDraftSaveError(_ error: Error?) { draftSaveError = error }

    func saveDraft(_ draft: CourseDraft) async throws {
        if let draftSaveError { throw draftSaveError }
        savedDrafts.append(draft)
    }
    func loadDraft() async -> CourseDraft? { stubbedDraft }
    func saveCourse(_ course: SavedCourse) async throws { savedCourses.append(course) }
    func fetchCourses() async -> [SavedCourse] {
        savedCourses.sorted { $0.createdAt > $1.createdAt }
    }
    func deleteCourse(id: UUID) async throws {
        savedCourses.removeAll { $0.id == id }
    }
}

struct StubError: Error {}

@MainActor
final class CoursePlannerViewModelPersistenceTests: XCTestCase {
    private func coord(_ lat: Double, _ lon: Double) -> CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }

    private func makeViewModel(repo: MockCourseRepository) -> CoursePlannerPageViewModel {
        CoursePlannerPageViewModel(
            coursePlanningService: StubPlannerService(),
            locationService: StubLocationService(),
            courseRepository: repo
        )
    }

    private func draftWithOneSegment() -> CourseDraft {
        CourseDraft(
            entries: [CourseDraft.Entry(
                id: UUID(), order: 0, placedAtFront: false, anchorID: nil,
                segment: .tapped(
                    coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000
                )
            )],
            nextOrder: 1
        )
    }

    func testBootstrapDraft_restoresSession() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()
        XCTAssertEqual(vm.course?.segments.count, 1)
        XCTAssertEqual(vm.course?.distanceMeters, 1000)
    }

    func testBootstrapDraft_nilDraft_keepsEmptySession() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()
        XCTAssertNil(vm.course)
    }

    func testUndo_persistsDraftSnapshot() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        await vm.undo()
        await vm.flushDraftSaves()

        let saved = await repo.savedDrafts
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(saved[0].isEmpty) // undo로 비워진 상태가 저장됨
    }

    func testClear_persistsEmptyDraft() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        vm.clear()
        await vm.flushDraftSaves()

        let saved = await repo.savedDrafts
        XCTAssertEqual(saved.last?.isEmpty, true) // 초기화 = 빈 스냅샷 저장 (clearDraft 대체)
    }

    func testPersistDraft_savesInOperationOrder() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        await vm.undo()   // 빈 스냅샷 (entries 0)
        vm.redo()         // 복구 스냅샷 (entries 1)
        await vm.flushDraftSaves()

        let saved = await repo.savedDrafts
        XCTAssertEqual(saved.map(\.entries.count), [0, 1]) // 연산 순서 보존 (스펙 §2 순서 불변식)
    }

    func testDraftSaveFailure_threeConsecutive_notifiesOnce() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        await repo.setDraftSaveError(StubError())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        await vm.undo()
        vm.redo()
        await vm.undo()
        await vm.flushDraftSaves()

        XCTAssertNotNil(vm.errorMessage) // 3회 연속 실패 → 1회 알림 (스펙 §2)

        // 4번째 실패는 다시 알리지 않는다 (세션당 1회) — 메시지가 그대로임으로 확인
        let message = vm.errorMessage
        vm.redo()
        await vm.flushDraftSaves()
        XCTAssertEqual(vm.errorMessage, message)
    }

    func testSaveCurrentCourse_savesSnapshotWithTrimmedName() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        vm.courseNameInput = "  한강 5km  "
        await vm.saveCurrentCourse()

        let saved = await repo.savedCourses
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.name, "한강 5km")
        XCTAssertEqual(saved.first?.segments, vm.course?.segments)
    }

    func testSaveCurrentCourse_emptyNameOrCourse_doesNothing() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        vm.courseNameInput = "이름"
        await vm.saveCurrentCourse() // 코스 없음
        vm.courseNameInput = "   "
        await vm.saveCurrentCourse() // 이름 없음(코스도 없지만 이름 가드 선행)
        let saved = await repo.savedCourses
        XCTAssertTrue(saved.isEmpty)
    }

    func testPresentCourseList_loadsCoursesNewestFirst() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        let older = SavedCourse(
            id: UUID(), name: "A", createdAt: Date(timeIntervalSince1970: 1000),
            segments: [.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000)]
        )
        let newer = SavedCourse(
            id: UUID(), name: "B", createdAt: Date(timeIntervalSince1970: 2000), segments: older.segments
        )
        try? await repo.saveCourse(older)
        try? await repo.saveCourse(newer)

        await vm.presentCourseList()

        XCTAssertTrue(vm.isCourseListPresented)
        XCTAssertEqual(vm.savedCourses.map(\.name), ["B", "A"])
    }

    func testRequestLoad_emptySession_loadsImmediately() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        let saved = SavedCourse(
            id: UUID(), name: "A", createdAt: Date(),
            segments: [.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000)]
        )
        await vm.requestLoad(saved)
        XCTAssertEqual(vm.course?.segments, saved.segments)
        XCTAssertNil(vm.pendingLoadCourse)
        await vm.flushDraftSaves()
        let drafts = await repo.savedDrafts
        XCTAssertEqual(drafts.last?.entries.count, 1) // 불러오기도 초안으로 저장됨 (스펙 §3 트리거)
    }

    func testRequestLoad_nonEmptySession_asksConfirmationThenReplaces() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()
        let saved = SavedCourse(
            id: UUID(), name: "A", createdAt: Date(),
            segments: [
                .drawn(coordinates: [coord(37.55, 126.99), coord(37.56, 126.99)], distanceMeters: 3000)
            ]
        )

        await vm.requestLoad(saved)
        XCTAssertEqual(vm.pendingLoadCourse, saved) // 즉시 교체 아님 — 확인 대기
        XCTAssertNotEqual(vm.course?.segments, saved.segments)

        await vm.confirmPendingLoad()
        XCTAssertEqual(vm.course?.segments, saved.segments)
        XCTAssertNil(vm.pendingLoadCourse)
        XCTAssertFalse(vm.isCourseListPresented) // 불러오면 시트 닫힘
    }

    func testDeleteSavedCourse_removesFromRepositoryAndList() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        let saved = SavedCourse(
            id: UUID(), name: "A", createdAt: Date(),
            segments: [.tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000)]
        )
        try? await repo.saveCourse(saved)
        await vm.presentCourseList()
        XCTAssertEqual(vm.savedCourses.count, 1)

        await vm.deleteSavedCourse(saved)

        XCTAssertTrue(vm.savedCourses.isEmpty)
        let remaining = await repo.savedCourses
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInsertRoundTrip_viaViewModel_updatesCourseAndPersists() async {
        let repo = MockCourseRepository()
        await repo.setStubbedDraft(draftWithOneSegment())
        let vm = makeViewModel(repo: repo)
        await vm.bootstrapDraft()

        XCTAssertTrue(vm.canInsertRoundTrip(afterColorKey: 0))
        vm.insertRoundTrip(afterColorKey: 0)

        XCTAssertEqual(vm.course?.segments.count, 2)
        XCTAssertEqual(vm.course?.segments.last?.isRoundTrip, true)
        XCTAssertEqual(vm.course?.distanceMeters, 3000) // 1000 + 2000
        XCTAssertNil(vm.selectedSegmentIndex)

        await vm.flushDraftSaves()
        let drafts = await repo.savedDrafts
        XCTAssertEqual(drafts.last?.entries.count, 2) // 왕복 삽입도 초안 저장 트리거 (스펙 §3)
    }

    func testCanInsertRoundTrip_unknownKey_false() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        XCTAssertFalse(vm.canInsertRoundTrip(afterColorKey: 0)) // 빈 코스
    }
}

private final class StubPlannerService: CoursePlanningServiceProtocol {
    func route(
        from start: CourseCoordinate,
        to destination: CourseCoordinate
    ) async throws -> PlannedCourse {
        PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 500)])
    }
}

private final class StubLocationService: LocationServiceProtocol {
    func currentLocation() async throws -> CourseCoordinate {
        CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
    }
}
