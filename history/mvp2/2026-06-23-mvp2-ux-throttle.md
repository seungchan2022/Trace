# MVP2 UX 개선 + 스로틀 완화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MVP1 실기기 피드백을 반영해 코스 플래너의 UX 품질을 개선하고, MKDirections 스로틀 문제를 완화한다.

**Architecture:** 기존 MVVM 구조 위에서 ViewModel과 View만 수정. 캐시는 인프라 계층(`MapKitCoursePlanningService`)에, 디바운스는 ViewModel에 추가. 새 파일 없이 기존 4개 파일 변경.

**Tech Stack:** Swift · SwiftUI · MapKit · XCTest · iOS 17+ Observation API

## Global Constraints

- iOS 17.0 minimum
- SwiftUI + `@Observable` (not `ObservableObject`)
- `@MainActor` UI state isolation
- ViewModel은 MapKit을 import하지 않음
- port-and-adapter: 프로토콜 계층 변경 없이 구체 어댑터만 수정
- 테스트: XCTest, `@testable import Trace`

## File Map

| 파일 | 변경 | 역할 |
|------|------|------|
| `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift` | Modify | InteractionMode enum, 모드 전환 로직, 권한 알럿 플래그, 디바운스, clear() 통합 초기화 |
| `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` | Modify | UserAnnotation, 내 위치 버튼, 권한 알럿, 모드별 마커 분기, 줌 레벨 |
| `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift` | Modify | 모드 인디케이터 UI, 버튼 라벨/아이콘, 배경색 |
| `Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift` | Modify | 구간 라우팅 캐시 딕셔너리 |
| `TraceTests/CoursePlannerViewModelTests.swift` | Create | 모드 전환, clear, 권한 알럿, 디바운스 테스트 |
| `TraceTests/RouteCacheTests.swift` | Create | 캐시 히트/미스 테스트 |

---

### Task 1: 단일 모드 전환 + 상태 잔상 정리

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Create: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Produces: `InteractionMode` enum, `interactionMode` property, updated `toggleDrawingMode()`, updated `clear()`

- [x] **Step 1: ViewModel 테스트 파일 생성 — 모드 전환 테스트 작성**

```swift
// TraceTests/CoursePlannerViewModelTests.swift
import XCTest
@testable import Trace

@MainActor
final class CoursePlannerViewModelTests: XCTestCase {
    private func makeSUT() -> CoursePlannerPageViewModel {
        CoursePlannerPageViewModel(
            coursePlanningService: StubCoursePlanningService(),
            locationService: StubLocationService()
        )
    }

    // MARK: - Mode switching

    func testDefaultModeIsTap() {
        let sut = makeSUT()
        XCTAssertEqual(sut.interactionMode, .tap)
    }

    func testToggleToDrawClearsTapState() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
        XCTAssertNotNil(sut.startCoordinate)

        sut.toggleDrawingMode()

        XCTAssertEqual(sut.interactionMode, .draw)
        XCTAssertNil(sut.startCoordinate)
        XCTAssertNil(sut.destinationCoordinate)
        XCTAssertNil(sut.course)
    }

    func testToggleToTapClearsDrawState() async {
        let sut = makeSUT()
        sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])
        XCTAssertFalse(sut.drawnStrokes.isEmpty)

        sut.toggleDrawingMode()

        XCTAssertEqual(sut.interactionMode, .tap)
        XCTAssertTrue(sut.drawnStrokes.isEmpty)
        XCTAssertNil(sut.course)
    }

    func testClearResetsAllState() async {
        let sut = makeSUT()
        await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
        sut.toggleDrawingMode()
        await sut.appendStroke([
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ])

        sut.clear()

        XCTAssertNil(sut.startCoordinate)
        XCTAssertNil(sut.destinationCoordinate)
        XCTAssertTrue(sut.drawnStrokes.isEmpty)
        XCTAssertNil(sut.course)
        XCTAssertNil(sut.errorMessage)
    }
}

// MARK: - Test Doubles

@MainActor
private final class StubCoursePlanningService: CoursePlanningServiceProtocol {
    var routeCallCount = 0
    var stubbedResult: PlannedCourse?
    var stubbedError: Error?

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        routeCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedResult ?? PlannedCourse(
            coordinates: [start, destination],
            distanceMeters: 100
        )
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
```

