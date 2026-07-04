import XCTest
@testable import Trace

@MainActor
final class CoursePlannerViewModelTests: XCTestCase {
    private func makeSUT(locationError: Error? = nil) -> CoursePlannerPageViewModel {
        let locationService = StubLocationService()
        locationService.stubbedError = locationError
        let defaults = UserDefaults(suiteName: "viewModelTests")!
        defaults.removePersistentDomain(forName: "viewModelTests")
        return CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: locationService,
            cameraStateStore: CameraStateStore(defaults: defaults)
        )
    }

    // MARK: - Mode switching

    func testDefaultModeIsTap() {
        let sut = makeSUT()
        XCTAssertEqual(sut.interactionMode, .tap)
    }

    func testToggleToDrawPreservesTapRouteAsHistory() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.6, longitude: 127.0))
        XCTAssertNotNil(sut.course)

        await sut.toggleDrawingMode()

        XCTAssertEqual(sut.interactionMode, .draw)
        XCTAssertNil(sut.pendingTapStart)
        XCTAssertNotNil(sut.course, "탭 경로가 session으로 보존되어야 함")
    }

    func testClearResetsAllState() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        sut.clear()

        XCTAssertNil(sut.pendingTapStart)
        XCTAssertNil(sut.course)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Location permission

    func testBootstrapSetsAlertOnDenied() async {
        let sut = makeSUT(locationError: LocationError.denied)
        await sut.bootstrapLocation()
        XCTAssertTrue(sut.showLocationDeniedAlert)
        XCTAssertNotNil(sut.initialCameraCoordinate)
    }

    func testBootstrapNoAlertOnSuccess() async {
        let sut = makeSUT()
        await sut.bootstrapLocation()
        XCTAssertFalse(sut.showLocationDeniedAlert)
        XCTAssertNotNil(sut.initialCameraCoordinate)
    }

    // MARK: - Camera restore

    func testBootstrapDoesNotOverrideWhenCameraRestored() async {
        let store = CameraStateStore(defaults: UserDefaults(suiteName: "testBootstrap")!)
        UserDefaults(suiteName: "testBootstrap")!.removePersistentDomain(forName: "testBootstrap")
        store.save(latitude: 35.0, longitude: 129.0, latitudinalMeters: 1000, longitudinalMeters: 1000)

        let sut = CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService(),
            cameraStateStore: store
        )
        await sut.bootstrapLocation()
        XCTAssertNil(sut.initialCameraCoordinate)
    }

    func testBootstrapSetsCoordinateWhenNoCameraStored() async {
        let store = CameraStateStore(defaults: UserDefaults(suiteName: "testBootstrapEmpty")!)
        UserDefaults(suiteName: "testBootstrapEmpty")!.removePersistentDomain(forName: "testBootstrapEmpty")

        let sut = CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService(),
            cameraStateStore: store
        )
        await sut.bootstrapLocation()
        XCTAssertNotNil(sut.initialCameraCoordinate)
    }

    // MARK: - Tap accumulation (MVP6 핵심)

    func testThirdTap_afterExistingSegment_autoConnectsWithSingleTap() async {
        let sut = makeSUT()
        // 최초 2탭: A→B, 세그먼트 1개
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 1)

        // 세 번째 탭 1번만으로 바로 연결되어야 함 (pendingTapStart를 거치지 않음)
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))

        XCTAssertNil(sut.pendingTapStart, "자동 연결 탭에는 대기 상태가 없어야 함")
        XCTAssertEqual(sut.session.segments.count, 2)
    }

    func testAutoConnect_choosesNearerEndpoint() async {
        let sut = makeSUT()
        // A(37.50)→B(37.51) 세그먼트
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 1)

        // 새 탭이 A(37.50)에 훨씬 가까움 → 출발쪽에서 연결(prepend)되어야 함
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.499, longitude: 127.00))

        XCTAssertEqual(sut.session.segments.count, 2)
        XCTAssertEqual(sut.course?.coordinates.first?.latitude ?? 0, 37.499, accuracy: 0.001)
    }

    func testFirstTap_setsPendingStart() async {
        let sut = makeSUT()
        let coord = CourseCoordinate(latitude: 37.5, longitude: 127.0)
        await sut.handleMapTap(at: coord)
        XCTAssertEqual(sut.pendingTapStart?.latitude ?? 0, coord.latitude, accuracy: 0.0001)
        XCTAssertNil(sut.course, "첫 탭만으로 course가 생기면 안 됨")
    }

    func testSecondTap_routesAndCommitsToSession() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertNil(sut.pendingTapStart)
        XCTAssertEqual(sut.session.segments.count, 1)
        XCTAssertNotNil(sut.course)
    }

    func testMultipleTapPairs_accumulate() async {
        let sut = makeSUT()
        // 첫 번째 쌍: A→B
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 1)

        // 세 번째 탭부터 자동 연결: C는 B에 가까워서 자동 연결
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 2)

        // 네 번째 탭도 자동 연결
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.53, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 3, "탭이 누적되어야 함 — 자동 연결로 각 탭마다 새 세그먼트 생성")
        XCTAssertNotNil(sut.course)
    }

    func testTapUndo_removesLastSegment() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.53, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 3, "자동 연결로 3개 세그먼트 생성")

        await sut.undo()
        XCTAssertEqual(sut.session.segments.count, 2)
    }

    func testUndo_clearsSelectedSegmentIndex() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 2)

        sut.selectSegment(at: 1)
        XCTAssertEqual(sut.selectedSegmentIndex, 1)

        await sut.undo()

        XCTAssertNil(sut.selectedSegmentIndex, "undo로 세그먼트 배열이 바뀌면 선택된 인덱스는 무효화되어야 함")
    }

    func testAttachPrepend_clearsSelectedSegmentIndex() async {
        let sut = makeSUT()
        // A(37.50)→B(37.51) 세그먼트
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 1)

        sut.selectSegment(at: 0)
        XCTAssertEqual(sut.selectedSegmentIndex, 0)

        // 새 탭이 A(37.50)에 훨씬 가까움 → 출발쪽에서 연결(prepend)되어 기존 세그먼트 인덱스가 밀림
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.499, longitude: 127.00))

        XCTAssertEqual(sut.session.segments.count, 2)
        XCTAssertNil(sut.selectedSegmentIndex, "prepend로 기존 인덱스가 가리키는 세그먼트가 바뀌므로 선택은 초기화되어야 함")
    }

    func testTapRouteNotFound_showsErrorAndDoesNotAttach() async {
        let service = StubCoursePlanningService()
        service.stubbedError = CoursePlanningError.routeNotFound
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )

        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5665, longitude: 126.9780))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5700, longitude: 126.9820))

        XCTAssertNil(sut.course)
        XCTAssertEqual(sut.errorMessage, "도보 경로를 찾을 수 없습니다.")
    }

    func testTapDegenerateRoute_singleCoordinate_showsErrorAndDoesNotAttach() async {
        let service = StubCoursePlanningService()
        let single = CourseCoordinate(latitude: 37.5665, longitude: 126.9780)
        // route 서비스가 실패(throw)하지 않고 "성공"하지만 좌표가 1개뿐인 축약된 경로를 반환하는 경우
        // (두 탭 좌표가 거의 동일하거나 매우 짧은 스트로크일 때 MapKit이 반환할 수 있는 경계 사례)
        service.stubbedResult = PlannedCourse(
            segments: [.tapped(coordinates: [single], distanceMeters: 0)]
        )
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )

        await sut.handleMapTap(at: single)
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5666, longitude: 126.9781))

        XCTAssertNil(sut.course, "좌표 1개짜리 route는 유효한 구간으로 attach되면 안 됨")
        XCTAssertEqual(sut.errorMessage, "도보 경로를 찾을 수 없습니다.")
    }

    func testFailedAttach_doesNotResetSelectedSegmentIndex() async {
        let service = StubCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertEqual(sut.session.segments.count, 1)

        sut.selectSegment(at: 0)
        XCTAssertEqual(sut.selectedSegmentIndex, 0)

        service.stubbedError = CoursePlanningError.routeNotFound
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))

        XCTAssertEqual(sut.session.segments.count, 1, "실패한 attach는 세그먼트를 추가하지 않아야 함")
        XCTAssertEqual(sut.selectedSegmentIndex, 0, "attach 실패 시 기존 선택은 유지되어야 함")
    }

    // MARK: - Draw mode: stroke = segment

    func testAppendStroke_attachesOneSegmentPerStroke() async {
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sut.session.segments.count, 1)

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.511, longitude: 127.00),
            CourseCoordinate(latitude: 37.520, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sut.session.segments.count, 2, "스트로크마다 세그먼트가 하나씩 붙어야 함")
    }

    func testAppendStroke_startNearExistingEnd_snapsToExactEndpointBeforeRouting() async {
        let service = StubCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        let a = CourseCoordinate(latitude: 37.500, longitude: 127.00)
        let b = CourseCoordinate(latitude: 37.510, longitude: 127.00)
        await sut.appendStroke([a, b])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sut.session.segments.count, 1)

        // 두 번째 스트로크: 기존 도착점(b)에서 약 11m 떨어진 곳에서 시작(라우팅 스냅 오차 시뮬레이션)
        let nearB = CourseCoordinate(latitude: b.latitude + 0.0001, longitude: b.longitude)
        let c = CourseCoordinate(latitude: 37.520, longitude: 127.00)
        await sut.appendStroke([nearB, c])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(sut.session.segments.count, 2, "gap 세그먼트 없이 하나로 붙어야 함")
        XCTAssertEqual(service.recordedFromCoordinates.last, b, "라우팅 시작점이 원본 터치(nearB)가 아니라 기존 도착점(b)으로 스냅되어야 함")
        XCTAssertEqual(sut.course?.coordinates.last, c)
    }

    func testAppendStroke_startNearExistingStart_snapsAndReversesPrepend() async {
        let service = StubCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        let a = CourseCoordinate(latitude: 37.500, longitude: 127.00)
        let b = CourseCoordinate(latitude: 37.510, longitude: 127.00)
        await sut.appendStroke([a, b])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sut.session.segments.count, 1)

        // 두 번째 스트로크: 기존 출발점(a)에서 약 11m 떨어진 곳에서 시작해 바깥쪽(D)으로 그림
        let nearA = CourseCoordinate(latitude: a.latitude - 0.0001, longitude: a.longitude)
        let d = CourseCoordinate(latitude: 37.490, longitude: 127.00)
        await sut.appendStroke([nearA, d])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(sut.session.segments.count, 2)
        XCTAssertEqual(service.recordedFromCoordinates.last, a, "라우팅 시작점이 원본 터치(nearA)가 아니라 기존 출발점(a)으로 스냅되어야 함")
        XCTAssertEqual(sut.course?.coordinates.first, d, "반전 prepend로 코스 시작이 d로 바뀌어야 함 (유일한 반전 케이스)")
    }

    func testDrawUndo_removesOnlyLastSegment() async {
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.511, longitude: 127.00),
            CourseCoordinate(latitude: 37.520, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sut.session.segments.count, 2)

        await sut.undo()

        XCTAssertEqual(sut.session.segments.count, 1)
    }

    func testToggleModes_doesNotAttachExtraSegment() async {
        let sut = makeSUT()
        await sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sut.session.segments.count, 1)

        await sut.toggleDrawingMode()

        XCTAssertEqual(sut.session.segments.count, 1, "모드 종료 자체는 세그먼트를 추가하지 않아야 함")
    }

    func testThrottleErrorDuringStroke_doesNotAttachSegment() async {
        let service = StubCoursePlanningService()
        service.stubbedError = CoursePlanningError.throttled
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(sut.errorMessage, "요청이 많아 잠시 후 다시 시도해주세요")
        XCTAssertTrue(sut.session.segments.isEmpty)
    }

    func testDrawStrokeFailure_keepsPreviousSegmentAndSetsError() async {
        let service = StubCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sut.session.segments.count, 1)

        service.stubbedError = CoursePlanningError.requestFailed
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.511, longitude: 127.00),
            CourseCoordinate(latitude: 37.520, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(sut.session.segments.count, 1, "실패한 스트로크는 세그먼트로 붙지 않고 기존 세그먼트가 유지되어야 함")
        XCTAssertNotNil(sut.errorMessage)
    }

    // MARK: - Undo with session

    func testClearAlsoResetsSession() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        try? await Task.sleep(nanoseconds: 100_000_000)
        await sut.toggleDrawingMode()
        XCTAssertNotNil(sut.course)

        sut.clear()

        XCTAssertNil(sut.course)
        XCTAssertNil(sut.pendingTapStart)
    }

    func testThrottleErrorShowsUserMessage() async {
        let service = StubCoursePlanningService()
        service.stubbedError = CoursePlanningError.throttled
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        await sut.appendStroke([
            CourseCoordinate(latitude: 37.500, longitude: 127.00),
            CourseCoordinate(latitude: 37.510, longitude: 127.00),
        ])
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(sut.errorMessage, "요청이 많아 잠시 후 다시 시도해주세요")
    }

    // MARK: - Race condition

    func testToggleDuringRouteCalculationDiscardsStaleCourse() async {
        let service = BlockingCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )

        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        XCTAssertNotNil(sut.pendingTapStart)

        let calculateTask = Task {
            await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        }

        await service.waitUntilRouteEntered()

        await sut.toggleDrawingMode()
        XCTAssertEqual(sut.interactionMode, .draw)
        // draw 전환 시 session에 아직 아무것도 없으면 course = nil
        XCTAssertNil(sut.course)

        service.resumeRoute()
        await calculateTask.value

        XCTAssertNil(sut.course)
    }

    func testClear_duringInFlightStroke_discardsStaleCourse() async {
        let service = BlockingCoursePlanningService()
        let sut = CoursePlannerPageViewModel(
            coursePlanningService: service,
            locationService: StubLocationService()
        )
        await sut.toggleDrawingMode()

        let appendTask = Task {
            await sut.appendStroke([
                CourseCoordinate(latitude: 37.50, longitude: 127.00),
                CourseCoordinate(latitude: 37.51, longitude: 127.00),
            ])
        }

        await service.waitUntilRouteEntered()

        sut.clear()
        XCTAssertNil(sut.course)

        service.resumeRoute()
        await appendTask.value

        XCTAssertNil(sut.course, "clear() 이후 완료된 recompute가 course를 부활시키면 안 됩니다")
        XCTAssertTrue(sut.session.segments.isEmpty)
    }

    // MARK: - Path stitching

    func testTapRouteIsPreservedWhenEnteringDrawMode() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        try? await Task.sleep(nanoseconds: 100_000_000)
        let tapCourse = sut.course
        XCTAssertNotNil(tapCourse)

        await sut.toggleDrawingMode()

        XCTAssertNotNil(sut.course)
        XCTAssertEqual(sut.course?.distanceMeters, tapCourse?.distanceMeters)
    }

    // MARK: - Redo

    func testRedo_restoresCourseAndResetsSelection() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))
        XCTAssertEqual(sut.course?.segments.count, 2)

        await sut.undo()
        XCTAssertEqual(sut.course?.segments.count, 1)
        XCTAssertTrue(sut.canRedo)

        sut.selectSegment(at: 0)
        sut.redo()
        XCTAssertEqual(sut.course?.segments.count, 2)
        XCTAssertNil(sut.selectedSegmentIndex, "redo 후 선택 초기화 (prepend 복원 시 인덱스 밀림)")
        XCTAssertFalse(sut.canRedo)
    }

    // MARK: - Pin hit handling (round trip / no-op / info)

    func testHandleMapTap_startPinHit_appendsReturnLegSnappedToStart() async {
        let sut = makeSUT()
        let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
        let b = CourseCoordinate(latitude: 37.51, longitude: 127.00)
        await sut.handleMapTap(at: a)
        await sut.handleMapTap(at: b)
        XCTAssertEqual(sut.course?.segments.count, 1)

        // 출발핀 히트 → 도착점에서 출발점 좌표(스냅)까지 왕복 구간 append
        let nearA = CourseCoordinate(latitude: 37.5001, longitude: 127.00)
        await sut.handleMapTap(at: nearA, hitPin: .start)
        XCTAssertEqual(sut.course?.segments.count, 2)
        XCTAssertEqual(sut.course?.coordinates.first, a, "출발 유지")
        XCTAssertEqual(sut.course?.coordinates.last, a, "탭 좌표가 아닌 출발점 좌표로 스냅")
        XCTAssertTrue(sut.isClosedCourse)
    }

    func testHandleMapTap_endPinHit_isNoOpWithInfo() async {
        let sut = makeSUT()
        let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
        let b = CourseCoordinate(latitude: 37.51, longitude: 127.00)
        await sut.handleMapTap(at: a)
        await sut.handleMapTap(at: b)

        await sut.handleMapTap(at: b, hitPin: .end)
        XCTAssertEqual(sut.course?.segments.count, 1, "무시(no-op)")
        XCTAssertEqual(sut.infoMessage, "이미 도착점입니다")
    }

    func testHandleMapTap_mergedPinHit_isNoOpWithInfo() async {
        let sut = makeSUT()
        let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
        await sut.handleMapTap(at: a)
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        await sut.handleMapTap(at: a, hitPin: .start) // 왕복으로 닫음

        await sut.handleMapTap(at: a, hitPin: .merged)
        XCTAssertEqual(sut.course?.segments.count, 2, "무시(no-op)")
        XCTAssertEqual(sut.infoMessage, "이미 닫힌 코스입니다")
    }

    func testInfoMessage_clearedOnNextAction() async {
        let sut = makeSUT()
        let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
        await sut.handleMapTap(at: a)
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00), hitPin: .end)
        XCTAssertNotNil(sut.infoMessage)
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.52, longitude: 127.00))
        XCTAssertNil(sut.infoMessage, "다음 액션에서 안내가 사라져야 함")
    }

    func testRoundTripHintVisible_onlyForOpenCourseInTapMode() async {
        let sut = makeSUT()
        XCTAssertFalse(sut.roundTripHintVisible, "코스 없으면 숨김")
        let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
        await sut.handleMapTap(at: a)
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertTrue(sut.roundTripHintVisible)
        await sut.handleMapTap(at: a, hitPin: .start)
        XCTAssertFalse(sut.roundTripHintVisible, "닫힌 코스면 숨김")
    }

    // MARK: - Waypoint coordinates

    func testWaypointCoordinates_areSegmentBoundariesExceptFinal() async {
        let viewModel = makeSUT()
        let a = CourseCoordinate(latitude: 37.50, longitude: 127.00)
        let b = CourseCoordinate(latitude: 37.51, longitude: 127.00)
        let c = CourseCoordinate(latitude: 37.52, longitude: 127.00)
        await viewModel.handleMapTap(at: a)
        await viewModel.handleMapTap(at: b)   // 구간 1: a→b
        await viewModel.handleMapTap(at: c)   // 구간 2: b→c
        XCTAssertEqual(viewModel.course?.segments.count, 2)

        let waypoints = viewModel.waypointCoordinates
        XCTAssertEqual(waypoints.count, 1, "구간 2개 → 경계 1개")
        XCTAssertEqual(waypoints.first, viewModel.course?.segments.first?.coordinates.last)
    }

    func testWaypointCoordinates_emptyForSingleSegment() async {
        let viewModel = makeSUT()
        await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
        await viewModel.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
        XCTAssertTrue(viewModel.waypointCoordinates.isEmpty)
    }
}

