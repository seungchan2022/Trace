# MVP3 — UX 개선 + 스로틀 강화 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 카메라 점프 제거, 비연속 구간 그리기 개선, 그리기 중 지도 이동, 스로틀 증분 계산 + 에러 안내를 구현한다.

**Architecture:** 3개 마일스톤으로 나뉜다. camera-restore는 독립적. stroke-pipeline은 비연속 구간 방향 감지 + 증분 계산 + 되돌리기를 하나의 스트로크 파이프라인으로 통합 (같은 ViewModel 구조를 건드리므로 분리하면 throwaway 작업 발생). drawing-pan은 제스처 분리 spike 포함.

**Tech Stack:** Swift, SwiftUI, MapKit, XCTest, iOS 17+, `@Observable`

## Global Constraints

- iOS 17+ minimum deployment target
- Swift 6 concurrency: `async`/`await`, `@MainActor`
- `@Observable` (not `ObservableObject`)
- ViewModel은 MapKit을 import하지 않음
- 테스트 시뮬레이터는 iOS 26+ UDID 고정
- `xcodebuild test`에 `-parallel-testing-enabled NO` 필수

---

## 마일스톤 순서

| 순서 | 마일스톤 | 포함 항목 | Task |
|------|----------|-----------|------|
| 1 | `camera-restore` | 카메라 점프 제거 | 1–2 |
| 2 | `stroke-pipeline` | 비연속 구간 + 증분 계산 + 스로틀 에러 | 3–6 |
| 3 | ~~`drawing-pan`~~ | 보류 — SwiftUI Map 제스처 한계, MKMapView 교체 필요 | 7 |

---

### Task 1: CameraStateStore — UserDefaults 래퍼

**Files:**
- Create: `Trace/Infrastructure/Camera/CameraStateStore.swift`
- Create: `TraceTests/CameraStateStoreTests.swift`
- Modify: `Trace/App/DependencyContainer.swift`

**Interfaces:**
- Consumes: 없음
- Produces: `CameraStateStore` — `save(latitude:longitude:latitudinalMeters:longitudinalMeters:)`, `restore() -> CameraBounds?`, `CameraBounds` struct

- [x] **Step 1: Write the failing tests**

```swift
// TraceTests/CameraStateStoreTests.swift
import XCTest
@testable import Trace

final class CameraStateStoreTests: XCTestCase {
    private let suiteName = "CameraStateStoreTests"

    private func makeSUT() -> CameraStateStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return CameraStateStore(defaults: defaults)
    }

    func testRestoreReturnsNilWhenEmpty() {
        let sut = makeSUT()
        XCTAssertNil(sut.restore())
    }

    func testSaveAndRestoreRoundTrips() {
        let sut = makeSUT()
        sut.save(latitude: 37.5, longitude: 127.0, latitudinalMeters: 500, longitudinalMeters: 500)
        let bounds = sut.restore()
        XCTAssertEqual(bounds?.latitude, 37.5)
        XCTAssertEqual(bounds?.longitude, 127.0)
        XCTAssertEqual(bounds?.latitudinalMeters, 500)
        XCTAssertEqual(bounds?.longitudinalMeters, 500)
    }

    func testSaveOverwritesPreviousValue() {
        let sut = makeSUT()
        sut.save(latitude: 37.5, longitude: 127.0, latitudinalMeters: 500, longitudinalMeters: 500)
        sut.save(latitude: 35.0, longitude: 129.0, latitudinalMeters: 1000, longitudinalMeters: 1000)
        let bounds = sut.restore()
        XCTAssertEqual(bounds?.latitude, 35.0)
        XCTAssertEqual(bounds?.longitude, 129.0)
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: Compile error — `CameraStateStore` not found

- [x] **Step 3: Implement CameraStateStore**

```swift
// Trace/Infrastructure/Camera/CameraStateStore.swift
import Foundation

struct CameraBounds: Equatable {
    let latitude: Double
    let longitude: Double
    let latitudinalMeters: Double
    let longitudinalMeters: Double
}

final class CameraStateStore {
    private let defaults: UserDefaults
    private enum Key {
        static let latitude = "cameraState.latitude"
        static let longitude = "cameraState.longitude"
        static let latSpan = "cameraState.latSpan"
        static let lonSpan = "cameraState.lonSpan"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(latitude: Double, longitude: Double, latitudinalMeters: Double, longitudinalMeters: Double) {
        defaults.set(latitude, forKey: Key.latitude)
        defaults.set(longitude, forKey: Key.longitude)
        defaults.set(latSpan, forKey: Key.latSpan)
        defaults.set(lonSpan, forKey: Key.lonSpan)
    }

