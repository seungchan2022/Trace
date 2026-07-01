# 코스 편집 UX 개선 (탭 자동 연결 + 구간 시각화 + 실시간 패널) Implementation Plan

> 완료(소급 확인): Task 1~5 전부 구현·커밋됨 — `9698dea`(A 탭 자동 연결), `47e3dbf`(A-2 그리기 스트로크=세그먼트), `babc44e`(Task 3 색상 팔레트), `28075e3`(Task 4 색상+거리 라벨), `2a76d93`(Task 5 실시간 패널), `8458f8d`(selectedSegmentIndex QA 버그). 아래 체크박스는 실행 당시 갱신되지 않았으나 실제 구현은 완료 상태다.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 탭 2번째부터 자동으로 기존 경로 끝에 연결되고, 그리기 스트로크마다 독립 세그먼트로 붙으며, 지도 위에 세그먼트별 색상·거리 라벨이 보이고, 우측 상단에 실시간 구간 현황 패널(접힘/펼침, 지도 연동)이 뜨는 코스 편집 UX를 구현한다.

**Architecture:** 기존 `CourseEditSession.attach`의 4방향 최단거리 판단 로직을 탭/그리기 양쪽 모두에서 재사용한다 (탭은 이미 그렇고, 그리기는 스트로크 단위 attach로 새로 통일). 지도 렌더링은 `MapViewRepresentable`에서 세그먼트 배열을 그대로 받아 세그먼트별 `MKPolyline`(색상 인덱스 포함 서브클래스)과 거리 라벨 annotation을 그린다. 패널은 `CoursePlannerPage`의 순수 SwiftUI 오버레이이며, ViewModel의 `selectedSegmentIndex`를 통해 지도와 연동된다.

**Tech Stack:** Swift 6, SwiftUI, MapKit(`MKMapView`/`MKPolyline`/`MKAnnotation`, `UIViewRepresentable`), iOS 17+ `@Observable`, XCTest.

## Global Constraints

- Minimum iOS version: iOS 17.0
- Presentation architecture: MVVM, ViewModel은 MapKit을 import하지 않는다 (지도 좌표 변환·리전 계산은 View 레이어에서)
- 동시성: Swift 6 `async`/`await`, `@MainActor` UI 상태
- 강제 언랩/force try 금지 (swiftlint 에러)
- 커밋 메시지: `docs/agent-rules/git.md` 형식 (Co-Authored-By 금지, 한국어 본문 3~4줄)
- 페이지 전용 서브뷰는 `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+{Role}Component.swift`
- `Trace.xcodeproj/project.pbxproj`는 `PBXFileSystemSynchronizedRootGroup`(Xcode 16 synchronized folders)를 사용한다 — 폴더 안에 파일을 만들거나 지우면 타겟 멤버십이 자동 반영되므로, 이 계획의 어떤 태스크도 `.pbxproj`를 수동으로 편집할 필요가 없다.

---

## Task 1: 탭 자동 연결 — `handleMapTap` 리팩터

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift:107-142` (`handleMapTap`)
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift:141-150` (`mapPins`의 `pendingTapStart` 핀 — 아래 참고)
- Test: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: `CourseEditSession.attach(_:using:)` (기존, 변경 없음), `CourseCoordinate.distanceMeters(to:)` (기존)
- Produces: `handleMapTap(at:)` 시그니처는 변경 없음 (`async`, 인자 `CourseCoordinate`). 내부에 새 private 함수 `nearestEndpoint(to:) -> CourseCoordinate?`, `routeAndAttach(from:to:) async` 추가 — 이후 Task는 이 두 함수를 재사용하지 않는다(그리기는 Task 2에서 별도 헬퍼를 둔다).

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/CoursePlannerViewModelTests.swift`의 `// MARK: - Tap accumulation (MVP6 핵심)` 섹션 바로 아래에 추가:

```swift
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
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/CoursePlannerViewModelTests/testThirdTap_afterExistingSegment_autoConnectsWithSingleTap -only-testing:TraceTests/CoursePlannerViewModelTests/testAutoConnect_choosesNearerEndpoint`
Expected: 두 테스트 모두 FAIL — `testThirdTap...`은 `pendingTapStart`가 nil이 아니라서, `testAutoConnect...`는 세 번째 탭이 대기 상태로 남아 `segments.count`가 여전히 1이라서 실패한다.

- [ ] **Step 3: `handleMapTap` 구현**

`CoursePlannerPageViewModel.swift`의 `handleMapTap`(107-142줄)을 아래로 교체:

```swift
    func handleMapTap(at coordinate: CourseCoordinate) async {
        guard interactionMode == .tap else { return }

        if pendingTapStart == nil {
            if let start = nearestEndpoint(to: coordinate) {
                await routeAndAttach(from: start, to: coordinate)
                return
            }
            // First tap when no course exists yet: set pending start, show pin
            pendingTapStart = coordinate
            return
        }

        // Second tap of the initial pair: route start→coordinate then attach
        guard let start = pendingTapStart else { return }
        pendingTapStart = nil
        await routeAndAttach(from: start, to: coordinate)
    }

    private func nearestEndpoint(to coordinate: CourseCoordinate) -> CourseCoordinate? {
        guard let course = session.course,
              let start = course.coordinates.first,
              let end = course.coordinates.last else { return nil }
        return coordinate.distanceMeters(to: start) <= coordinate.distanceMeters(to: end) ? start : end
    }

    private func routeAndAttach(from start: CourseCoordinate, to coordinate: CourseCoordinate) async {
        recomputeGeneration += 1
        let generation = recomputeGeneration
        isLoading = true
        errorMessage = nil

        do {
            let result = try await coursePlanningService.route(from: start, to: coordinate)
            guard generation == recomputeGeneration else { isLoading = false; return }
            let segment = CourseSegment.tapped(
                coordinates: result.coordinates,
                distanceMeters: result.distanceMeters
            )
            try await session.attach(segment, using: coursePlanningService)
        } catch CoursePlanningError.routeNotFound {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "도보 경로를 찾을 수 없습니다."
        } catch {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "경로를 계산할 수 없습니다."
        }

        isLoading = false
    }
```

이 변경으로 `pendingTapStart`는 이제 코스가 비어 있을 때만 설정된다(자동 연결 경로에서는 대기 상태를 거치지 않음). 즉 `CoursePlannerPage.swift:141-150`의 `mapPins`에서 `hasCourse ? "연결점" ... : "출발" ...` 삼항 분기는 `hasCourse`가 항상 `false`인 죽은 코드가 된다. 아래로 단순화한다:

```swift
        // tap 모드에서 pendingTapStart는 코스가 비어 있을 때만 설정됨 (최초 2탭 대기)
        if viewModel.interactionMode == .tap, let start = viewModel.pendingTapStart {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude),
                title: "출발",
                color: .systemGreen,
                systemImage: "figure.run"
            ))
        }
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/CoursePlannerViewModelTests`
Expected: 전체 `CoursePlannerViewModelTests` PASS (기존 `testFirstTap_setsPendingStart`, `testSecondTap_routesAndCommitsToSession`, `testMultipleTapPairs_accumulate` 등도 그대로 통과해야 함 — 최초 2탭 흐름은 변경 없음).

- [ ] **Step 5: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift TraceTests/CoursePlannerViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat: 탭 자동 연결 — 세 번째 탭부터 가까운 끝점으로 즉시 연결

기존에는 세그먼트가 있어도 매번 2번 탭(시작→끝)을 해야 이어붙기가
됐다. 이제 기존 경로가 있으면 탭 1번만으로 더 가까운 끝점에서 자동
연결된다. attach의 4방향 판단 로직은 그대로 재사용한다.
EOF
)"
```

---

## Task 2: 그리기 모드 — 스트로크 단위 세그먼트화

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift:16-17`
- Delete: `Trace/Domain/CoursePlanning/StrokeDirectionResolver.swift`
- Delete: `Trace/Domain/CoursePlanning/StrokeEntry.swift`
- Delete: `TraceTests/StrokeDirectionResolverTests.swift`
- Test: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: `DrawnPathSampler.sample(_:minSpacingMeters:)` (기존, 변경 없음), `CourseEditSession.attach(_:using:)` (기존)
- Produces: `canUndo: Bool` (더 이상 모드별 분기 없음), `undo() async` (기존 `undoLastStroke()`를 이름 변경 — Task 1에서 만든 헬퍼와 이름 충돌 없음), `course: PlannedCourse?` (`session.course`를 그대로 반환)

- [ ] **Step 1: 실패하는 테스트로 새 그리기 동작 정의**

`TraceTests/CoursePlannerViewModelTests.swift`에서 아래 기존 테스트들을 **삭제**한다 (새 모델과 모순되는 "누적 버퍼" 가정을 검증하던 테스트들):
`testToggleToTapPreservesDrawnRouteAsHistory`, `testAppendStrokeNearEndAppendsAndRoutesOnlyNewSegment`, `testAppendStrokeNearStartPrepends`, `testUndoAllStrokesRestoresHistory`, `testDrawModeUndoWithNoStrokes_fallsThroughToSession`, `testUndoRemovesLastAddedStroke`, `testRapidStrokesDebounceRecompute`, `testDrawRouteIsPreservedWhenEnteringTapMode`, `testDrawRouteIsPreservedAsCourseOnModeSwitch`, `testDrawNearRouteStartPrependsCorrectly`.

그 자리(`// MARK: - Incremental stroke pipeline` 섹션)에 새 테스트로 교체:

```swift
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
```

기존 `testToggleToDrawPreservesTapRouteAsHistory`, `testClearResetsAllState`, `testTapUndo_removesLastSegment`, `testClearAlsoResetsSession`, `testTapRouteIsPreservedWhenEnteringDrawMode`, `testToggleDuringRouteCalculationDiscardsStaleCourse`에서 `sut.drawnStrokes` 참조는 제거한다 (해당 필드가 사라지므로). 예를 들어 `testClearResetsAllState`는:

```swift
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
```

동일한 방식으로 `drawnStrokes` 참조가 있는 나머지 테스트에서도 그 assertion 줄만 제거한다 (다른 assertion은 유지).

마지막으로 `undoLastStroke()` 호출부를 전부 `undo()`로 바꾼다 (Step 1에서 새로 추가한 테스트는 이미 `undo()`로 작성됨. 기존 `testTapUndo_removesLastSegment`도 `await sut.undo()`로 변경).