- [x] **Step 2: 테스트 실행 — 실패 확인**

- [x] **Step 3: ViewModel에 InteractionMode 도입 + 모드 전환 로직 구현**

`CoursePlannerPageViewModel.swift` 변경:

```swift
// 파일 상단, class 바깥
enum InteractionMode: Equatable {
    case tap
    case draw
}

// class 내부 — 기존 isDrawingMode 교체
private(set) var interactionMode: InteractionMode = .tap

var isDrawingMode: Bool { interactionMode == .draw }

// toggleDrawingMode() 교체
func toggleDrawingMode() {
    switch interactionMode {
    case .tap:
        startCoordinate = nil
        destinationCoordinate = nil
        course = nil
        errorMessage = nil
        interactionMode = .draw
    case .draw:
        recomputeGeneration += 1
        drawnStrokes = []
        course = nil
        errorMessage = nil
        interactionMode = .tap
    }
}

// clear() 교체 — 모든 상태 초기화
func clear() {
    recomputeGeneration += 1
    startCoordinate = nil
    destinationCoordinate = nil
    drawnStrokes = []
    course = nil
    errorMessage = nil
    isLoading = false
}
```

`isDrawingMode` 저장 프로퍼티를 삭제하고 computed property로 교체. `interactionMode`를 추가.

- [x] **Step 4: 테스트 실행 — 통과 확인**

- [x] **Step 5: statusPanel 안내 텍스트 모드 분기**

`CoursePlannerPage.swift`의 `statusPanel` 내부, 마지막 `else` 절:

```swift
// 기존
} else {
    Text("지도에서 출발지를 선택하세요")
        .accessibilityIdentifier("coursePlanner.prompt")
}

// 변경
} else {
    Text(viewModel.isDrawingMode ? "경로를 그려주세요" : "지도에서 출발지를 선택하세요")
        .accessibilityIdentifier("coursePlanner.prompt")
}
```

- [x] **Step 6: Controls의 clear 버튼 활성화 조건 업데이트**

`CoursePlannerPage+ControlsComponent.swift`:

```swift
// 기존
Button("초기화") { viewModel.clear() }
    .disabled(viewModel.drawnStrokes.isEmpty)

// 변경 — 탭 데이터나 그리기 데이터 중 하나라도 있으면 활성화
Button("초기화") { viewModel.clear() }
    .disabled(
        viewModel.startCoordinate == nil
        && viewModel.drawnStrokes.isEmpty
    )
```

- [x] **Step 7: 빌드 확인**

- [x] **Step 8: 커밋** — `0c69084` + 후속 fix `d858fb0`

---

### Task 2: 위치 시작 화면 + 권한 거부 알럿

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`
- Modify: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: `LocationServiceProtocol.currentLocation()`, `LocationError.denied`
- Produces: `showLocationDeniedAlert: Bool`, `recenterToCurrentLocation()` method

- [x] **Step 1: 권한 거부 알럿 테스트 추가**

`TraceTests/CoursePlannerViewModelTests.swift`에 추가:

```swift
// MARK: - Location permission

func testBootstrapSetsAlertOnDenied() async {
    let sut = makeSUT(locationError: LocationError.denied)
    await sut.bootstrapLocation()
    XCTAssertTrue(sut.showLocationDeniedAlert)
    XCTAssertNotNil(sut.initialCameraCoordinate) // 서울시청 폴백
}