    func restore() -> CameraBounds? {
        guard defaults.object(forKey: Key.latitude) != nil else { return nil }
        return CameraBounds(
            latitude: defaults.double(forKey: Key.latitude),
            longitude: defaults.double(forKey: Key.longitude),
            latitudinalMeters: defaults.double(forKey: Key.latSpan),
            longitudinalMeters: defaults.double(forKey: Key.lonSpan)
        )
    }
}
```

주의: `save` 메서드 내 `forKey` 값을 올바른 상수로 수정:
```swift
    func save(latitude: Double, longitude: Double, latitudinalMeters: Double, longitudinalMeters: Double) {
        defaults.set(latitude, forKey: Key.latitude)
        defaults.set(longitude, forKey: Key.longitude)
        defaults.set(latitudinalMeters, forKey: Key.latSpan)
        defaults.set(longitudinalMeters, forKey: Key.lonSpan)
    }
```

- [x] **Step 4: Register in DependencyContainer**

`Trace/App/DependencyContainer.swift` 수정:

```swift
struct DependencyContainer {
    let coursePlanningService: CoursePlanningServiceProtocol
    let locationService: LocationServiceProtocol
    let cameraStateStore: CameraStateStore

    @MainActor
    static func live() -> DependencyContainer {
        DependencyContainer(
            coursePlanningService: MapKitCoursePlanningService(),
            locationService: CoreLocationService(),
            cameraStateStore: CameraStateStore()
        )
    }

    @MainActor
    static func uiTesting() -> DependencyContainer {
        DependencyContainer(
            coursePlanningService: UITestingCoursePlanningService(),
            locationService: UITestingLocationService(),
            cameraStateStore: CameraStateStore(defaults: UserDefaults(suiteName: "uiTesting")!)
        )
    }
}
```

- [x] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: All tests PASS

- [x] **Step 6: Commit**

```bash
git add Trace/Infrastructure/Camera/CameraStateStore.swift TraceTests/CameraStateStoreTests.swift Trace/App/DependencyContainer.swift
git commit -m "feat: add CameraStateStore for persisting camera position"
```

---

### Task 2: CoursePlannerPage 카메라 복원 통합

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `Trace/App/TraceApp.swift`
- Modify: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: `CameraStateStore` (Task 1), `CameraBounds`
- Produces: 변경된 `CoursePlannerPage` init — `cameraStateStore` 파라미터 추가

- [x] **Step 1: Write the failing test — bootstrapLocation이 저장된 값이 있으면 initialCameraCoordinate를 세팅하지 않음**

`TraceTests/CoursePlannerViewModelTests.swift`에 추가:

```swift
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

    // bootstrapLocation은 호출되지만, 저장된 카메라가 있으므로
    // initialCameraCoordinate는 세팅되지 않음 (Page에서 이미 복원했으므로)
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