- [ ] **Step 2: 테스트 실행 — 컴파일 실패 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/CoursePlannerViewModelTests`
Expected: 컴파일 에러 — `undo()`, 그리고 `drawnStrokes`가 아직 존재하므로 실제로는 컴파일은 될 수 있으나 `undo` 심볼이 없어 실패한다. (이 단계는 "아직 구현 안 됨"을 확인하는 목적이므로 컴파일 실패도 유효한 RED 상태다.)

- [ ] **Step 3: ViewModel 구현**

`CoursePlannerPageViewModel.swift` 전체를 아래로 교체한다:

```swift
import Foundation
import Observation

enum InteractionMode: Equatable {
    case tap
    case draw
}

@MainActor
@Observable
final class CoursePlannerPageViewModel {
    // Application layer: mutable course being planned
    let session = CourseEditSession()

    // Tap mode: first tap waits here until second tap routes A→B
    private(set) var pendingTapStart: CourseCoordinate?

    // UI state
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var initialCameraCoordinate: CourseCoordinate?
    private(set) var interactionMode: InteractionMode = .tap
    private(set) var selectedSegmentIndex: Int?
    var showLocationDeniedAlert = false

    private let coursePlanningService: CoursePlanningServiceProtocol
    private let locationService: LocationServiceProtocol
    private let cameraStateStore: CameraStateStore
    private var recomputeGeneration = 0

    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol,
        cameraStateStore: CameraStateStore = CameraStateStore()
    ) {
        self.coursePlanningService = coursePlanningService
        self.locationService = locationService
        self.cameraStateStore = cameraStateStore
    }

    var isDrawingMode: Bool { interactionMode == .draw }

    var canUndo: Bool { !session.segments.isEmpty }

    var course: PlannedCourse? { session.course }

    var distanceText: String? {
        guard let course else { return nil }
        return String(format: "%.2f km", course.distanceMeters / 1000)
    }

    // MARK: - Location

    func bootstrapLocation() async {
        let hasRestoredCamera = cameraStateStore.restore() != nil
        do {
            let location = try await locationService.currentLocation()
            if !hasRestoredCamera { initialCameraCoordinate = location }
        } catch LocationError.denied {
            showLocationDeniedAlert = true
            if !hasRestoredCamera {
                initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
            }
        } catch {
            if !hasRestoredCamera {
                initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
            }
        }
    }

    func recenterToCurrentLocation() async -> CourseCoordinate? {
        try? await locationService.currentLocation()
    }

    // MARK: - Tap Mode

    func handleMapTap(at coordinate: CourseCoordinate) async {
        guard interactionMode == .tap else { return }

        if pendingTapStart == nil {
            if let start = nearestEndpoint(to: coordinate) {
                await routeAndAttach(from: start, to: coordinate)
                return
            }
            pendingTapStart = coordinate
            return
        }

        guard let start = pendingTapStart else { return }
        pendingTapStart = nil
        await routeAndAttach(from: start, to: coordinate)
    }

    private func nearestEndpoint(to coordinate: CourseCoordinate) -> CourseCoordinate? {
        guard let course = session.course,
              let start = course.coordinates.first,
              let end = course.coordinates.last else { return nil }
        return coordinate.distanceMeters(to: start) <= coordinate.distanceMeters(to: end) ? start : end
    }

    private func routeAndAttach(from start: CourseCoordinate, to coordinate: CourseCoordinate) async {
        recomputeGeneration += 1
        let generation = recomputeGeneration
        isLoading = true
        errorMessage = nil

        do {
            let result = try await coursePlanningService.route(from: start, to: coordinate)
            guard generation == recomputeGeneration else { isLoading = false; return }
            let segment = CourseSegment.tapped(
                coordinates: result.coordinates,
                distanceMeters: result.distanceMeters
            )
            try await session.attach(segment, using: coursePlanningService)
        } catch CoursePlanningError.routeNotFound {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "도보 경로를 찾을 수 없습니다."
        } catch {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "경로를 계산할 수 없습니다."
        }

        isLoading = false
    }

    // MARK: - Mode Toggle

    func toggleDrawingMode() async {
        switch interactionMode {
        case .tap:
            pendingTapStart = nil
            recomputeGeneration += 1
            errorMessage = nil
            isLoading = false
            interactionMode = .draw

        case .draw:
            recomputeGeneration += 1
            interactionMode = .tap
        }
    }

    // MARK: - Draw Mode

    func appendStroke(_ stroke: [CourseCoordinate]) async {
        guard stroke.count >= 2 else { return }
        recomputeGeneration += 1
        let generation = recomputeGeneration
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard generation == recomputeGeneration else { isLoading = false; return }
        await routeStrokeAndAttach(stroke, generation: generation)
    }

    private func routeStrokeAndAttach(_ rawStroke: [CourseCoordinate], generation: Int) async {
        let sampled = DrawnPathSampler.sample(rawStroke)
        guard sampled.count >= 2 else { return }

        isLoading = true
        errorMessage = nil

        do {
            var coords: [CourseCoordinate] = []
            var distance = 0.0
            for i in 0..<(sampled.count - 1) {
                let leg = try await coursePlanningService.route(from: sampled[i], to: sampled[i + 1])
                guard generation == recomputeGeneration else { isLoading = false; return }
                coords.append(contentsOf: coords.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst()))
                distance += leg.distanceMeters
            }
            let segment = CourseSegment.drawn(coordinates: coords, distanceMeters: distance)
            try await session.attach(segment, using: coursePlanningService)
        } catch CoursePlanningError.throttled {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "요청이 많아 잠시 후 다시 시도해주세요"
        } catch {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "경로를 계산할 수 없습니다."
        }
        isLoading = false
    }

    // MARK: - Undo / Clear

    func undo() async {
        session.undo()
    }

    func clear() {
        recomputeGeneration += 1
        session.clear()
        pendingTapStart = nil
        selectedSegmentIndex = nil
        errorMessage = nil
        isLoading = false
    }

    // MARK: - Segment selection (지도 연동용, Task 5에서 사용)

    func selectSegment(at index: Int?) {
        selectedSegmentIndex = index
    }
}
```

`CoursePlannerPage+ControlsComponent.swift:16-17`을 아래로 변경:

```swift
            Button("되돌리기") { Task { await viewModel.undo() } }
                .disabled(!viewModel.canUndo)
                .accessibilityIdentifier("coursePlanner.undo")