// MARK: - Test Doubles

@MainActor
private final class StubCoursePlanningService: CoursePlanningServiceProtocol {
    var routeCallCount = 0
    var recordedFromCoordinates: [CourseCoordinate] = []
    var stubbedResult: PlannedCourse?
    var stubbedError: Error?

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        routeCallCount += 1
        recordedFromCoordinates.append(start)
        if let error = stubbedError { throw error }
        return stubbedResult ?? PlannedCourse(
            segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)]
        )
    }
}

@MainActor
private final class BlockingCoursePlanningService: CoursePlanningServiceProtocol {
    private var routeEnteredContinuation: CheckedContinuation<Void, Never>?
    private var routeReleaseContinuation: CheckedContinuation<Void, Never>?

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        if let continuation = routeEnteredContinuation {
            continuation.resume()
            routeEnteredContinuation = nil
        }
        await withCheckedContinuation { continuation in
            routeReleaseContinuation = continuation
        }
        return PlannedCourse(segments: [.tapped(coordinates: [start, destination], distanceMeters: 100)])
    }

    func waitUntilRouteEntered() async {
        await withCheckedContinuation { continuation in
            routeEnteredContinuation = continuation
        }
    }

    func resumeRoute() {
        routeReleaseContinuation?.resume()
        routeReleaseContinuation = nil
    }
}

@MainActor
private final class StubLocationService: LocationServiceProtocol {
    var stubbedLocation: CourseCoordinate? = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
    var stubbedError: Error?

    func currentLocation() async throws -> CourseCoordinate {
        if let error = stubbedError { throw error }
        return stubbedLocation!
    }
}