    // 저장된 카메라 없으면 현재 위치로 세팅
    XCTAssertNotNil(sut.initialCameraCoordinate)
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: Compile error — `CoursePlannerPageViewModel` init에 `cameraStateStore` 파라미터 없음

- [x] **Step 3: Modify ViewModel — cameraStateStore 주입 + bootstrapLocation 분기**

`Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift` 수정:

```swift
@MainActor
@Observable
final class CoursePlannerPageViewModel {
    // ... 기존 프로퍼티 유지 ...
    private let cameraStateStore: CameraStateStore

    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol,
        cameraStateStore: CameraStateStore = CameraStateStore()
    ) {
        self.coursePlanningService = coursePlanningService
        self.locationService = locationService
        self.cameraStateStore = cameraStateStore
    }

    func bootstrapLocation() async {
        // 저장된 카메라가 있으면 Page에서 이미 복원했으므로 위치 요청만 하고 카메라는 건드리지 않음
        let hasRestoredCamera = cameraStateStore.restore() != nil

        do {
            let location = try await locationService.currentLocation()
            if !hasRestoredCamera {
                initialCameraCoordinate = location
            }
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

    // ... 나머지 메서드 변경 없음 ...
}
```

- [x] **Step 4: Modify CoursePlannerPage — 카메라 복원 + scenePhase 저장**

`Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` 수정:

```swift
struct CoursePlannerPage: View {
    @State var viewModel: CoursePlannerPageViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentStroke: [CourseCoordinate] = []
    @State private var currentStrokePoints: [CGPoint] = []
    @Environment(\.scenePhase) private var scenePhase

    private let cameraStateStore: CameraStateStore

    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol,
        cameraStateStore: CameraStateStore = CameraStateStore()
    ) {
        self.cameraStateStore = cameraStateStore
        _viewModel = State(initialValue: CoursePlannerPageViewModel(
            coursePlanningService: coursePlanningService,
            locationService: locationService,
            cameraStateStore: cameraStateStore
        ))
    }

    var body: some View {
        mapView
            .accessibilityIdentifier("coursePlanner.map")
            .safeAreaInset(edge: .top) {
                controls
            }
            .safeAreaInset(edge: .bottom) {
                statusPanel
            }
            .task {
                // 저장된 카메라 복원 (즉시, 점프 없음)
                if let bounds = cameraStateStore.restore() {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: bounds.latitude, longitude: bounds.longitude),
                        latitudinalMeters: bounds.latitudinalMeters,
                        longitudinalMeters: bounds.longitudinalMeters
                    ))
                }

                await viewModel.bootstrapLocation()

                // 저장된 카메라가 없었던 경우(첫 실행)에만 위치로 이동
                if let center = viewModel.initialCameraCoordinate {
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                            latitudinalMeters: 500,
                            longitudinalMeters: 500
                        ))
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    saveCameraPosition()
                }
            }
            .alert("위치 권한이 필요합니다", isPresented: $viewModel.showLocationDeniedAlert) {
                Button("설정으로 이동") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("닫기", role: .cancel) {}
            }
    }

    private func saveCameraPosition() {
        // MapCameraPosition에서 region 추출은 바인딩 기반으로 직접 접근 불가
        // onMapCameraChange로 마지막 영역을 캐싱하는 방식 사용
        // → Step 5에서 onMapCameraChange 추가
    }

    // ... mapView, statusPanel 등 기존 코드 유지 ...
}
```

- [x] **Step 5: onMapCameraChange로 마지막 카메라 영역 캐싱 + background 저장**

`CoursePlannerPage`에 `@State private var lastCameraRegion: MKCoordinateRegion?` 추가하고, `mapView`의 `Map`에 modifier 추가:

```swift
@State private var lastCameraRegion: MKCoordinateRegion?

// Map(...) 뒤에 추가:
.onMapCameraChange(frequency: .onEnd) { context in
    lastCameraRegion = context.region
}
```

`saveCameraPosition()`을 실제 구현으로 교체:

```swift
private func saveCameraPosition() {
    guard let region = lastCameraRegion else { return }
    cameraStateStore.save(
        latitude: region.center.latitude,
        longitude: region.center.longitude,
        latitudinalMeters: region.span.latitudeDelta * 111_000,
        longitudinalMeters: region.span.longitudeDelta * 111_000 * cos(region.center.latitude * .pi / 180)
    )
}
```

- [x] **Step 6: Modify TraceApp — cameraStateStore 전달**

`Trace/App/TraceApp.swift` 수정:

```swift
var body: some Scene {
    WindowGroup {
        CoursePlannerPage(
            coursePlanningService: container.coursePlanningService,
            locationService: container.locationService,
            cameraStateStore: container.cameraStateStore
        )
    }
}
```

- [x] **Step 7: Fix existing tests — StubCoursePlanningService와 StubLocationService가 test double로 쓰이는 기존 테스트에서 makeSUT 업데이트**

기존 `makeSUT`에 cameraStateStore 파라미터 추가 (빈 UserDefaults 사용):

```swift
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
```

- [x] **Step 8: Run all tests**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: All tests PASS

- [x] **Step 9: Commit**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift Trace/App/TraceApp.swift TraceTests/CoursePlannerViewModelTests.swift
git commit -m "feat: restore camera position on launch, save on background"
```

---

### Task 3: StrokeEntry 데이터 모델 + 방향 감지 로직

**Files:**
- Create: `Trace/Domain/CoursePlanning/StrokeEntry.swift`
- Create: `Trace/Domain/CoursePlanning/StrokeDirectionResolver.swift`
- Create: `TraceTests/StrokeDirectionResolverTests.swift`

**Interfaces:**
- Consumes: `CourseCoordinate`, `CourseCoordinate.distanceMeters(to:)`
- Produces: `StrokeEntry` struct, `StrokeDirectionResolver.resolve(newStroke:existingCourseStart:existingCourseEnd:) -> StrokeAttachment`

- [x] **Step 1: Write the failing tests**

```swift
// TraceTests/StrokeDirectionResolverTests.swift
import XCTest
@testable import Trace

final class StrokeDirectionResolverTests: XCTestCase {
    // 기존 경로: A(37.50, 127.00) → B(37.52, 127.00)
    let courseStart = CourseCoordinate(latitude: 37.50, longitude: 127.00)
    let courseEnd = CourseCoordinate(latitude: 37.52, longitude: 127.00)

    func testStrokeNearEndAppendsForward() {
        // 새 스트로크: 끝점(B) 근처에서 시작 → 더 멀리
        let stroke = [
            CourseCoordinate(latitude: 37.521, longitude: 127.00),
            CourseCoordinate(latitude: 37.53, longitude: 127.00),
        ]
        let result = StrokeDirectionResolver.resolve(
            newStroke: stroke,
            existingCourseStart: courseStart,
            existingCourseEnd: courseEnd
        )
        XCTAssertEqual(result.direction, .append)
        XCTAssertEqual(result.orientedStroke.first, stroke.first)
    }

