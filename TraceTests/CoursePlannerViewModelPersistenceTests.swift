import XCTest
@testable import Trace

// Task 6 공용 목 저장소
actor MockCourseRepository: CourseRepositoryProtocol {
    var savedCourses: [SavedCourse] = []

    func saveCourse(_ course: SavedCourse) async throws { savedCourses.append(course) }
    func fetchCourses() async -> [SavedCourse] {
        savedCourses.sorted { $0.createdAt > $1.createdAt }
    }
    func deleteCourse(id: UUID) async throws {
        savedCourses.removeAll { $0.id == id }
    }
}

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

    func testSaveCurrentCourse_savesSnapshotWithTrimmedName() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        try? await vm.session.attach(
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            using: StubPlannerService()
        )

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
    }

    func testRequestLoad_nonEmptySession_asksConfirmationThenReplaces() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        try? await vm.session.attach(
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            using: StubPlannerService()
        )
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
        let vm = makeViewModel(repo: repo)
        try? await vm.session.attach(
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            using: StubPlannerService()
        )

        XCTAssertTrue(vm.canInsertRoundTrip(afterColorKey: 0))
        vm.insertRoundTrip(afterColorKey: 0)

        XCTAssertEqual(vm.course?.segments.count, 2)
        XCTAssertEqual(vm.course?.segments.last?.isRoundTrip, true)
        XCTAssertEqual(vm.course?.distanceMeters, 2000) // 1000 + 1000(대상 구간만큼 추가)
        XCTAssertNil(vm.selectedSegmentIndex)
    }

    func testCanInsertRoundTrip_unknownKey_false() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        XCTAssertFalse(vm.canInsertRoundTrip(afterColorKey: 0)) // 빈 코스
    }

    func testInsertWholeCourseRoundTrip_viaViewModel_updatesCourseAndPersists() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        try? await vm.session.attach(
            .tapped(coordinates: [coord(37.50, 127.00), coord(37.51, 127.00)], distanceMeters: 1000),
            using: StubPlannerService()
        )

        XCTAssertTrue(vm.canInsertWholeCourseRoundTrip)
        vm.insertWholeCourseRoundTrip()

        XCTAssertEqual(vm.course?.segments.count, 2)
        XCTAssertEqual(vm.course?.segments.last?.isRoundTrip, true)
        XCTAssertEqual(vm.course?.distanceMeters, 2000) // 1000 + 1000(전체 코스 왕복)
        XCTAssertNil(vm.selectedSegmentIndex)
    }

    func testCanInsertWholeCourseRoundTrip_emptyCourse_false() async {
        let repo = MockCourseRepository()
        let vm = makeViewModel(repo: repo)
        XCTAssertFalse(vm.canInsertWholeCourseRoundTrip)
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