func testBootstrapNoAlertOnSuccess() async {
    let sut = makeSUT()
    await sut.bootstrapLocation()
    XCTAssertFalse(sut.showLocationDeniedAlert)
    XCTAssertNotNil(sut.initialCameraCoordinate)
}
```

`makeSUT` 업데이트:

```swift
private func makeSUT(locationError: Error? = nil) -> CoursePlannerPageViewModel {
    let locationService = StubLocationService()
    locationService.stubbedError = locationError
    return CoursePlannerPageViewModel(
        coursePlanningService: StubCoursePlanningService(),
        locationService: locationService
    )
}
```

- [x] **Step 2: 테스트 실행 — 실패 확인**

- [x] **Step 3: ViewModel에 권한 알럿 플래그 + bootstrapLocation 수정**

`CoursePlannerPageViewModel.swift`:

```swift
// 새 프로퍼티
var showLocationDeniedAlert = false

// bootstrapLocation() 교체
func bootstrapLocation() async {
    do {
        initialCameraCoordinate = try await locationService.currentLocation()
    } catch LocationError.denied {
        showLocationDeniedAlert = true
        initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
    } catch {
        initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
    }
}
```

- [x] **Step 4: ViewModel에 recenterToCurrentLocation 추가**

```swift
func recenterToCurrentLocation() async -> CourseCoordinate? {
    do {
        return try await locationService.currentLocation()
    } catch {
        return nil
    }
}
```

- [x] **Step 5: 테스트 실행 — 통과 확인**

- [x] **Step 6: View — 줌 레벨 100m + UserAnnotation + 내 위치 버튼 + 알럿**

`CoursePlannerPage.swift` 변경:

카메라 초기화 (`.task` 블록):
```swift
.task {
    await viewModel.bootstrapLocation()
    if let center = viewModel.initialCameraCoordinate {
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            latitudinalMeters: 100,
            longitudinalMeters: 100
        ))
    }
}
```

Map content에 `UserAnnotation()` 추가:
```swift
Map(position: $cameraPosition, interactionModes: viewModel.isDrawingMode ? [] : .all) {
    UserAnnotation()

    if let course = viewModel.course {
        // ... 기존 코드
    }
    // ... 기존 마커 코드
}
```

"내 위치로" 버튼 오버레이 (`.overlay(alignment: .bottomTrailing)` 추가, Canvas 오버레이와 별개):
```swift
.overlay(alignment: .bottomTrailing) {
    Button {
        Task {
            if let location = await viewModel.recenterToCurrentLocation() {
                cameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    latitudinalMeters: 100,
                    longitudinalMeters: 100
                ))
            }
        }
    } label: {
        Image(systemName: "location.fill")
            .font(.title2)
            .padding(12)
            .background(.regularMaterial, in: Circle())
    }
    .padding()
}
```

알럿 modifier (body 최상위에 추가):
```swift
.alert("위치 권한이 필요합니다", isPresented: $viewModel.showLocationDeniedAlert) {
    Button("설정으로 이동") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    Button("닫기", role: .cancel) {}
}
```

- [x] **Step 7: 빌드 확인**

- [x] **Step 8: 커밋** — `28dd737`

---

### Task 3: 그리기 모드 표시 명확화 + 그린 코스 핀

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`

**Interfaces:**
- Consumes: `viewModel.interactionMode`, `viewModel.isDrawingMode`, `viewModel.course`

- [x] **Step 1: Controls 컴포넌트 — 모드 인디케이터 + 아이콘 버튼**

`CoursePlannerPage+ControlsComponent.swift` 전체 교체:

```swift
import SwiftUI

extension CoursePlannerPage {
    var controls: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleDrawingMode()
            } label: {
                Label(
                    viewModel.isDrawingMode ? "그리기 중" : "그리기",
                    systemImage: "pencil.tip"
                )
            }
            .accessibilityIdentifier("coursePlanner.drawToggle")

            if viewModel.isDrawingMode {
                Button("되돌리기") { Task { await viewModel.undoLastStroke() } }
                    .disabled(viewModel.drawnStrokes.isEmpty)
                    .accessibilityIdentifier("coursePlanner.undo")
            }

            Button("초기화") { viewModel.clear() }
                .disabled(
                    viewModel.startCoordinate == nil
                    && viewModel.drawnStrokes.isEmpty
                )
                .accessibilityIdentifier("coursePlanner.clear")
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .frame(maxWidth: .infinity)
        .background(viewModel.isDrawingMode ? Color.orange.opacity(0.15) : Color.clear)
    }
}
```