    func testStrokeNearStartPrependsForward() {
        // 새 스트로크: 시작점(A) 근처에서 끝남 → 더 멀리에서 시작
        let stroke = [
            CourseCoordinate(latitude: 37.48, longitude: 127.00),
            CourseCoordinate(latitude: 37.499, longitude: 127.00),
        ]
        let result = StrokeDirectionResolver.resolve(
            newStroke: stroke,
            existingCourseStart: courseStart,
            existingCourseEnd: courseEnd
        )
        XCTAssertEqual(result.direction, .prepend)
        // 스트로크 끝이 A에 가까우므로, 역순으로 뒤집혀서
        // orientedStroke의 끝이 A에 가까워야 한다
        let lastOfOriented = result.orientedStroke.last!
        let firstOfOriented = result.orientedStroke.first!
        XCTAssertTrue(lastOfOriented.distanceMeters(to: courseStart) < firstOfOriented.distanceMeters(to: courseStart))
    }

    func testStrokeNearEndButReversedGetsFlipped() {
        // 새 스트로크: B 근처에서 끝남 (시작은 멀리) → append이지만 reverse 필요
        let stroke = [
            CourseCoordinate(latitude: 37.53, longitude: 127.00),
            CourseCoordinate(latitude: 37.521, longitude: 127.00),
        ]
        let result = StrokeDirectionResolver.resolve(
            newStroke: stroke,
            existingCourseStart: courseStart,
            existingCourseEnd: courseEnd
        )
        XCTAssertEqual(result.direction, .append)
        // orientedStroke의 시작이 B에 가까워야 함
        let first = result.orientedStroke.first!
        XCTAssertTrue(first.distanceMeters(to: courseEnd) < 200)
    }