```

`Trace/Domain/CoursePlanning/StrokeDirectionResolver.swift`, `Trace/Domain/CoursePlanning/StrokeEntry.swift`, `TraceTests/StrokeDirectionResolverTests.swift`를 삭제한다.

- [ ] **Step 4: 테스트 실행 — 통과 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/CoursePlannerViewModelTests`
Expected: 전체 PASS.

Run: `xcodebuild build -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED (삭제한 파일을 참조하는 곳이 없어야 함 — Xcode 프로젝트 파일에서도 참조 제거 필요할 수 있음, 빌드로 확인).

- [ ] **Step 5: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift \
        Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift \
        TraceTests/CoursePlannerViewModelTests.swift
git rm Trace/Domain/CoursePlanning/StrokeDirectionResolver.swift \
       Trace/Domain/CoursePlanning/StrokeEntry.swift \
       TraceTests/StrokeDirectionResolverTests.swift
git commit -m "$(cat <<'EOF'
refactor: 그리기 모드 스트로크=세그먼트로 통일

기존엔 그리기 모드 종료 시점에야 누적 버퍼 전체가 세그먼트 1개로
붙었다. 이제 탭처럼 스트로크가 끝날 때마다 attach()로 즉시 세그먼트
하나가 붙는다. attach의 4방향 판단을 재사용하므로 스트로크 전용
StrokeDirectionResolver/StrokeEntry와 누적 버퍼가 필요 없어졌다.
EOF
)"
```

---

## Task 3: 세그먼트 색상 팔레트

**Files:**
- Create: `Trace/Pages/CoursePlannerPage/SegmentPalette.swift`
- Test: `TraceTests/SegmentPaletteTests.swift`

**Interfaces:**
- Produces: `SegmentPalette.color(at index: Int) -> UIColor` — Task 4(Map)와 Task 5(Panel)가 이 함수를 그대로 호출한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/SegmentPaletteTests.swift` 생성:

```swift
import XCTest
@testable import Trace

final class SegmentPaletteTests: XCTestCase {
    func testColorsCycleThroughPalette() {
        let paletteSize = 6
        let first = SegmentPalette.color(at: 0)
        let wrapped = SegmentPalette.color(at: paletteSize)
        XCTAssertEqual(first, wrapped, "팔레트 크기만큼 지나면 순환되어야 함")
    }

    func testDifferentIndicesGiveDifferentColorsWithinOneCycle() {
        let a = SegmentPalette.color(at: 0)
        let b = SegmentPalette.color(at: 1)
        XCTAssertNotEqual(a, b)
    }
}
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/SegmentPaletteTests`
Expected: FAIL — `SegmentPalette`가 정의되지 않아 컴파일 에러.

- [ ] **Step 3: 구현**

`Trace/Pages/CoursePlannerPage/SegmentPalette.swift` 생성:

```swift
import UIKit

enum SegmentPalette {
    private static let colors: [UIColor] = [
        .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemTeal, .systemPink,
    ]

    static func color(at index: Int) -> UIColor {
        colors[index % colors.count]
    }
}
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/SegmentPaletteTests`
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/SegmentPalette.swift TraceTests/SegmentPaletteTests.swift
git commit -m "$(cat <<'EOF'
feat: 세그먼트 색상 순환 팔레트 추가

지도 위 구간 색상(Task 4)과 실시간 구간 패널(Task 5)이 같은 색상
소스를 참조해야 시각적으로 일관되므로, 인덱스→색상 매핑을 순수
함수 하나로 뽑아 양쪽에서 공유한다.
EOF
)"
```

---

## Task 4: 지도 위 세그먼트별 색상 + 거리 라벨

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (`mapView`, `overlayCoordinates` 프로퍼티 대체)