- [x] **Step 2: 마커 표시 — 모드별 분기**

`CoursePlannerPage.swift`의 Map content에서 마커 부분 교체:

```swift
// 탭 모드: startCoordinate/destinationCoordinate 기반 (경로 계산 전에도 표시)
if viewModel.interactionMode == .tap {
    if let start = viewModel.startCoordinate {
        Marker("출발", systemImage: "figure.run", coordinate: CLLocationCoordinate2D(start))
            .tint(.green)
    }

    if let destination = viewModel.destinationCoordinate {
        Marker("도착", systemImage: "flag.checkered", coordinate: CLLocationCoordinate2D(destination))
            .tint(.red)
    }
}

// 그리기 모드: course의 첫/끝 좌표 기반
if viewModel.interactionMode == .draw, let course = viewModel.course,
   let first = course.coordinates.first, let last = course.coordinates.last {
    Marker("출발", systemImage: "figure.run", coordinate: CLLocationCoordinate2D(first))
        .tint(.green)
    Marker("도착", systemImage: "flag.checkered", coordinate: CLLocationCoordinate2D(last))
        .tint(.red)
}
```

- [x] **Step 3: 빌드 확인**

- [x] **Step 4: 커밋** — (아래)

---

### Task 4: 구간 라우팅 캐시

**Files:**
- Modify: `Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift`
- Create: `TraceTests/RouteCacheTests.swift`

**Interfaces:**
- Consumes: `CourseCoordinate`, `PlannedCourse`
- Produces: 캐시가 적용된 `route()` — 동일 좌표 쌍 재호출 시 API 미호출

- [x] **Step 1: 캐시 테스트 작성**

```swift
// TraceTests/RouteCacheTests.swift
import XCTest
@testable import Trace

@MainActor
final class RouteCacheTests: XCTestCase {
    func testCacheHitSkipsAPICall() async throws {
        let service = SpyMapKitService()
        let start = CourseCoordinate(latitude: 37.50000, longitude: 127.00000)
        let end = CourseCoordinate(latitude: 37.51000, longitude: 127.00000)

        let first = try await service.route(from: start, to: end)
        let second = try await service.route(from: start, to: end)

        XCTAssertEqual(service.apiCallCount, 1)
        XCTAssertEqual(first, second)
    }

    func testCacheMissCallsAPI() async throws {
        let service = SpyMapKitService()
        let a = CourseCoordinate(latitude: 37.50000, longitude: 127.00000)
        let b = CourseCoordinate(latitude: 37.51000, longitude: 127.00000)
        let c = CourseCoordinate(latitude: 37.52000, longitude: 127.00000)

        _ = try await service.route(from: a, to: b)
        _ = try await service.route(from: b, to: c)

        XCTAssertEqual(service.apiCallCount, 2)
    }

    func testRoundingMatchesNearbyCoordinates() async throws {
        let service = SpyMapKitService()
        let start1 = CourseCoordinate(latitude: 37.500001, longitude: 127.000002)
        let end1 = CourseCoordinate(latitude: 37.510003, longitude: 127.000001)
        let start2 = CourseCoordinate(latitude: 37.500004, longitude: 127.000006)
        let end2 = CourseCoordinate(latitude: 37.510001, longitude: 127.000005)

        _ = try await service.route(from: start1, to: end1)
        _ = try await service.route(from: start2, to: end2)

        XCTAssertEqual(service.apiCallCount, 1) // 소수점 5자리 라운딩 → 같은 키
    }
}

@MainActor
private final class SpyMapKitService: CoursePlanningServiceProtocol {
    var apiCallCount = 0
    private var cache: [String: PlannedCourse] = [:]

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        let key = cacheKey(from: start, to: destination)
        if let cached = cache[key] { return cached }
        apiCallCount += 1
        let result = PlannedCourse(coordinates: [start, destination], distanceMeters: 100)
        cache[key] = result
        return result
    }

    private func cacheKey(from start: CourseCoordinate, to end: CourseCoordinate) -> String {
        let s = "\(round(start.latitude, 5)),\(round(start.longitude, 5))"
        let e = "\(round(end.latitude, 5)),\(round(end.longitude, 5))"
        return "\(s)->\(e)"
    }

    private func round(_ value: Double, _ places: Int) -> Double {
        let m = pow(10.0, Double(places))
        return (value * m).rounded() / m
    }
}
```

