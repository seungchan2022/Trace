# 마커 그리기 + 스냅 슬라이스 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **완료(소급 확인, 2026-06-22):** 이 슬라이스는 구현·실기기 검증까지 끝났다(그리기 제스처·스냅·전용 오버레이 레이어 — 근거 커밋 `54f6c77`, `8590ba2`). 아래 Task별 `- [ ]` 체크박스는 작업 당시 실시간 갱신되지 않았을 뿐 실제로는 완료 상태다. MVP1 아카이빙 시 체크박스를 일괄 복원하지 않고 이 노트로 갈음한다. 남은 후속(MKDirections 스로틀 완화 등)은 `docs/backlog.md` 참고.

**Goal:** 현재 위치로 시작하는 지도에서 마커(손으로 그린 경로)를 실제 도보 길에 스냅해 거리와 함께 보여준다.

**Architecture:** 기존 포트-어댑터 + MVVM(@Observable). 그린 좌표를 순수 함수로 다운샘플(`DrawnPathSampler`)한 뒤, `CoursePlanningServiceProtocol`의 기본 구현 `snappedRoute(through:)`가 인접 점마다 `route(from:to:)`(MapKit `MKDirections .walking`)를 호출해 이어붙인다. MapKit/CoreLocation 타입은 뷰·인프라에만 가둔다.

**Tech Stack:** Swift, SwiftUI, MapKit, CoreLocation, XCTest, iOS 17+(@Observable / Observation).

## Global Constraints

- iOS 최소 버전: 17.0. 상태는 `@Observable`(Observation), `ObservableObject`/`@Published` 금지.
- 동시성: Swift `async`/`await`, UI 상태는 `@MainActor` 격리.
- MapKit/CoreLocation 타입은 ViewModel/Domain에 노출 금지(도메인 타입 `CourseCoordinate`/`PlannedCourse`만 사용).
- 샘플러 기본 간격 ≈ 120m(스파이크 실측 스위트스폿), 과도 분할 금지.
- 경로 형상은 영속 저장하지 않음(저장은 범위 밖).
- 커밋은 경로별 명시 스테이징(`git add <path>`); `git add -A`/`.` 금지. 푸시 금지.
- 구현은 `main`에서 분기한 `feature/marker-draw-snap` 브랜치에서. 결정/스펙/플랜 문서는 별도 커밋.
- 프로덕션 Swift에 force unwrap(`!`)·force cast(`as!`)·force try(`try!`) 금지(pre-commit 훅·swiftlint 차단). `guard let`/옵셔널 바인딩 사용. 테스트 파일은 훅 예외.

### 검증·커밋 프로토콜 (모든 코드 태스크 공통)

`.swift`/프로젝트 파일 커밋 전 순서대로 실행하고, 각 성공 후 스탬프 생성(없으면 pre-commit 훅이 커밋 차단):

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build && touch .git/trace-verify-build.ok
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' test && touch .git/trace-verify-test.ok
swiftlint && touch .git/trace-verify-lint.ok
```

- 시뮬레이터는 **iPhone 16**(이 머신 가용). testing.md 기본 iPhone 17/iOS 26.5는 없음.
- 각 태스크의 "xcodebuild test ..." 스텝은 위 프로토콜로 대체해 실행한다. 커밋은 `scripts/trace-commit.sh -m "..." -- <path>...`로 경로 명시.

참고 스펙: `docs/superpowers/specs/2026-06-20-marker-draw-snap-mvp-design.md`. 용어: **포인트**=탭한 지점, **마커**=손으로 그린 경로.

---

### Task 1: DrawnPathSampler (순수 다운샘플 + 좌표 거리)

**Files:**
- Create: `Trace/Domain/CoursePlanning/CourseCoordinate+Geo.swift`
- Create: `Trace/Domain/CoursePlanning/DrawnPathSampler.swift`
- Test: `TraceTests/DrawnPathSamplerTests.swift`

**Interfaces:**
- Produces: `CourseCoordinate.distanceMeters(to:) -> Double`; `enum DrawnPathSampler { static func sample(_ raw: [CourseCoordinate], minSpacingMeters: Double = 120) -> [CourseCoordinate] }`

- [ ] **Step 1: 실패 테스트 작성**

```swift
// TraceTests/DrawnPathSamplerTests.swift
import XCTest
@testable import Trace