**Interfaces:**
- Consumes: `SegmentPalette.color(at:)` (Task 3), `CourseSegment` (기존)
- Produces: `MapViewRepresentable`의 `overlayCoordinates: [CLLocationCoordinate2D]` 파라미터를 `segments: [CourseSegment]`로 교체, `selectedSegmentIndex: Int?` 파라미터 추가 — Task 5가 이 파라미터로 하이라이트를 트리거한다.

이 Task는 UIKit(`MKMapView`) 렌더링 코드라 XCTest 유닛 테스트로 시각적 결과를 검증하기 어렵다. 대신 **컴파일 가능성 + 실기기/시뮬레이터 스크린샷**으로 검증한다 (Step 2/4가 QA 스텝으로 대체됨).

- [ ] **Step 1: `MapViewRepresentable` 시그니처와 렌더링 로직 교체**

`Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` 전체를 아래로 교체:

```swift
import MapKit
import SwiftUI

// MARK: - Supporting Types

struct MapPin: Equatable {
    let coordinate: CLLocationCoordinate2D
    let title: String
    let color: UIColor
    let systemImage: String

    static func == (lhs: MapPin, rhs: MapPin) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.title == rhs.title
    }
}

final class ColoredPinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let color: UIColor
    let systemImage: String

    init(coordinate: CLLocationCoordinate2D, title: String, color: UIColor, systemImage: String) {
        self.coordinate = coordinate
        self.title = title
        self.color = color
        self.systemImage = systemImage
    }
}

final class SegmentPolyline: MKPolyline {
    var segmentIndex: Int = 0
}

final class SegmentDistanceAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let distanceText: String
    let color: UIColor

    init(coordinate: CLLocationCoordinate2D, distanceText: String, color: UIColor) {
        self.coordinate = coordinate
        self.distanceText = distanceText
        self.color = color
    }
}

final class SegmentDistanceAnnotationView: MKAnnotationView {
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        addSubview(label)
        canShowCallout = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, color: UIColor) {
        label.text = " \(text) "
        label.backgroundColor = color
        label.sizeToFit()
        bounds = label.bounds
        centerOffset = .zero
    }
}

private struct SegmentSnapshot: Equatable {
    let coordinateCount: Int
    let first: CLLocationCoordinate2D?
    let last: CLLocationCoordinate2D?

    static func == (lhs: SegmentSnapshot, rhs: SegmentSnapshot) -> Bool {
        guard lhs.coordinateCount == rhs.coordinateCount else { return false }
        switch (lhs.first, rhs.first, lhs.last, rhs.last) {
        case (nil, nil, nil, nil): return true
        case let (lf?, rf?, ll?, rl?):
            return abs(lf.latitude - rf.latitude) < 0.00001 &&
                abs(ll.latitude - rl.latitude) < 0.00001
        default: return false
        }
    }
}

// MARK: - MapViewRepresentable

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var segments: [CourseSegment]
    var pins: [MapPin]
    var selectedSegmentIndex: Int?
    var isDrawingMode: Bool
    var onStrokeUpdate: ([CGPoint]) -> Void
    var onStrokeEnded: ([CourseCoordinate]) -> Void
    var onMapTap: ((CourseCoordinate) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.setRegion(region, animated: false)

        let drawGR = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDraw(_:))
        )
        drawGR.maximumNumberOfTouches = 1
        drawGR.isEnabled = false
        mapView.addGestureRecognizer(drawGR)
        context.coordinator.drawGestureRecognizer = drawGR

        let twoFingerPanGR = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerPan(_:))
        )
        twoFingerPanGR.minimumNumberOfTouches = 2
        twoFingerPanGR.maximumNumberOfTouches = 2
        twoFingerPanGR.isEnabled = false
        mapView.addGestureRecognizer(twoFingerPanGR)
        context.coordinator.twoFingerPanGestureRecognizer = twoFingerPanGR

        let pinchGR = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinchGR.isEnabled = false
        mapView.addGestureRecognizer(pinchGR)
        context.coordinator.pinchGestureRecognizer = pinchGR

        let tapGR = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGR.isEnabled = !isDrawingMode
        mapView.addGestureRecognizer(tapGR)
        context.coordinator.tapGestureRecognizer = tapGR

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self

        let mapCenter = uiView.region.center
        let latDiff = abs(mapCenter.latitude - region.center.latitude)
        let lonDiff = abs(mapCenter.longitude - region.center.longitude)
        let spanDiff = abs(uiView.region.span.latitudeDelta - region.span.latitudeDelta)
        if latDiff > 0.0001 || lonDiff > 0.0001 || spanDiff > 0.0001 {
            uiView.setRegion(region, animated: true)
        }

        let currentSnapshots = segments.map {
            SegmentSnapshot(
                coordinateCount: $0.coordinates.count,
                first: $0.coordinates.first.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
                last: $0.coordinates.last.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            )
        }
        if context.coordinator.lastSegmentSnapshots != currentSnapshots {
            uiView.removeOverlays(uiView.overlays)
            uiView.removeAnnotations(uiView.annotations.filter { $0 is SegmentDistanceAnnotation })
            for (index, segment) in segments.enumerated() {
                var coords = segment.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                guard coords.count >= 2 else { continue }
                let polyline = SegmentPolyline(coordinates: &coords, count: coords.count)
                polyline.segmentIndex = index
                uiView.addOverlay(polyline)

                let midIndex = coords.count / 2
                let annotation = SegmentDistanceAnnotation(
                    coordinate: coords[midIndex],
                    distanceText: String(format: "%.0fm", segment.distanceMeters),
                    color: SegmentPalette.color(at: index)
                )
                uiView.addAnnotation(annotation)
            }
            context.coordinator.lastSegmentSnapshots = currentSnapshots
        }

        if context.coordinator.lastSelectedIndex != selectedSegmentIndex {
            context.coordinator.lastSelectedIndex = selectedSegmentIndex
            for overlay in uiView.overlays {
                guard let polyline = overlay as? SegmentPolyline,
                      let renderer = uiView.renderer(for: polyline) as? MKPolylineRenderer else { continue }
                configureRenderer(renderer, segmentIndex: polyline.segmentIndex, selected: selectedSegmentIndex)
                renderer.setNeedsDisplay()
            }
        }

        let existing = uiView.annotations.filter { !($0 is MKUserLocation) }
            .compactMap { $0 as? ColoredPinAnnotation }
        let pinsChanged = existing.count != pins.count ||
            zip(existing, pins).contains { ann, pin in
                abs(ann.coordinate.latitude - pin.coordinate.latitude) > 0.00001 ||
                abs(ann.coordinate.longitude - pin.coordinate.longitude) > 0.00001
            }
        if pinsChanged {
            uiView.removeAnnotations(uiView.annotations.compactMap { $0 as? ColoredPinAnnotation })
            for pin in pins {
                uiView.addAnnotation(ColoredPinAnnotation(
                    coordinate: pin.coordinate,
                    title: pin.title,
                    color: pin.color,
                    systemImage: pin.systemImage
                ))
            }
        }

        let wasDrawing = context.coordinator.drawGestureRecognizer?.isEnabled ?? false
        if wasDrawing != isDrawingMode {
            uiView.isScrollEnabled = !isDrawingMode
            uiView.isZoomEnabled = !isDrawingMode
            uiView.isPitchEnabled = !isDrawingMode
            uiView.isRotateEnabled = !isDrawingMode
            context.coordinator.drawGestureRecognizer?.isEnabled = isDrawingMode
            context.coordinator.twoFingerPanGestureRecognizer?.isEnabled = isDrawingMode
            context.coordinator.pinchGestureRecognizer?.isEnabled = isDrawingMode
            context.coordinator.tapGestureRecognizer?.isEnabled = !isDrawingMode
        }
    }

    private func configureRenderer(_ renderer: MKPolylineRenderer, segmentIndex: Int, selected: Int?) {
        renderer.strokeColor = SegmentPalette.color(at: segmentIndex)
        renderer.lineWidth = segmentIndex == selected ? 9 : 6
    }
}

// MARK: - Coordinator

extension MapViewRepresentable {
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        var lastSegmentSnapshots: [SegmentSnapshot] = []
        var lastSelectedIndex: Int?

        init(parent: MapViewRepresentable) {
            self.parent = parent
        }

        // MARK: Overlay

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? SegmentPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            parent.configureRenderer(renderer, segmentIndex: polyline.segmentIndex, selected: parent.selectedSegmentIndex)
            return renderer
        }

        // MARK: Annotation

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let distanceAnnotation = annotation as? SegmentDistanceAnnotation {
                let identifier = "segmentDistance"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? SegmentDistanceAnnotationView
                    ?? SegmentDistanceAnnotationView(annotation: distanceAnnotation, reuseIdentifier: identifier)
                view.annotation = distanceAnnotation
                view.configure(text: distanceAnnotation.distanceText, color: distanceAnnotation.color)
                return view
            }
            guard let pin = annotation as? ColoredPinAnnotation else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "coloredPin")
            view.markerTintColor = pin.color
            view.glyphImage = UIImage(systemName: pin.systemImage)
            return view
        }

        // MARK: Camera

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            parent.region = mapView.region
        }

        // MARK: Gesture State

        weak var drawGestureRecognizer: UIPanGestureRecognizer?
        weak var twoFingerPanGestureRecognizer: UIPanGestureRecognizer?
        weak var pinchGestureRecognizer: UIPinchGestureRecognizer?
        weak var tapGestureRecognizer: UITapGestureRecognizer?
        private var currentStrokePoints: [CGPoint] = []
        private var currentStrokeCoords: [CourseCoordinate] = []
        private var panStartCenter: CLLocationCoordinate2D?
        private var pinchStartSpan: MKCoordinateSpan?
        private var pinchStartScale: CGFloat = 1.0

        // MARK: Draw

        @objc func handleDraw(_ recognizer: UIPanGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }

            if recognizer.numberOfTouches > 1 {
                currentStrokePoints = []
                currentStrokeCoords = []
                parent.onStrokeUpdate([])
                recognizer.state = .cancelled
                return
            }

            let point = recognizer.location(in: mapView)
            let clCoord = mapView.convert(point, toCoordinateFrom: mapView)
            let coord = CourseCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude)

            switch recognizer.state {
            case .began, .changed:
                currentStrokePoints.append(point)
                currentStrokeCoords.append(coord)
                parent.onStrokeUpdate(currentStrokePoints)
            case .ended, .cancelled:
                currentStrokePoints.append(point)
                currentStrokeCoords.append(coord)
                let stroke = currentStrokeCoords
                currentStrokePoints = []
                currentStrokeCoords = []
                parent.onStrokeUpdate([])
                if stroke.count >= 2 {
                    parent.onStrokeEnded(stroke)
                }
            default:
                break
            }
        }

        // MARK: Tap

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            let point = recognizer.location(in: mapView)
            let clCoord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onMapTap?(CourseCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude))
        }

        // MARK: Two-Finger Pan

        @objc func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            switch recognizer.state {
            case .began:
                panStartCenter = mapView.region.center
            case .changed:
                guard let startCenter = panStartCenter else { return }
                let translation = recognizer.translation(in: mapView)
                let region = mapView.region
                let latPerPoint = region.span.latitudeDelta / mapView.bounds.height
                let lonPerPoint = region.span.longitudeDelta / mapView.bounds.width
                let newCenter = CLLocationCoordinate2D(
                    latitude: startCenter.latitude + translation.y * latPerPoint,
                    longitude: startCenter.longitude - translation.x * lonPerPoint
                )
                let newRegion = MKCoordinateRegion(center: newCenter, span: region.span)
                mapView.setRegion(newRegion, animated: false)
            case .ended, .cancelled:
                panStartCenter = nil
            default:
                break
            }
        }

        // MARK: Pinch

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            switch recognizer.state {
            case .began:
                pinchStartSpan = mapView.region.span
                pinchStartScale = recognizer.scale
            case .changed:
                guard let startSpan = pinchStartSpan else { return }
                let scaleDelta = pinchStartScale / recognizer.scale
                let newSpan = MKCoordinateSpan(
                    latitudeDelta: min(max(startSpan.latitudeDelta * scaleDelta, 0.001), 100),
                    longitudeDelta: min(max(startSpan.longitudeDelta * scaleDelta, 0.001), 100)
                )
                let newRegion = MKCoordinateRegion(center: mapView.region.center, span: newSpan)
                mapView.setRegion(newRegion, animated: false)
            case .ended, .cancelled:
                pinchStartSpan = nil
            default:
                break
            }
        }
    }
}
```