    func testFirstStrokeReturnsInitial() {
        let stroke = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ]
        let result = StrokeDirectionResolver.resolve(
            newStroke: stroke,
            existingCourseStart: nil,
            existingCourseEnd: nil
        )
        XCTAssertEqual(result.direction, .initial)
        XCTAssertEqual(result.orientedStroke, stroke)
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: Compile error — `StrokeDirectionResolver` not found

- [x] **Step 3: Implement StrokeEntry and StrokeDirectionResolver**

```swift
// Trace/Domain/CoursePlanning/StrokeEntry.swift
import Foundation

enum StrokeDirection: Equatable {
    case initial
    case append
    case prepend
}

struct StrokeEntry: Equatable {
    let orientedStroke: [CourseCoordinate]
    let direction: StrokeDirection
    var routedCoordinateCount: Int = 0
    var routedDistance: Double = 0
}
```

```swift
// Trace/Domain/CoursePlanning/StrokeDirectionResolver.swift
import Foundation

struct StrokeAttachment: Equatable {
    let direction: StrokeDirection
    let orientedStroke: [CourseCoordinate]
}

enum StrokeDirectionResolver {
    static func resolve(
        newStroke: [CourseCoordinate],
        existingCourseStart: CourseCoordinate?,
        existingCourseEnd: CourseCoordinate?
    ) -> StrokeAttachment {
        guard let courseStart = existingCourseStart, let courseEnd = existingCourseEnd else {
            return StrokeAttachment(direction: .initial, orientedStroke: newStroke)
        }
        guard let strokeStart = newStroke.first, let strokeEnd = newStroke.last else {
            return StrokeAttachment(direction: .initial, orientedStroke: newStroke)
        }

        // 4쌍 거리 비교
        let pairs: [(distance: Double, direction: StrokeDirection, needsReverse: Bool)] = [
            (strokeStart.distanceMeters(to: courseEnd), .append, false),   // stroke시작 → 경로끝: append, 그대로
            (strokeEnd.distanceMeters(to: courseEnd), .append, true),      // stroke끝 → 경로끝: append, 뒤집기
            (strokeEnd.distanceMeters(to: courseStart), .prepend, false),  // stroke끝 → 경로시작: prepend, 그대로
            (strokeStart.distanceMeters(to: courseStart), .prepend, true), // stroke시작 → 경로시작: prepend, 뒤집기
        ]

        let closest = pairs.min(by: { $0.distance < $1.distance })!
        let oriented = closest.needsReverse ? newStroke.reversed() : newStroke
        return StrokeAttachment(direction: closest.direction, orientedStroke: Array(oriented))
    }
}
```

- [x] **Step 4: Run tests**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: All tests PASS

- [x] **Step 5: Commit**

```bash
git add Trace/Domain/CoursePlanning/StrokeEntry.swift Trace/Domain/CoursePlanning/StrokeDirectionResolver.swift TraceTests/StrokeDirectionResolverTests.swift
git commit -m "feat: add StrokeEntry model and direction resolver for bidirectional stroke attachment"
```

---

### Task 4: CoursePlanningError.throttled + MapKit 감지

**Files:**
- Modify: `Trace/Domain/CoursePlanning/CoursePlanningError.swift`
- Modify: `Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift`
- Modify: `Trace/Domain/CoursePlanning/Protocol/CoursePlanningServiceProtocol.swift`
- Create: `TraceTests/ThrottleDetectionTests.swift`

**Interfaces:**
- Consumes: `CoursePlanningError`
- Produces: `.throttled` 케이스, `routeWithRetry`가 `.throttled`를 bypass

- [x] **Step 1: Write the failing test**

```swift
// TraceTests/ThrottleDetectionTests.swift
import XCTest
@testable import Trace

@MainActor
final class ThrottleDetectionTests: XCTestCase {
    func testThrottleErrorIsDistinctFromRequestFailed() {
        let throttled = CoursePlanningError.throttled
        let failed = CoursePlanningError.requestFailed
        XCTAssertNotEqual(throttled, failed)
    }

    func testRouteWithRetryDoesNotRetryOnThrottle() async {
        let service = ThrottleStubService()
        // snappedRoute가 routeWithRetry를 사용하므로 간접 테스트
        do {
            _ = try await service.snappedRoute(through: [
                CourseCoordinate(latitude: 37.50, longitude: 127.00),
                CourseCoordinate(latitude: 37.51, longitude: 127.00),
            ])
            XCTFail("Should have thrown")
        } catch CoursePlanningError.throttled {
            // routeWithRetry가 retry하지 않으므로 1번만 호출
            XCTAssertEqual(service.routeCallCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

@MainActor
private final class ThrottleStubService: CoursePlanningServiceProtocol {
    var routeCallCount = 0

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        routeCallCount += 1
        throw CoursePlanningError.throttled
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Expected: Compile error — `.throttled` not found

- [x] **Step 3: Add .throttled case + update routeWithRetry + MapKit detection**

`Trace/Domain/CoursePlanning/CoursePlanningError.swift`:
```swift
enum CoursePlanningError: Error, Equatable {
    case routeNotFound
    case requestFailed
    case throttled
}
```

`Trace/Domain/CoursePlanning/Protocol/CoursePlanningServiceProtocol.swift` — `routeWithRetry` 수정:
```swift
    private func routeWithRetry(
        from start: CourseCoordinate,
        to destination: CourseCoordinate,
        attempts: Int = 2
    ) async throws -> PlannedCourse {
        var lastError: Error = CoursePlanningError.requestFailed
        for attempt in 0..<attempts {
            do {
                return try await route(from: start, to: destination)
            } catch CoursePlanningError.throttled {
                throw CoursePlanningError.throttled
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
        throw lastError
    }
```

`Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift` — catch 블록 수정:
```swift
        } catch let error as CoursePlanningError {
            throw error
        } catch {
            let nsError = error as NSError
            if nsError.domain == "GEOErrorDomain", nsError.code == -3 {
                throw CoursePlanningError.throttled
            }
            throw CoursePlanningError.requestFailed
        }
```

- [x] **Step 4: Run tests**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: All tests PASS

- [x] **Step 5: Commit**

```bash
git add Trace/Domain/CoursePlanning/CoursePlanningError.swift Trace/Domain/CoursePlanning/Protocol/CoursePlanningServiceProtocol.swift Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift TraceTests/ThrottleDetectionTests.swift
git commit -m "feat: detect MKDirections throttle and bypass retry"
```

---

### Task 5: ViewModel 스트로크 파이프라인 리팩터 — 증분 계산 + 방향 감지 + 되돌리기

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `Trace/Domain/CoursePlanning/DrawnPathSampler.swift`
- Modify: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: `StrokeEntry`, `StrokeDirectionResolver`, `CoursePlanningError.throttled`, `DrawnPathSampler.sample(_:)`
- Produces: 변경된 `appendStroke`, `undoLastStroke`, `clear`, 새로운 `strokeEntries` 프로퍼티

- [x] **Step 1: Write the failing tests — 증분 계산 + 방향 감지**

`TraceTests/CoursePlannerViewModelTests.swift`에 추가:

```swift
// MARK: - Incremental stroke pipeline

func testAppendStrokeNearEndAppendsAndRoutesOnlyNewSegment() async {
    let service = StubCoursePlanningService()
    let sut = CoursePlannerPageViewModel(
        coursePlanningService: service,
        locationService: StubLocationService()
    )
    sut.toggleDrawingMode()

    // 첫 스트로크
    await sut.appendStroke([
        CourseCoordinate(latitude: 37.500, longitude: 127.00),
        CourseCoordinate(latitude: 37.510, longitude: 127.00),
    ])
    try? await Task.sleep(nanoseconds: 400_000_000)
    let callsAfterFirst = service.routeCallCount

    // 끝점 근처에서 두 번째 스트로크
    service.routeCallCount = 0
    await sut.appendStroke([
        CourseCoordinate(latitude: 37.511, longitude: 127.00),
        CourseCoordinate(latitude: 37.520, longitude: 127.00),
    ])
    try? await Task.sleep(nanoseconds: 400_000_000)

    // 이전 구간은 재호출하지 않음 — 새 스트로크 내부 구간 + 연결 1건만
    XCTAssertTrue(service.routeCallCount < callsAfterFirst + 3)
    XCTAssertNotNil(sut.course)
}

func testAppendStrokeNearStartPrepends() async {
    let service = StubCoursePlanningService()
    let sut = CoursePlannerPageViewModel(
        coursePlanningService: service,
        locationService: StubLocationService()
    )
    sut.toggleDrawingMode()

    // 첫 스트로크: 37.510 → 37.520
    await sut.appendStroke([
        CourseCoordinate(latitude: 37.510, longitude: 127.00),
        CourseCoordinate(latitude: 37.520, longitude: 127.00),
    ])
    try? await Task.sleep(nanoseconds: 400_000_000)

    // 시작점 근처에서 두 번째 스트로크: 37.500 → 37.509
    await sut.appendStroke([
        CourseCoordinate(latitude: 37.500, longitude: 127.00),
        CourseCoordinate(latitude: 37.509, longitude: 127.00),
    ])
    try? await Task.sleep(nanoseconds: 400_000_000)

    XCTAssertNotNil(sut.course)
    // 코스의 시작이 37.500 근처여야 함 (prepend됨)
    if let first = sut.course?.coordinates.first {
        XCTAssertTrue(abs(first.latitude - 37.500) < 0.005)
    }
}

func testUndoRemovesLastAddedStroke() async {
    let sut = CoursePlannerPageViewModel(
        coursePlanningService: StubCoursePlanningService(),
        locationService: StubLocationService()
    )
    sut.toggleDrawingMode()

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
    XCTAssertNotNil(sut.course)

    await sut.undoLastStroke()

    // 첫 스트로크만 남아있어야 함
    XCTAssertEqual(sut.drawnStrokes.count, 1)
    XCTAssertNotNil(sut.course)
}

func testThrottleErrorShowsUserMessage() async {
    let service = StubCoursePlanningService()
    service.stubbedError = CoursePlanningError.throttled
    let sut = CoursePlannerPageViewModel(
        coursePlanningService: service,
        locationService: StubLocationService()
    )
    sut.toggleDrawingMode()

    await sut.appendStroke([
        CourseCoordinate(latitude: 37.500, longitude: 127.00),
        CourseCoordinate(latitude: 37.510, longitude: 127.00),
    ])
    try? await Task.sleep(nanoseconds: 400_000_000)

    XCTAssertEqual(sut.errorMessage, "요청이 많아 잠시 후 다시 시도해주세요")
}
```

- [x] **Step 2: Run tests to verify they fail**

Expected: 기존 테스트는 통과하지만 새 테스트는 실패 (증분 계산 미구현)

- [x] **Step 3: Implement — ViewModel 스트로크 파이프라인 리팩터**

`CoursePlannerPageViewModel.swift` 전체 그리기 관련 로직을 교체:

```swift
// 새 프로퍼티 추가
private(set) var strokeEntries: [StrokeEntry] = []
private var accumulatedCoordinates: [CourseCoordinate] = []
private var accumulatedDistance: Double = 0

// appendStroke 교체
func appendStroke(_ stroke: [CourseCoordinate]) async {
    guard stroke.count >= 2 else { return }
    drawnStrokes.append(stroke)
    recomputeGeneration += 1
    let generation = recomputeGeneration
    try? await Task.sleep(nanoseconds: 300_000_000)
    guard generation == recomputeGeneration else { return }
    await incrementalRoute(rawStroke: stroke, generation: generation)
}

private func incrementalRoute(rawStroke: [CourseCoordinate], generation: Int) async {
    let sampled = DrawnPathSampler.sample(rawStroke)
    guard sampled.count >= 2 else { return }

    let attachment = StrokeDirectionResolver.resolve(
        newStroke: sampled,
        existingCourseStart: accumulatedCoordinates.first,
        existingCourseEnd: accumulatedCoordinates.last
    )
    let oriented = attachment.orientedStroke

    isLoading = true
    errorMessage = nil

    do {
        // 1) 새 스트로크 내부 구간 라우팅
        var newCoords: [CourseCoordinate] = []
        var newDistance = 0.0
        for i in 0..<(oriented.count - 1) {
            let leg = try await coursePlanningService.route(from: oriented[i], to: oriented[i + 1])
            guard generation == recomputeGeneration else { return }
            newCoords.append(contentsOf: newCoords.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst()))
            newDistance += leg.distanceMeters
        }

        // 2) 기존 경로와 연결 구간
        switch attachment.direction {
        case .initial:
            accumulatedCoordinates = newCoords
            accumulatedDistance = newDistance
        case .append:
            if let existingEnd = accumulatedCoordinates.last, let newStart = newCoords.first {
                let connection = try await coursePlanningService.route(from: existingEnd, to: newStart)
                guard generation == recomputeGeneration else { return }
                accumulatedCoordinates.append(contentsOf: Array(connection.coordinates.dropFirst()))
                accumulatedDistance += connection.distanceMeters
            }
            accumulatedCoordinates.append(contentsOf: Array(newCoords.dropFirst()))
            accumulatedDistance += newDistance
        case .prepend:
            if let existingStart = accumulatedCoordinates.first, let newEnd = newCoords.last {
                let connection = try await coursePlanningService.route(from: newEnd, to: existingStart)
                guard generation == recomputeGeneration else { return }
                var merged = newCoords
                merged.append(contentsOf: Array(connection.coordinates.dropFirst()))
                merged.append(contentsOf: Array(accumulatedCoordinates.dropFirst()))
                accumulatedDistance += connection.distanceMeters + newDistance
                accumulatedCoordinates = merged
            }
        }

        var entry = StrokeEntry(
            orientedStroke: oriented,
            direction: attachment.direction,
            routedCoordinateCount: newCoords.count,
            routedDistance: newDistance
        )
        strokeEntries.append(entry)

        course = PlannedCourse(coordinates: accumulatedCoordinates, distanceMeters: accumulatedDistance)
    } catch CoursePlanningError.throttled {
        guard generation == recomputeGeneration else { return }
        errorMessage = "요청이 많아 잠시 후 다시 시도해주세요"
        // 스트로크는 추가했지만 라우팅 실패 — drawnStrokes에서도 제거
        drawnStrokes.removeLast()
    } catch {
        guard generation == recomputeGeneration else { return }
        errorMessage = "경로를 계산할 수 없습니다."
    }
    isLoading = false
}

// undoLastStroke 교체
func undoLastStroke() async {
    guard let lastEntry = strokeEntries.popLast() else { return }
    drawnStrokes.removeLast()
    recomputeGeneration += 1

    if strokeEntries.isEmpty {
        accumulatedCoordinates = []
        accumulatedDistance = 0
        course = nil
        errorMessage = nil
    } else {
        // 전체 재계산 대신 마지막 entry의 좌표/거리를 잘라냄
        // 연결 구간까지 정확히 빼기 어려우므로 전체 재구축
        // (undo는 드물어 성능 영향 미미)
        recomputeGeneration += 1
        let generation = recomputeGeneration
        let savedStrokes = drawnStrokes
        strokeEntries = []
        accumulatedCoordinates = []
        accumulatedDistance = 0
        course = nil
        errorMessage = nil

        for stroke in savedStrokes {
            await incrementalRoute(rawStroke: stroke, generation: generation)
            guard generation == recomputeGeneration else { return }
        }
    }
}

// clear 교체
func clear() {
    recomputeGeneration += 1
    startCoordinate = nil
    destinationCoordinate = nil
    drawnStrokes = []
    strokeEntries = []
    accumulatedCoordinates = []
    accumulatedDistance = 0
    course = nil
    errorMessage = nil
    isLoading = false
}

// toggleDrawingMode 교체 — draw→tap 시 stroke pipeline 상태도 초기화
func toggleDrawingMode() {
    switch interactionMode {
    case .tap:
        recomputeGeneration += 1
        startCoordinate = nil
        destinationCoordinate = nil
        course = nil
        errorMessage = nil
        isLoading = false
        interactionMode = .draw
    case .draw:
        recomputeGeneration += 1
        drawnStrokes = []
        strokeEntries = []
        accumulatedCoordinates = []
        accumulatedDistance = 0
        course = nil
        errorMessage = nil
        interactionMode = .tap
    }
}
```

기존 `recomputeSnappedCourse` 메서드는 삭제한다.

- [x] **Step 4: Run all tests**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: All tests PASS

- [x] **Step 5: Commit**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift Trace/Domain/CoursePlanning/DrawnPathSampler.swift TraceTests/CoursePlannerViewModelTests.swift
git commit -m "feat: incremental stroke pipeline with direction detection, throttle message, and undo"
```

---

### Task 6: ViewModel 스로틀 에러 메시지 표시 통합 확인

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (statusPanel)

**Interfaces:**
- Consumes: `viewModel.errorMessage` (이미 Task 5에서 throttle 메시지 세팅됨)
- Produces: 없음 (기존 UI가 `errorMessage`를 표시하므로 별도 수정 불필요할 수 있음)

- [x] **Step 1: 확인 — statusPanel이 이미 errorMessage를 표시하는지 검증**

현재 `statusPanel`의 코드:
```swift
} else if let errorMessage = viewModel.errorMessage {
    Text(errorMessage)
        .foregroundStyle(.red)
```

스로틀 메시지("요청이 많아 잠시 후 다시 시도해주세요")는 `errorMessage`에 세팅되므로 **기존 UI로 이미 표시된다.** 스로틀과 일반 에러를 시각적으로 구분하고 싶다면 색상을 다르게 할 수 있지만, MVP3에서는 동일한 빨간색 텍스트로 충분하다.

- [x] **Step 2: 빌드 + 테스트 전체 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: All tests PASS

- [x] **Step 3: Commit (변경이 있을 경우만)**

변경 없으면 skip.

---

### Task 7: ~~그리기 중 2손가락 지도 이동~~ (보류 — MKMapView 교체 필요)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`

**Interfaces:**
- Consumes: 기존 `CoursePlannerPage.mapView`
- Produces: 1손가락 그리기 + 2손가락 패닝/줌 동시 지원

- [x] **Step 1: Spike — interactionModes 변경으로 동작하는지 확인**

`CoursePlannerPage.swift`의 `Map` 생성자에서:

현재:
```swift
Map(position: $cameraPosition, interactionModes: viewModel.isDrawingMode ? [] : .all)
```

변경:
```swift
Map(position: $cameraPosition, interactionModes: viewModel.isDrawingMode ? [.pan, .zoom] : .all)
```

시뮬레이터에서 빌드 후 그리기 모드 진입 → 1손가락 드래그가 Canvas에서 소비되고, 2손가락(Option+Drag in Simulator)으로 지도가 이동하는지 확인.

- [x] **Step 2: 제스처 충돌 해결 — 필요 시 DragGesture에 터치 수 제한**

Canvas 오버레이의 `DragGesture`가 모든 터치를 소비하면 2손가락이 Map으로 전달되지 않는다. 이 경우 UIKit `UIGestureRecognizer`를 SwiftUI에 브릿징해야 한다:

Canvas 대신 UIViewRepresentable로 그리기 뷰를 만들고, `UIPanGestureRecognizer`에 `maximumNumberOfTouches = 1`을 설정하여 1손가락만 소비:

```swift
// Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+DrawingOverlay.swift
import SwiftUI
import UIKit

struct DrawingOverlay: UIViewRepresentable {
    let isActive: Bool
    let onStrokePoint: (CGPoint) -> Void
    let onStrokeEnd: () -> Void

    func makeUIView(context: Context) -> DrawingUIView {
        let view = DrawingUIView()
        view.backgroundColor = .clear
        view.onStrokePoint = onStrokePoint
        view.onStrokeEnd = onStrokeEnd
        return view
    }

    func updateUIView(_ uiView: DrawingUIView, context: Context) {
        uiView.isDrawingActive = isActive
        uiView.onStrokePoint = onStrokePoint
        uiView.onStrokeEnd = onStrokeEnd
    }
}

final class DrawingUIView: UIView {
    var isDrawingActive = false
    var onStrokePoint: ((CGPoint) -> Void)?
    var onStrokeEnd: (() -> Void)?
    private var currentPath: [CGPoint] = []
    private var shapeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        shapeLayer.strokeColor = UIColor.orange.cgColor
        shapeLayer.fillColor = nil
        shapeLayer.lineWidth = 4
        layer.addSublayer(shapeLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isDrawingActive else { return }
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began, .changed:
            currentPath.append(point)
            onStrokePoint?(point)
            redrawPath()
        case .ended, .cancelled:
            onStrokeEnd?()
            currentPath = []
            redrawPath()
        default: break
        }
    }

    private func redrawPath() {
        let bezier = UIBezierPath()
        guard let first = currentPath.first else {
            shapeLayer.path = nil
            return
        }
        bezier.move(to: first)
        for point in currentPath.dropFirst() {
            bezier.addLine(to: point)
        }
        shapeLayer.path = bezier.cgPath
    }
}
```

이 방식은 SwiftUI DragGesture의 Canvas 기반 접근이 2손가락을 통과시키지 못할 때의 대안이다. spike 결과에 따라 선택:
- Canvas DragGesture가 2손가락을 통과시키면 → `interactionModes` 변경만으로 충분
- 통과시키지 못하면 → `DrawingOverlay` UIViewRepresentable 사용

- [x] **Step 3: CoursePlannerPage에서 Canvas 교체 (필요 시)**

spike 결과에 따라 Canvas 오버레이를 `DrawingOverlay`로 교체하고, `MapReader.proxy`를 통한 좌표 변환을 `DrawingOverlay`의 콜백에서 처리:

```swift
.overlay {
    DrawingOverlay(
        isActive: viewModel.isDrawingMode,
        onStrokePoint: { point in
            if let coord = proxy.convert(point, from: .local) {
                currentStroke.append(CourseCoordinate(coord))
            }
            currentStrokePoints.append(point)
        },
        onStrokeEnd: {
            let stroke = currentStroke
            currentStroke = []
            currentStrokePoints = []
            Task { await viewModel.appendStroke(stroke) }
        }
    )
}
```

- [x] **Step 4: 빌드 + 시뮬레이터 테스트**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build 2>&1 | tail -10`

시뮬레이터에서 확인:
1. 그리기 모드 진입
2. 1손가락 드래그 → 선이 그려짐
3. Option+Drag (2손가락 시뮬레이션) → 지도가 이동함
4. 기존 탭 모드 동작 변화 없음

- [x] **Step 5: 전체 테스트 실행**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: All tests PASS

- [x] **Step 6: Commit**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+DrawingOverlay.swift
git commit -m "feat: enable two-finger pan/zoom during drawing mode"
```

---

## 실기기 체크리스트

모든 Task 완료 후 `docs/qa/2026-06-24-mvp3-device-checklist.md`를 작성하고 사용자에게 전달한다.