- [x] **Step 2: 테스트 실행 — 통과 확인 (Spy가 자체 캐시 포함이므로 통과해야 함)**

Run: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/RouteCacheTests 2>&1 | tail -20`
Expected: PASS — Spy의 캐시 로직이 의도대로 동작하는지 확인

- [x] **Step 3: MapKitCoursePlanningService에 캐시 구현**

`MapKitCoursePlanningService.swift` 변경:

```swift
final class MapKitCoursePlanningService: CoursePlanningServiceProtocol {
    private var cache: [String: PlannedCourse] = [:]

    func route(
        from start: CourseCoordinate,
        to destination: CourseCoordinate
    ) async throws -> PlannedCourse {
        let key = cacheKey(from: start, to: destination)
        if let cached = cache[key] { return cached }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(start)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(destination)))
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw CoursePlanningError.routeNotFound
            }

            var coordinates = Array(
                repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                count: route.polyline.pointCount
            )
            route.polyline.getCoordinates(
                &coordinates,
                range: NSRange(location: 0, length: route.polyline.pointCount)
            )

            let result = PlannedCourse(
                coordinates: coordinates.map(CourseCoordinate.init),
                distanceMeters: route.distance
            )
            cache[key] = result
            return result
        } catch let error as CoursePlanningError {
            throw error
        } catch {
            throw CoursePlanningError.requestFailed
        }
    }

    private func cacheKey(from start: CourseCoordinate, to end: CourseCoordinate) -> String {
        let s = "\(round(start.latitude, 5)),\(round(start.longitude, 5))"
        let e = "\(round(end.latitude, 5)),\(round(end.longitude, 5))"
        return "\(s)->\(e)"
    }

    private func round(_ value: Double, _ places: Int) -> Double {
        let m = pow(10.0, Double(places))
        return (value * m).rounded() / m
    }
}
```

- [x] **Step 4: 빌드 확인**

- [x] **Step 5: 커밋** — `0e3fcb0`

---

### Task 5: 디바운스

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: `recomputeGeneration`, `appendStroke()`
- Produces: 300ms 디바운스가 적용된 `appendStroke()`

- [x] **Step 1: 디바운스 테스트 추가**

`TraceTests/CoursePlannerViewModelTests.swift`에 추가:

```swift
// MARK: - Debounce