- [ ] **Step 2: `CoursePlannerPage.swift` 호출부 갱신**

`Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`에서 `overlayCoordinates` 프로퍼티(115-119줄)를 삭제하고, `mapView`(72-113줄)의 `MapViewRepresentable(...)` 호출을 아래로 교체:

```swift
        MapViewRepresentable(
            region: $cameraRegion,
            segments: viewModel.course?.segments ?? [],
            pins: mapPins,
            selectedSegmentIndex: viewModel.selectedSegmentIndex,
            isDrawingMode: viewModel.isDrawingMode,
            onStrokeUpdate: { points in currentStrokePoints = points },
            onStrokeEnded: { stroke in Task { await viewModel.appendStroke(stroke) } },
            onMapTap: { coord in Task { await viewModel.handleMapTap(at: coord) } }
        )
```

- [ ] **Step 3: 빌드 확인**

Run: `xcodebuild build -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: 시뮬레이터에서 시각 확인**

XcodeBuildMCP `build_run_sim`으로 실행 후 탭 모드로 3개 이상 세그먼트를 만들고 스크린샷(`screenshot`)을 찍어 다음을 확인한다:
- 세그먼트마다 다른 색 폴리라인이 보인다
- 각 세그먼트 중점에 거리 라벨이 보인다
- 지도를 팬/줌해도 오버레이가 깜빡이거나 사라지지 않는다

- [ ] **Step 5: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift
git commit -m "$(cat <<'EOF'
feat: 지도 위 세그먼트별 색상 폴리라인 + 거리 라벨

세그먼트 배열을 그대로 받아 세그먼트마다 색상이 다른 MKPolyline과
중점 거리 라벨을 그린다. 카메라 이동마다 불필요하게 다시 그리지
않도록 세그먼트 개수/좌표 스냅샷으로 diff한다.
EOF
)"
```