final class DrawnPathSamplerTests: XCTestCase {
    func testEmptyReturnsEmpty() {
        XCTAssertTrue(DrawnPathSampler.sample([], minSpacingMeters: 120).isEmpty)
    }

    func testSinglePointPreserved() {
        let p = CourseCoordinate(latitude: 37.5, longitude: 127.0)
        XCTAssertEqual(DrawnPathSampler.sample([p], minSpacingMeters: 120), [p])
    }

    func testEndpointsAlwaysPreservedEvenIfClose() {
        let a = CourseCoordinate(latitude: 37.5000, longitude: 127.0000)
        let b = CourseCoordinate(latitude: 37.5001, longitude: 127.0000) // ~11m
        XCTAssertEqual(DrawnPathSampler.sample([a, b], minSpacingMeters: 120), [a, b])
    }

    func testDownsamplesByMinSpacing() {
        // 위도 0.001 ≈ 111m 간격으로 5점 → 120m 간격 다운샘플 시 중간 점들이 솎임
        let raw = (0..<5).map { CourseCoordinate(latitude: 37.5 + Double($0) * 0.001, longitude: 127.0) }
        let result = DrawnPathSampler.sample(raw, minSpacingMeters: 120)
        XCTAssertEqual(result.first, raw.first)
        XCTAssertEqual(result.last, raw.last)
        XCTAssertLessThan(result.count, raw.count)
        // 인접 결과 간 간격이 모두 최소 간격 이상(끝점 보정 구간 제외)
        for i in 0..<(result.count - 2) {
            XCTAssertGreaterThanOrEqual(result[i].distanceMeters(to: result[i + 1]), 120)
        }
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/DrawnPathSamplerTests`
Expected: 컴파일 실패(`distanceMeters`/`DrawnPathSampler` 미정의).

- [ ] **Step 3: 좌표 거리 구현**

```swift
// Trace/Domain/CoursePlanning/CourseCoordinate+Geo.swift
import Foundation

extension CourseCoordinate {
    /// 두 좌표 사이의 대략적 지표면 거리(미터, Haversine).
    func distanceMeters(to other: CourseCoordinate) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }
}
```

- [ ] **Step 4: 샘플러 구현**

```swift
// Trace/Domain/CoursePlanning/DrawnPathSampler.swift
import Foundation

/// 손으로 그린 마커 좌표열을 최소 간격으로 다운샘플한다.
/// 라우팅 호출 수를 제한해 스로틀을 피하고, 시작/끝 좌표는 항상 보존한다.
enum DrawnPathSampler {
    static func sample(_ raw: [CourseCoordinate], minSpacingMeters: Double = 120) -> [CourseCoordinate] {
        guard var last = raw.first else { return [] }
        var result = [last]
        for point in raw.dropFirst() where last.distanceMeters(to: point) >= minSpacingMeters {
            result.append(point)
            last = point
        }
        if let actualLast = raw.last, actualLast != last {
            result.append(actualLast)
        }
        return result
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/DrawnPathSamplerTests`
Expected: PASS.

- [ ] **Step 6: 커밋**

```bash
git add Trace/Domain/CoursePlanning/CourseCoordinate+Geo.swift Trace/Domain/CoursePlanning/DrawnPathSampler.swift TraceTests/DrawnPathSamplerTests.swift
git commit -m "feat: 마커 좌표 다운샘플러와 좌표 거리 헬퍼 추가"
```

---

### Task 2: snappedRoute (구간 이어붙이기 + 재시도) 기본 구현

**Files:**
- Modify: `Trace/Domain/CoursePlanning/Protocol/CoursePlanningServiceProtocol.swift`
- Test: `TraceTests/SnappedRouteTests.swift`

**Interfaces:**
- Consumes: 기존 `func route(from:to:) async throws -> PlannedCourse`
- Produces: 프로토콜 요구사항 `func snappedRoute(through points: [CourseCoordinate]) async throws -> PlannedCourse` + 동일 시그니처의 기본 구현(extension). 각 구간을 `route`로 계산해 좌표를 이어붙이고 거리를 합산, 구간 실패 시 1회 재시도 후에도 실패하면 throw.

- [ ] **Step 1: 실패 테스트 작성**

```swift
// TraceTests/SnappedRouteTests.swift
import XCTest
@testable import Trace

@MainActor
final class SnappedRouteTests: XCTestCase {
    func testStitchesLegsAndSumsDistance() async throws {
        let service = StubLegService()
        let p = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
            CourseCoordinate(latitude: 37.52, longitude: 127.00),
        ]
        let course = try await service.snappedRoute(through: p)
        XCTAssertEqual(service.calls, 2)              // 점 3개 → 구간 2개
        XCTAssertEqual(course.distanceMeters, 200)    // 구간당 100m
        XCTAssertEqual(course.coordinates.first, p[0])
        XCTAssertEqual(course.coordinates.last, p[2])
    }

    func testRetriesTransientLegFailureOnce() async throws {
        let service = StubLegService(failFirstCall: true)
        let p = [
            CourseCoordinate(latitude: 37.50, longitude: 127.00),
            CourseCoordinate(latitude: 37.51, longitude: 127.00),
        ]
        let course = try await service.snappedRoute(through: p)
        XCTAssertEqual(service.calls, 2)              // 첫 호출 실패 + 재시도 성공
        XCTAssertEqual(course.distanceMeters, 100)
    }

    func testThrowsWhenFewerThanTwoPoints() async {
        let service = StubLegService()
        do {
            _ = try await service.snappedRoute(through: [CourseCoordinate(latitude: 37.5, longitude: 127)])
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? CoursePlanningError, .routeNotFound)
        }
    }
}

@MainActor
private final class StubLegService: CoursePlanningServiceProtocol {
    var calls = 0
    private var shouldFailNext: Bool
    init(failFirstCall: Bool = false) { shouldFailNext = failFirstCall }

    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse {
        calls += 1
        if shouldFailNext {
            shouldFailNext = false
            throw CoursePlanningError.requestFailed
        }
        return PlannedCourse(coordinates: [start, destination], distanceMeters: 100)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/SnappedRouteTests`
Expected: 컴파일 실패(`snappedRoute` 미정의).

- [ ] **Step 3: 프로토콜 + 기본 구현 추가**

```swift
// Trace/Domain/CoursePlanning/Protocol/CoursePlanningServiceProtocol.swift
import Foundation

@MainActor
protocol CoursePlanningServiceProtocol {
    func route(from start: CourseCoordinate, to destination: CourseCoordinate) async throws -> PlannedCourse
    func snappedRoute(through points: [CourseCoordinate]) async throws -> PlannedCourse
}

extension CoursePlanningServiceProtocol {
    /// 그린 마커 좌표열을 인접 구간 도보 경로로 이어붙여 하나의 코스로 만든다.
    func snappedRoute(through points: [CourseCoordinate]) async throws -> PlannedCourse {
        guard points.count >= 2 else { throw CoursePlanningError.routeNotFound }

        var coordinates: [CourseCoordinate] = []
        var distance = 0.0
        for index in 0..<(points.count - 1) {
            let leg = try await routeWithRetry(from: points[index], to: points[index + 1])
            // 구간 접합부 좌표 중복 제거
            coordinates.append(contentsOf: coordinates.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst()))
            distance += leg.distanceMeters
        }
        return PlannedCourse(coordinates: coordinates, distanceMeters: distance)
    }

    private func routeWithRetry(
        from start: CourseCoordinate,
        to destination: CourseCoordinate,
        attempts: Int = 2
    ) async throws -> PlannedCourse {
        var lastError: Error = CoursePlanningError.requestFailed
        for attempt in 0..<attempts {
            do {
                return try await route(from: start, to: destination)
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
        throw lastError
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/SnappedRouteTests`
Expected: PASS. (기존 `TraceTests`도 함께 통과해야 함 — 기존 fake들은 기본 구현으로 자동 충족.)

- [ ] **Step 5: 커밋**

```bash
git add Trace/Domain/CoursePlanning/Protocol/CoursePlanningServiceProtocol.swift TraceTests/SnappedRouteTests.swift
git commit -m "feat: 그린 마커를 도보 경로로 이어붙이는 snappedRoute 추가"
```

---

### Task 3: LocationService(현재 위치) + DI + 권한 문자열

**Files:**
- Create: `Trace/Domain/Location/LocationError.swift`
- Create: `Trace/Domain/Location/Protocol/LocationServiceProtocol.swift`
- Create: `Trace/Infrastructure/Location/CoreLocation/CoreLocationService.swift`
- Modify: `Trace/App/DependencyContainer.swift`
- Modify: `Trace.xcodeproj/project.pbxproj` (앱 타깃 빌드 설정에 위치 권한 문자열)

**Interfaces:**
- Produces: `enum LocationError: Error { case unavailable, denied }`; `@MainActor protocol LocationServiceProtocol { func currentLocation() async throws -> CourseCoordinate }`; `DependencyContainer.locationService`.

- [ ] **Step 1: Domain 프로토콜·에러 작성**

```swift
// Trace/Domain/Location/LocationError.swift
import Foundation

enum LocationError: Error, Equatable {
    case denied
    case unavailable
}
```

```swift
// Trace/Domain/Location/Protocol/LocationServiceProtocol.swift
import Foundation

@MainActor
protocol LocationServiceProtocol {
    func currentLocation() async throws -> CourseCoordinate
}
```

- [ ] **Step 2: CoreLocation 어댑터 작성**

```swift
// Trace/Infrastructure/Location/CoreLocation/CoreLocationService.swift
import CoreLocation
import Foundation

@MainActor
final class CoreLocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CourseCoordinate, Error>?

    func currentLocation() async throws -> CourseCoordinate {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .restricted, .denied:
                finish(.failure(LocationError.denied))
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            @unknown default:
                finish(.failure(LocationError.unavailable))
            }
        }
    }

    private func finish(_ result: Result<CourseCoordinate, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
            case .restricted, .denied: finish(.failure(LocationError.denied))
            case .notDetermined: break
            @unknown default: finish(.failure(LocationError.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        let coord = CourseCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        Task { @MainActor in self.finish(.success(coord)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(LocationError.unavailable)) }
    }
}
```

- [ ] **Step 3: DI에 locationService 추가**

```swift
// Trace/App/DependencyContainer.swift
import Foundation

struct DependencyContainer {
    let coursePlanningService: CoursePlanningServiceProtocol
    let locationService: LocationServiceProtocol

    @MainActor
    static func live() -> DependencyContainer {
        DependencyContainer(
            coursePlanningService: MapKitCoursePlanningService(),
            locationService: CoreLocationService()
        )
    }

    @MainActor
    static func uiTesting() -> DependencyContainer {
        DependencyContainer(
            coursePlanningService: UITestingCoursePlanningService(),
            locationService: UITestingLocationService()
        )
    }
}

private final class UITestingCoursePlanningService: CoursePlanningServiceProtocol {
    func route(
        from start: CourseCoordinate,
        to destination: CourseCoordinate
    ) async throws -> PlannedCourse {
        if ProcessInfo.processInfo.arguments.contains("-traceRouteFailure") {
            throw CoursePlanningError.routeNotFound
        }

        return PlannedCourse(
            coordinates: [
                start,
                CourseCoordinate(
                    latitude: (start.latitude + destination.latitude) / 2 + 0.001,
                    longitude: (start.longitude + destination.longitude) / 2
                ),
                destination
            ],
            distanceMeters: 1200
        )
    }
}

private final class UITestingLocationService: LocationServiceProtocol {
    func currentLocation() async throws -> CourseCoordinate {
        CourseCoordinate(latitude: 37.5666, longitude: 126.9784) // 서울시청 고정
    }
}
```

> 참고: `live()`/`uiTesting()`에 `@MainActor`를 붙였다. 호출부(`TraceApp.init`, `ContentView`)는 이미 메인에서 실행되므로 문제없다. 컴파일 에러가 나면 해당 호출을 `MainActor.assumeIsolated`로 감싸지 말고, 호출 위치가 메인인지 먼저 확인할 것.

- [ ] **Step 4: 위치 권한 문자열 추가 (빌드 설정)**

`Trace.xcodeproj/project.pbxproj`의 **앱 타깃**(`Trace`) Debug/Release 빌드 설정 양쪽에 아래 키 추가(다른 `INFOPLIST_KEY_*` 항목 옆):

```
INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "달릴 코스를 현재 위치에서 시작하기 위해 위치를 사용합니다.";
```

Xcode UI로 하려면: 타깃 `Trace` → Info → Custom iOS Target Properties에 `Privacy - Location When In Use Usage Description` 추가. (테스트 타깃 아님, 앱 타깃만.)

- [ ] **Step 5: 빌드 + 기존 테스트 통과 확인**

Run: `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests`
Expected: 빌드 성공, 기존 전체 테스트 PASS. (이 시점에 `CoursePlannerPage`는 아직 locationService를 받지 않으므로 호출부 수정 불필요.)

- [ ] **Step 6: 커밋**

```bash
git add Trace/Domain/Location Trace/Infrastructure/Location Trace/App/DependencyContainer.swift Trace.xcodeproj/project.pbxproj
git commit -m "feat: 현재 위치 LocationService와 권한 문자열, DI 배선 추가"
```

---

### Task 4: ViewModel — 현재 위치로 카메라 부트스트랩

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (init 시그니처)
- Modify: `Trace/App/TraceApp.swift`, `Trace/App/ContentView.swift` (호출부)
- Modify: `TraceTests/TraceTests.swift` (기존 테스트의 ViewModel 생성 + Fake 추가)

**Interfaces:**
- Consumes: `LocationServiceProtocol`
- Produces: `CoursePlannerPageViewModel.init(coursePlanningService:locationService:)`; `var initialCameraCoordinate: CourseCoordinate?`; `func bootstrapLocation() async`. 위치 실패 시 폴백 좌표(서울시청 37.5666,126.9784).

- [ ] **Step 1: 실패 테스트 작성 (TraceTests.swift에 추가 + 기존 생성부 갱신)**

`TraceTests.swift` 상단 기존 `FakeCoursePlanningService` 아래에 Fake 추가:

```swift
@MainActor
private final class FakeLocationService: LocationServiceProtocol {
    var result: Result<CourseCoordinate, Error> = .success(CourseCoordinate(latitude: 37.4979, longitude: 127.0276))
    func currentLocation() async throws -> CourseCoordinate { try result.get() }
}
```

기존 세 테스트의 `CoursePlannerPageViewModel(coursePlanningService: service)` 생성을 모두 아래로 변경:

```swift
let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: FakeLocationService())
```

새 테스트 추가:

```swift
func testBootstrapSetsCameraToCurrentLocation() async {
    let service = FakeCoursePlanningService()
    let location = FakeLocationService()
    location.result = .success(CourseCoordinate(latitude: 37.4979, longitude: 127.0276))
    let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: location)

    await viewModel.bootstrapLocation()

    XCTAssertEqual(viewModel.initialCameraCoordinate?.latitude, 37.4979)
}

func testBootstrapFallsBackWhenLocationDenied() async {
    let service = FakeCoursePlanningService()
    let location = FakeLocationService()
    location.result = .failure(LocationError.denied)
    let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: location)

    await viewModel.bootstrapLocation()

    XCTAssertEqual(viewModel.initialCameraCoordinate?.latitude, 37.5666) // 서울시청 폴백
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests`
Expected: 컴파일 실패(init 시그니처 불일치 / `bootstrapLocation` 미정의).

- [ ] **Step 3: ViewModel 수정**

`CoursePlannerPageViewModel.swift`에 프로퍼티·init·메서드 추가:

```swift
// 프로퍼티 추가
private(set) var initialCameraCoordinate: CourseCoordinate?
private let locationService: LocationServiceProtocol

// init 교체
init(
    coursePlanningService: CoursePlanningServiceProtocol,
    locationService: LocationServiceProtocol
) {
    self.coursePlanningService = coursePlanningService
    self.locationService = locationService
}

// 메서드 추가
func bootstrapLocation() async {
    do {
        initialCameraCoordinate = try await locationService.currentLocation()
    } catch {
        initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
    }
}
```

- [ ] **Step 4: 호출부 수정**

`CoursePlannerPage.swift` init:

```swift
init(
    coursePlanningService: CoursePlanningServiceProtocol,
    locationService: LocationServiceProtocol
) {
    _viewModel = State(initialValue: CoursePlannerPageViewModel(
        coursePlanningService: coursePlanningService,
        locationService: locationService
    ))
}
```

`CoursePlannerPage.swift`의 `#Preview` 및 `TraceApp.swift:24`, `ContentView.swift:12`:

```swift
// TraceApp.swift
CoursePlannerPage(
    coursePlanningService: container.coursePlanningService,
    locationService: container.locationService
)

// ContentView.swift
CoursePlannerPage(
    coursePlanningService: DependencyContainer.live().coursePlanningService,
    locationService: DependencyContainer.live().locationService
)

// CoursePlannerPage.swift #Preview
CoursePlannerPage(
    coursePlanningService: DependencyContainer.uiTesting().coursePlanningService,
    locationService: DependencyContainer.uiTesting().locationService
)
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests`
Expected: PASS(신규 2개 포함 전체).

- [ ] **Step 6: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift Trace/App/TraceApp.swift Trace/App/ContentView.swift TraceTests/TraceTests.swift
git commit -m "feat: 진입 시 현재 위치로 카메라 부트스트랩(실패 시 폴백)"
```

---

### Task 5: ViewModel — 그리기 모드 + 마커 스냅 + 초기화

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `TraceTests/TraceTests.swift`

**Interfaces:**
- Consumes: `DrawnPathSampler.sample`, `coursePlanningService.snappedRoute(through:)`
- Produces: `var isDrawingMode: Bool`; `var drawnStrokes: [[CourseCoordinate]]`; `func toggleDrawingMode()`; `func appendStroke(_ stroke: [CourseCoordinate]) async`; `func clear()`. 성공 시 `course` 갱신, 실패 시 `errorMessage` 설정·`course` 유지.

- [ ] **Step 1: 실패 테스트 작성**

```swift
func testAppendStrokeSnapsAndPublishesCourse() async {
    let service = FakeCoursePlanningService()
    let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: FakeLocationService())
    let stroke = [
        CourseCoordinate(latitude: 37.50, longitude: 127.00),
        CourseCoordinate(latitude: 37.51, longitude: 127.00),
        CourseCoordinate(latitude: 37.52, longitude: 127.00),
    ]

    await viewModel.appendStroke(stroke)

    XCTAssertNotNil(viewModel.course)
    XCTAssertEqual(viewModel.drawnStrokes.count, 1)
    XCTAssertNil(viewModel.errorMessage)
}

func testAppendStrokeFailureSetsErrorAndKeepsNoCourse() async {
    let service = FakeCoursePlanningService()
    service.result = .failure(CoursePlanningError.requestFailed)
    let viewModel = CoursePlannerPageViewModel(coursePlanningService: service, locationService: FakeLocationService())

    await viewModel.appendStroke([
        CourseCoordinate(latitude: 37.50, longitude: 127.00),
        CourseCoordinate(latitude: 37.51, longitude: 127.00),
    ])

    XCTAssertNil(viewModel.course)
    XCTAssertNotNil(viewModel.errorMessage)
}

func testToggleDrawingModeFlips() {
    let viewModel = CoursePlannerPageViewModel(coursePlanningService: FakeCoursePlanningService(), locationService: FakeLocationService())
    XCTAssertFalse(viewModel.isDrawingMode)
    viewModel.toggleDrawingMode()
    XCTAssertTrue(viewModel.isDrawingMode)
}

func testClearResetsState() async {
    let viewModel = CoursePlannerPageViewModel(coursePlanningService: FakeCoursePlanningService(), locationService: FakeLocationService())
    await viewModel.appendStroke([
        CourseCoordinate(latitude: 37.50, longitude: 127.00),
        CourseCoordinate(latitude: 37.51, longitude: 127.00),
    ])
    viewModel.clear()
    XCTAssertNil(viewModel.course)
    XCTAssertTrue(viewModel.drawnStrokes.isEmpty)
    XCTAssertNil(viewModel.errorMessage)
}
```

> 주의: `FakeCoursePlanningService`는 `route`만 구현하므로 `snappedRoute`는 기본 구현으로 동작한다. 기본 구현이 점 1쌍 이상을 요구하므로 위 stroke는 2점 이상이어야 한다.

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests`
Expected: 컴파일 실패(`isDrawingMode`/`appendStroke`/`clear` 미정의).

- [ ] **Step 3: ViewModel 수정**

```swift
// 프로퍼티 추가
private(set) var isDrawingMode = false
private(set) var drawnStrokes: [[CourseCoordinate]] = []

// 메서드 추가
func toggleDrawingMode() {
    isDrawingMode.toggle()
}

func appendStroke(_ stroke: [CourseCoordinate]) async {
    guard stroke.count >= 2 else { return }
    drawnStrokes.append(stroke)
    await recomputeSnappedCourse()
}

func clear() {
    drawnStrokes = []
    course = nil
    errorMessage = nil
    isLoading = false
}

private func recomputeSnappedCourse() async {
    let allPoints = drawnStrokes.flatMap { $0 }
    let sampled = DrawnPathSampler.sample(allPoints)
    guard sampled.count >= 2 else { course = nil; return }

    isLoading = true
    errorMessage = nil
    do {
        course = try await coursePlanningService.snappedRoute(through: sampled)
    } catch {
        errorMessage = "경로를 계산할 수 없습니다."
    }
    isLoading = false
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests`
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift TraceTests/TraceTests.swift
git commit -m "feat: 그리기 모드와 마커 스냅 코스 계산, 초기화 추가"
```

---

### Task 6: ViewModel — 되돌리기(마지막 구간 취소)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Modify: `TraceTests/TraceTests.swift`

**Interfaces:**
- Produces: `func undoLastStroke() async`. 마지막 구간 제거 후 재계산; 남은 구간이 없으면 `course = nil`.

- [ ] **Step 1: 실패 테스트 작성**

```swift
func testUndoRemovesLastStroke() async {
    let viewModel = CoursePlannerPageViewModel(coursePlanningService: FakeCoursePlanningService(), locationService: FakeLocationService())
    await viewModel.appendStroke([
        CourseCoordinate(latitude: 37.50, longitude: 127.00),
        CourseCoordinate(latitude: 37.51, longitude: 127.00),
    ])
    await viewModel.appendStroke([
        CourseCoordinate(latitude: 37.52, longitude: 127.00),
        CourseCoordinate(latitude: 37.53, longitude: 127.00),
    ])

    await viewModel.undoLastStroke()
    XCTAssertEqual(viewModel.drawnStrokes.count, 1)

    await viewModel.undoLastStroke()
    XCTAssertTrue(viewModel.drawnStrokes.isEmpty)
    XCTAssertNil(viewModel.course)
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests`
Expected: 컴파일 실패(`undoLastStroke` 미정의).

- [ ] **Step 3: ViewModel 수정**

```swift
func undoLastStroke() async {
    guard !drawnStrokes.isEmpty else { return }
    drawnStrokes.removeLast()
    if drawnStrokes.isEmpty {
        course = nil
        errorMessage = nil
    } else {
        await recomputeSnappedCourse()
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests`
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift TraceTests/TraceTests.swift
git commit -m "feat: 마지막 그리기 구간 되돌리기 추가"
```

---

### Task 7: View — 카메라/그리기 제스처/모드 토글/버튼 (시뮬레이터 검증)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`
- Create: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift`

**Interfaces:**
- Consumes: ViewModel의 `initialCameraCoordinate`, `isDrawingMode`, `course`, `distanceText`, `isLoading`, `errorMessage`, `bootstrapLocation()`, `toggleDrawingMode()`, `appendStroke(_:)`, `undoLastStroke()`, `clear()`.

> 이 태스크는 제스처/CoreLocation/MapKit 렌더링이라 단위 테스트 불가. **시뮬레이터 수동 검증**이 게이트다.

- [ ] **Step 1: 카메라 + 진입 시 부트스트랩 배선**

`CoursePlannerPage.swift`에 카메라 상태와 `task`를 추가하고, `Map`을 `Map(position: $cameraPosition)`으로 바꾼다. 진입 시 위치를 받아 카메라를 맞춘다:

```swift
@State private var cameraPosition: MapCameraPosition = .automatic

// body의 ZStack에 .task 부착
.task {
    await viewModel.bootstrapLocation()
    if let c = viewModel.initialCameraCoordinate {
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        ))
    }
}
```

- [ ] **Step 2: 그리기 제스처 + 진행 중 마커 표시**

그리기 모드일 때 드래그로 화면 점을 모아 좌표로 변환하고, 손을 떼면 `appendStroke` 호출. 진행 중 선도 표시:

```swift
@State private var currentStroke: [CourseCoordinate] = []

// mapView의 MapReader { proxy in Map { ... } } 내부에 진행 중 스트로크 폴리라인 추가
if currentStroke.count > 1 {
    MapPolyline(coordinates: currentStroke.map(CLLocationCoordinate2D.init))
        .stroke(.orange, lineWidth: 4)
}

// Map에 부착할 제스처: 그리기 모드에서만 그리기, 아니면 SpatialTap(기존 포인트 유지)
.gesture(
    viewModel.isDrawingMode
    ? DragGesture(minimumDistance: 0)
        .onChanged { value in
            if let c = proxy.convert(value.location, from: .local) {
                currentStroke.append(CourseCoordinate(c))
            }
        }
        .onEnded { _ in
            let stroke = currentStroke
            currentStroke = []
            Task { await viewModel.appendStroke(stroke) }
        }
    : nil
)
```

> 기존 `SpatialTapGesture`(포인트 탭)는 일반 모드에서 유지한다. 그리기 모드에서는 `DragGesture`가 지도 pan을 가로채 지도가 고정된다.

- [ ] **Step 3: 컨트롤 컴포넌트(모드 토글·초기화·되돌리기)**

```swift
// Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift
import SwiftUI

extension CoursePlannerPage {
    var controls: some View {
        HStack(spacing: 12) {
            Button(viewModel.isDrawingMode ? "그리기 종료" : "그리기") {
                viewModel.toggleDrawingMode()
            }
            .accessibilityIdentifier("coursePlanner.drawToggle")

            Button("되돌리기") { Task { await viewModel.undoLastStroke() } }
                .accessibilityIdentifier("coursePlanner.undo")

            Button("초기화") { viewModel.clear() }
                .accessibilityIdentifier("coursePlanner.clear")
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
}
```

`CoursePlannerPage.swift` body의 `ZStack`에 `controls`를 상단 정렬로 얹는다(예: `VStack`으로 `controls`를 위, `statusPanel`을 아래로 배치하거나 `.overlay(alignment: .top)`).

- [ ] **Step 4: 시뮬레이터 수동 검증**

XcodeBuildMCP로 빌드·실행 후 확인:
1. 앱 실행 → 위치 권한 팝업 → 허용 → 지도가 현재 위치(시뮬레이터 기본 위치)로 줌인되는가.
2. "그리기" 탭 → 지도에서 곡선을 드래그 → 손 떼면 그린 모양을 따라 **실제 길에 붙은 파란 경로 + 거리**가 뜨는가.
3. 한 번 더 그려 이어지는가. "되돌리기"로 마지막 구간만 사라지는가. "초기화"로 전부 사라지는가.
4. 일부러 한국 도심(예: 강남) 좌표로 위치 설정해 스냅 품질을 눈으로 확인(스파이크 결론 재확인).

Run(예): XcodeBuildMCP `build_run_sim` → `screenshot`으로 결과 캡처.

- [ ] **Step 5: 커밋**

```bash
git add Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+ControlsComponent.swift
git commit -m "feat: 마커 그리기 제스처와 카메라/컨트롤 UI 배선"
```

---

## 검증 (완료 전)

- `xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests` 전체 PASS.
- Task 7 시뮬레이터 수동 검증 통과(스크린샷 첨부).
- `superpowers:verification-before-completion`로 실제 명령·결과 확인 후 완료 선언.
- execute→review 사이클 종료 시 `ce-compound`로 재사용 교훈 점검(`docs/agent-rules/skills.md`).

## 자체 점검 결과

- 스펙 커버리지: (a)현재위치/줌=Task 3·4·7 / (b)마커 스냅=Task 1·2·5·7 / (g)초기화·되돌리기=Task 5·6·7. 누락 없음.
- 스로틀 대응: 샘플러 120m(Task 1) + 구간 재시도(Task 2)로 반영.
- 실패 구간을 직선으로 몰래 메우지 않음: 구간 실패 시 throw→`errorMessage`(Task 2·5). 구간별 시각 표시는 다음 슬라이스로 명시 연기.
- 타입 일관성: `snappedRoute(through:)`, `appendStroke(_:)`, `undoLastStroke()`, `bootstrapLocation()`, `initialCameraCoordinate` 명칭 태스크 간 일치.