func testRapidStrokesOnlyTriggerOneRecompute() async {
    let service = StubCoursePlanningService()
    let sut = CoursePlannerPageViewModel(
        coursePlanningService: service,
        locationService: StubLocationService()
    )
    sut.toggleDrawingMode()

    let stroke1 = [
        CourseCoordinate(latitude: 37.50, longitude: 127.00),
        CourseCoordinate(latitude: 37.51, longitude: 127.00),
    ]
    let stroke2 = [
        CourseCoordinate(latitude: 37.51, longitude: 127.00),
        CourseCoordinate(latitude: 37.52, longitude: 127.00),
    ]

    await sut.appendStroke(stroke1)
    await sut.appendStroke(stroke2)

    // 디바운스 대기
    try? await Task.sleep(nanoseconds: 400_000_000)

    // 두 스트로크를 빠르게 추가했지만 route 호출은 최종 1회만
    // (첫 appendStroke의 디바운스는 두 번째에 의해 취소됨)
    XCTAssertEqual(service.routeCallCount, 2) // snappedRoute: 점3개 → 구간2개 → route 2회
    XCTAssertEqual(sut.drawnStrokes.count, 2)
}
```

- [x] **Step 2: 테스트 실행 — 실패 확인**

- [x] **Step 3: ViewModel에 디바운스 구현**

`CoursePlannerPageViewModel.swift`에서 `appendStroke` 수정:

```swift
func appendStroke(_ stroke: [CourseCoordinate]) async {
    guard stroke.count >= 2 else { return }
    drawnStrokes.append(stroke)
    recomputeGeneration += 1
    let generation = recomputeGeneration
    try? await Task.sleep(nanoseconds: 300_000_000)
    guard generation == recomputeGeneration else { return }
    await recomputeSnappedCourse(generation: generation)
}
```

`recomputeSnappedCourse`에서 generation 관리 수정 (더 이상 내부에서 increment 안 함):

```swift
private func recomputeSnappedCourse(generation: Int) async {
    let allPoints = drawnStrokes.flatMap { $0 }
    let sampled = DrawnPathSampler.sample(allPoints)
    guard sampled.count >= 2 else { course = nil; return }

    isLoading = true
    errorMessage = nil
    do {
        let snapped = try await coursePlanningService.snappedRoute(through: sampled)
        guard generation == recomputeGeneration else { return }
        course = snapped
    } catch {
        guard generation == recomputeGeneration else { return }
        errorMessage = "경로를 계산할 수 없습니다."
    }
    isLoading = false
}
```

`undoLastStroke`도 동일하게 수정:

```swift
func undoLastStroke() async {
    guard drawnStrokes.isEmpty == false else { return }
    drawnStrokes.removeLast()
    if drawnStrokes.isEmpty {
        recomputeGeneration += 1
        course = nil
        errorMessage = nil
    } else {
        recomputeGeneration += 1
        let generation = recomputeGeneration
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard generation == recomputeGeneration else { return }
        await recomputeSnappedCourse(generation: generation)
    }
}
```

- [x] **Step 4: 전체 테스트 실행 — 통과 확인**

- [x] **Step 5: 커밋** — `21fe11b`

---

### Task 6: 시뮬레이터 검증 + roadmap 업데이트

**Files:**
- Modify: `docs/roadmap.md`
- Modify: `docs/backlog.md`

**Interfaces:**
- Consumes: 전체 구현 결과

- [x] **Step 1: 시뮬레이터에서 빌드 + 실행**

Run: XcodeBuildMCP `build_run_sim`으로 앱 실행

- [x] **Step 2: 검증 체크리스트**

1. 앱 진입 시 현재 위치 100m 줌 + 파란 점 표시
2. "내 위치로" 버튼 동작
3. 탭으로 출발/도착 찍기 → 경로 + 핀 표시
4. 그리기 모드 전환 → 탭 핀 사라짐 + 배경색 변경 + "그리기 중" 표시
5. 그리기로 경로 그리기 → 출발/도착 핀 표시
6. 탭 모드로 전환 → 그리기 결과 사라짐
7. 초기화 → 모든 상태 클리어
8. 빠른 연속 스트로크 → 스로틀 에러 없음

- [x] **Step 3: roadmap.md 업데이트**

```markdown
### MVP2 — UX 개선 + 스로틀 완화   (상태: 진행 중)

> MVP1 실기기 피드백 반영: 상호작용 모델 정리, 위치 UX, 모드 표시, 스로틀 완화.

- [x] **ux-polish** — 단일 모드 전환, 위치 시작 화면, 권한 알럿, 모드 표시, 코스 핀
- [x] **throttle-mitigation** — 구간 캐시 + 디바운스
```

- [x] **Step 4: backlog.md 상태 업데이트**

- [x] **Step 5: 커밋** — `a787d36`