---

## Task 5: 실시간 구간 현황 패널 + 지도 연동

**Files:**
- Create: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+SegmentPanelComponent.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`

**Interfaces:**
- Consumes: `viewModel.course?.segments`, `viewModel.selectedSegmentIndex`, `viewModel.selectSegment(at:)` (Task 2), `SegmentPalette.color(at:)` (Task 3)
- Produces: 없음 (최종 UI 계층 — 이후 Task 없음)

- [ ] **Step 1: 패널 뷰 작성**

`Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+SegmentPanelComponent.swift` 생성:

```swift
import SwiftUI

extension CoursePlannerPage {
    var segmentPanel: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if isSegmentPanelExpanded {
                expandedSegmentList
            } else {
                collapsedSegmentChip
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
        .accessibilityIdentifier("coursePlanner.segmentPanel")
    }

    private var collapsedSegmentChip: some View {
        Button {
            isSegmentPanelExpanded = true
        } label: {
            Text(viewModel.distanceText ?? "0.00 km")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .accessibilityIdentifier("coursePlanner.segmentPanel.collapsed")
    }

    private var expandedSegmentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("구간")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Button {
                    isSegmentPanelExpanded = false
                } label: {
                    Image(systemName: "chevron.up")
                }
                .accessibilityIdentifier("coursePlanner.segmentPanel.collapse")
            }

            ForEach(Array((viewModel.course?.segments ?? []).enumerated()), id: \.offset) { index, segment in
                Button {
                    viewModel.selectSegment(at: index)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(uiColor: SegmentPalette.color(at: index)))
                            .frame(width: 10, height: 10)
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.0fm", segment.distanceMeters))
                                .font(.caption)
                            Text(String(format: "누적 %.2fkm", cumulativeDistanceMeters(upTo: index) / 1000))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coursePlanner.segmentPanel.item.\(index)")
            }
        }
        .padding(12)
        .frame(minWidth: 220)
    }

    private func cumulativeDistanceMeters(upTo index: Int) -> Double {
        guard let segments = viewModel.course?.segments, index < segments.count else { return 0 }
        return segments.prefix(through: index).reduce(0) { $0 + $1.distanceMeters }
    }
}
```

- [ ] **Step 2: `CoursePlannerPage.swift`에 패널 연결 + 카메라 연동**

`CoursePlannerPage.swift`에 `@State private var isSegmentPanelExpanded = false` 필드를 `currentStrokePoints` 선언 바로 아래에 추가한다.

`mapView`의 `.overlay(alignment: .bottomTrailing) { ... }`(내 위치 버튼) 블록 뒤에 아래 오버레이를 추가한다:

```swift
        .overlay(alignment: .topTrailing) {
            segmentPanel
        }
```

`body`의 `.task { ... }` 블록 뒤, `.onChange(of: scenePhase)` 앞에 아래 `.onChange`를 추가해 세그먼트 선택 시 카메라를 이동시킨다:

```swift
            .onChange(of: viewModel.selectedSegmentIndex) { _, newIndex in
                guard let newIndex,
                      let segments = viewModel.course?.segments,
                      newIndex < segments.count,
                      let region = regionFitting(segments[newIndex].coordinates) else { return }
                cameraRegion = region
            }
```

`saveCameraPosition()` 아래에 좌표 배열을 감싸는 리전을 계산하는 private 함수를 추가한다:

```swift
    private func regionFitting(_ coordinates: [CourseCoordinate]) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.003),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.003)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
```

- [ ] **Step 3: 빌드 확인**

Run: `xcodebuild build -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: 시뮬레이터에서 동작 확인**

XcodeBuildMCP로 실행 후:
- 세그먼트 3개 이상 만든 뒤 우측 상단 칩("N.NN km")이 보이는지 확인, 탭하면 펼쳐지는지 확인
- 펼친 목록에서 항목 하나를 탭하면 지도 카메라가 해당 세그먼트로 이동하고, 해당 폴리라인이 굵게 강조되는지 확인
- 접기 버튼으로 다시 접히는지 확인
- 패널이 내 위치 버튼이나 지도 조작(팬/줌/그리기)을 가리지 않는지 확인

- [ ] **Step 4-1: 전체 테스트 스위트(UI 테스트 포함) 실행**

Task 1에서 탭 상호작용이 바뀌었으므로(3번째 탭부터 대기 핀 없이 즉시 연결), 두 번 탭해서 핀이 뜨는 것을 전제로 한 UI 테스트가 있다면 이 시점에 회귀가 드러난다.

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: `TraceTests`, `TraceUITests` 전체 PASS. `TraceUITests`에서 실패가 있으면 새 탭 동작(최초 2탭만 대기, 이후 자동 연결)에 맞게 해당 UI 테스트를 수정한다.

- [ ] **Step 5: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+SegmentPanelComponent.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift
git commit -m "$(cat <<'EOF'
feat: 실시간 구간 현황 패널 + 지도 연동

지도 우측 상단에 접힘(총 거리)/펼침(세그먼트별 순번·거리·누적거리)
오버레이 패널을 추가한다. 펼친 목록에서 세그먼트를 탭하면 해당
구간이 보이도록 카메라가 이동하고 지도 위 폴리라인이 강조된다.
EOF
)"
```

---

## Self-Review 결과

- **spec 커버리지**: A(Task 1), A-2 그리기 세그먼트화(Task 2), B 색상+라벨(Task 3+4), E 패널+지도연동(Task 5) 모두 태스크로 매핑됨. C/D는 설계 문서에 명시한 대로 범위 밖(별도 디버깅 세션).
- **플레이스홀더 스캔**: 없음.
- **타입 일관성**: `undo()`(Task 2) 이후 `CoursePlannerPage+ControlsComponent.swift`도 같은 Task에서 함께 갱신. `segments`/`selectedSegmentIndex` 파라미터명이 Task 4·5·CoursePlannerPage.swift 호출부에서 동일하게 사용됨.
- **어드바이저 2차 검토 반영**: Task 4의 타입체크 안 되는 `uiView.renderer(for: .init())` 죽은 분기 삭제, 하이라이트 재적용 시 `renderer.setNeedsDisplay()` 추가, Task 1에 "연결점" 죽은 분기 정리 편입, `.pbxproj`가 synchronized folders라 타겟 멤버십 수동 작업 불필요함을 Global Constraints에 명시, Task 5에 `TraceUITests` 포함 전체 스위트 실행 스텝 추가.
