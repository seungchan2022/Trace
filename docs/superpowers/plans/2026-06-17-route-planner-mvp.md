# 러닝 코스 계획 MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 지도에서 출발지와 도착지를 탭하면 실제 도보 경로와 총 거리를 보여주는 Trace 첫 MVP 화면을 만든다.

**Architecture:** MVVM을 유지하고 경로 계산은 `RoutePlanningService` 포트 뒤로 숨긴다. 첫 구현은 `MapKitRoutePlanningService` 어댑터를 사용하되, UI 테스트에서는 가짜 라우팅 서비스를 주입할 수 있게 앱 시작 구성을 분리한다. 상태 관리는 iOS 17+ Observation API의 `@Observable`을 사용하고, Swift 6 동시성 기준에 맞게 UI 상태와 MVP 라우팅 포트는 `@MainActor` 경계에서 다룬다.

**Tech Stack:** SwiftUI, MapKit, XCTest, XCUITest, iOS 17+, Xcode project `Trace.xcodeproj`, scheme `Trace`

---

## 파일 구조

- Create: `Trace/Features/RoutePlanner/Domain/PlannedRoute.swift`
  - 경로 거리와 지도에 그릴 좌표 배열을 담는 도메인 모델.
- Create: `Trace/Features/RoutePlanner/Domain/RoutePlanningService.swift`
  - 경로 계산 포트와 에러 타입.
- Create: `Trace/Features/RoutePlanner/Infrastructure/MapKitRoutePlanningService.swift`
  - `MKDirections` 기반 실제 도보 경로 어댑터. `Infrastructure`는 유스케이스가 아니라 외부 SDK/시스템 API 구현 세부사항을 담는다.
- Create: `Trace/Features/RoutePlanner/Presentation/RoutePlannerViewModel.swift`
  - 지도 탭 선택 상태, 경로 계산, 로딩/에러 상태 관리.
- Create: `Trace/Features/RoutePlanner/Presentation/RoutePlannerView.swift`
  - SwiftUI 지도, 핀, 경로선, 거리 패널, 에러 표시.
- Create: `Trace/App/DependencyContainer.swift`
  - 앱 실행 모드별 의존성 구성.
- Modify: `Trace/TraceApp.swift`
  - `DependencyContainer`를 만들고 `RoutePlannerView`를 첫 화면으로 표시.
- Modify: `Trace/ContentView.swift`
  - 필요 없으면 제거하거나 `RoutePlannerView` 래퍼로 축소.
- Replace: `TraceTests/TraceTests.swift`
  - ViewModel 단위 테스트로 교체.
- Replace: `TraceUITests/TraceUITests.swift`
  - 실제 사용자 흐름 기반 UI 테스트로 교체.

커밋은 Trace 규칙상 사용자가 요청할 때만 한다. 이 계획의 "커밋" 단계는 구현자가 사용자 요청을 받은 경우에만 수행한다.

첫 MVP에서는 별도 UseCase 파일을 만들지 않는다. 아직 앱 정책이 단순하기 때문에 `RoutePlannerViewModel`이 `RoutePlanningService` 포트를 직접 호출한다. 추후 코스 저장, 회피 구간, 선호 거리, 한국 지도 제공자 선택 같은 정책이 생기면 `PlanRouteUseCase`를 추가한다.

---

### Task 1: 도메인 모델과 경로 계산 포트

**Files:**
- Create: `Trace/Features/RoutePlanner/Domain/PlannedRoute.swift`
- Create: `Trace/Features/RoutePlanner/Domain/RoutePlanningService.swift`
- Test: `TraceTests/TraceTests.swift`

- [ ] **Step 1: 실패하는 ViewModel 테스트의 기반 타입을 먼저 작성한다**

`TraceTests/TraceTests.swift`를 아래처럼 교체한다. 이 시점에는 타입이 없으므로 컴파일 실패가 기대된다.

```swift
import CoreLocation
import XCTest
@testable import Trace

final class RoutePlannerViewModelTests: XCTestCase {
    func testFirstTapSelectsStartOnly() async {
        let service = FakeRoutePlanningService()
        let viewModel = await MainActor.run {
            RoutePlannerViewModel(routePlanningService: service)
        }

        let start = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)

        await viewModel.handleMapTap(at: start)

        await MainActor.run {
            XCTAssertEqual(viewModel.startCoordinate?.latitude, start.latitude)
            XCTAssertNil(viewModel.destinationCoordinate)
            XCTAssertNil(viewModel.route)
            XCTAssertEqual(service.requestCount, 0)
        }
    }
}

@MainActor
private final class FakeRoutePlanningService: RoutePlanningService {
    var requestCount = 0

    func route(from start: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws -> PlannedRoute {
        requestCount += 1
        return PlannedRoute(
            coordinates: [start, destination],
            distanceMeters: 1200
        )
    }
}
```

- [ ] **Step 2: 테스트 실패를 확인한다**

Run:

```bash
xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/RoutePlannerViewModelTests/testFirstTapSelectsStartOnly
```

Expected: `RoutePlanningService`, `PlannedRoute`, `RoutePlannerViewModel` 타입이 없어 컴파일 실패.

- [ ] **Step 3: `PlannedRoute`를 추가한다**

`Trace/Features/RoutePlanner/Domain/PlannedRoute.swift`

```swift
import CoreLocation
import Foundation

struct PlannedRoute: Equatable, Sendable {
    let coordinates: [CLLocationCoordinate2D]
    let distanceMeters: CLLocationDistance
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
```

- [ ] **Step 4: `RoutePlanningService`를 추가한다**

`Trace/Features/RoutePlanner/Domain/RoutePlanningService.swift`

```swift
import CoreLocation
import Foundation

@MainActor
protocol RoutePlanningService {
    func route(from start: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws -> PlannedRoute
}

enum RoutePlanningError: Error, Equatable {
    case routeNotFound
    case requestFailed
}
```

- [ ] **Step 5: 테스트를 다시 실행해 다음 실패를 확인한다**

Run:

```bash
xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/RoutePlannerViewModelTests/testFirstTapSelectsStartOnly
```

Expected: `RoutePlannerViewModel` 타입이 없어 컴파일 실패.

---

### Task 2: RoutePlannerViewModel 상태 전이

**Files:**
- Create: `Trace/Features/RoutePlanner/Presentation/RoutePlannerViewModel.swift`
- Modify: `TraceTests/TraceTests.swift`

- [ ] **Step 1: ViewModel 테스트를 확장한다**

`TraceTests/TraceTests.swift`에 아래 테스트를 추가한다.

```swift
func testSecondTapRequestsRouteAndPublishesDistance() async {
    let service = FakeRoutePlanningService()
    let viewModel = await MainActor.run {
        RoutePlannerViewModel(routePlanningService: service)
    }
    let start = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
    let destination = CLLocationCoordinate2D(latitude: 37.5700, longitude: 126.9820)

    await viewModel.handleMapTap(at: start)
    await viewModel.handleMapTap(at: destination)

    await MainActor.run {
        XCTAssertEqual(viewModel.destinationCoordinate?.latitude, destination.latitude)
        XCTAssertEqual(viewModel.route?.distanceMeters, 1200)
        XCTAssertEqual(viewModel.distanceText, "1.20 km")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(service.requestCount, 1)
    }
}

func testRouteFailureShowsErrorAndDoesNotPublishRoute() async {
    let service = FakeRoutePlanningService()
    service.result = .failure(RoutePlanningError.routeNotFound)
    let viewModel = await MainActor.run {
        RoutePlannerViewModel(routePlanningService: service)
    }

    await viewModel.handleMapTap(at: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780))
    await viewModel.handleMapTap(at: CLLocationCoordinate2D(latitude: 37.5700, longitude: 126.9820))

    await MainActor.run {
        XCTAssertNil(viewModel.route)
        XCTAssertEqual(viewModel.errorMessage, "도보 경로를 찾을 수 없습니다.")
    }
}
```

`FakeRoutePlanningService`를 아래처럼 바꾼다.

```swift
@MainActor
private final class FakeRoutePlanningService: RoutePlanningService {
    var requestCount = 0
    var result: Result<PlannedRoute, Error>?

    func route(from start: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws -> PlannedRoute {
        requestCount += 1

        if let result {
            return try result.get()
        }

        return PlannedRoute(
            coordinates: [start, destination],
            distanceMeters: 1200
        )
    }
}
```

- [ ] **Step 2: 테스트 실패를 확인한다**

Run:

```bash
xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/RoutePlannerViewModelTests
```

Expected: `RoutePlannerViewModel` 없음 또는 속성/메서드 없음으로 실패.

- [ ] **Step 3: ViewModel을 구현한다**

`Trace/Features/RoutePlanner/Presentation/RoutePlannerViewModel.swift`

```swift
import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class RoutePlannerViewModel {
    private(set) var startCoordinate: CLLocationCoordinate2D?
    private(set) var destinationCoordinate: CLLocationCoordinate2D?
    private(set) var route: PlannedRoute?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let routePlanningService: RoutePlanningService

    init(routePlanningService: RoutePlanningService) {
        self.routePlanningService = routePlanningService
    }

    var distanceText: String? {
        guard let route else { return nil }
        return String(format: "%.2f km", route.distanceMeters / 1000)
    }

    func handleMapTap(at coordinate: CLLocationCoordinate2D) async {
        if startCoordinate == nil || destinationCoordinate != nil {
            startCoordinate = coordinate
            destinationCoordinate = nil
            route = nil
            errorMessage = nil
            isLoading = false
            return
        }

        destinationCoordinate = coordinate
        await calculateRoute()
    }

    private func calculateRoute() async {
        guard let startCoordinate, let destinationCoordinate else { return }

        isLoading = true
        errorMessage = nil
        route = nil

        do {
            let plannedRoute = try await routePlanningService.route(from: startCoordinate, to: destinationCoordinate)
            route = plannedRoute
        } catch RoutePlanningError.routeNotFound {
            errorMessage = "도보 경로를 찾을 수 없습니다."
        } catch {
            errorMessage = "경로를 계산할 수 없습니다."
        }

        isLoading = false
    }
}
```

- [ ] **Step 4: 단위 테스트 통과를 확인한다**

Run:

```bash
xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceTests/RoutePlannerViewModelTests
```

Expected: `TEST SUCCEEDED`.

---

### Task 3: MapKit 라우팅 어댑터

**Files:**
- Create: `Trace/Features/RoutePlanner/Infrastructure/MapKitRoutePlanningService.swift`

- [ ] **Step 1: 어댑터를 구현한다**

`Trace/Features/RoutePlanner/Infrastructure/MapKitRoutePlanningService.swift`

```swift
import CoreLocation
import Foundation
import MapKit

final class MapKitRoutePlanningService: RoutePlanningService {
    func route(from start: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws -> PlannedRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw RoutePlanningError.routeNotFound
            }

            var coordinates = Array(
                repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                count: route.polyline.pointCount
            )
            route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: route.polyline.pointCount))

            return PlannedRoute(
                coordinates: coordinates,
                distanceMeters: route.distance
            )
        } catch let error as RoutePlanningError {
            throw error
        } catch {
            throw RoutePlanningError.requestFailed
        }
    }
}
```

- [ ] **Step 2: 빌드로 컴파일을 확인한다**

Run:

```bash
xcodebuild build -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: `BUILD SUCCEEDED`.

---

### Task 4: RoutePlannerView UI 구현

**Files:**
- Create: `Trace/Features/RoutePlanner/Presentation/RoutePlannerView.swift`
- Create: `Trace/App/DependencyContainer.swift`
- Modify: `Trace/TraceApp.swift`
- Modify: `Trace/ContentView.swift`

- [ ] **Step 1: 앱 환경 구성을 추가한다**

`Trace/App/DependencyContainer.swift`

```swift
import CoreLocation
import Foundation

struct DependencyContainer {
    let routePlanningService: RoutePlanningService

    static func live() -> DependencyContainer {
        DependencyContainer(routePlanningService: MapKitRoutePlanningService())
    }

    static func uiTesting() -> DependencyContainer {
        DependencyContainer(routePlanningService: UITestingRoutePlanningService())
    }
}

private final class UITestingRoutePlanningService: RoutePlanningService {
    func route(from start: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws -> PlannedRoute {
        if ProcessInfo.processInfo.arguments.contains("-traceRouteFailure") {
            throw RoutePlanningError.routeNotFound
        }

        return PlannedRoute(
            coordinates: [
                start,
                CLLocationCoordinate2D(
                    latitude: (start.latitude + destination.latitude) / 2 + 0.001,
                    longitude: (start.longitude + destination.longitude) / 2
                ),
                destination
            ],
            distanceMeters: 1200
        )
    }
}
```

- [ ] **Step 2: SwiftUI 지도 화면을 추가한다**

`Trace/Features/RoutePlanner/Presentation/RoutePlannerView.swift`

```swift
import MapKit
import SwiftUI

struct RoutePlannerView: View {
    @State private var viewModel: RoutePlannerViewModel

    init(routePlanningService: RoutePlanningService) {
        _viewModel = State(initialValue: RoutePlannerViewModel(routePlanningService: routePlanningService))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapView
                .accessibilityIdentifier("routePlanner.map")

            statusPanel
        }
    }

    private var mapView: some View {
        MapReader { proxy in
            Map {
                if let route = viewModel.route {
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(.blue, lineWidth: 6)
                }

                if let start = viewModel.startCoordinate {
                    Marker("출발", systemImage: "figure.run", coordinate: start)
                        .tint(.green)
                }

                if let destination = viewModel.destinationCoordinate {
                    Marker("도착", systemImage: "flag.checkered", coordinate: destination)
                        .tint(.red)
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        Task {
                            await viewModel.handleMapTap(at: coordinate)
                        }
                    }
            )
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isLoading {
                Text("경로 계산 중")
                    .accessibilityIdentifier("routePlanner.loading")
            } else if let distanceText = viewModel.distanceText {
                Text(distanceText)
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("routePlanner.distance")
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("routePlanner.error")
            } else {
                Text("지도에서 출발지를 선택하세요")
                    .accessibilityIdentifier("routePlanner.prompt")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }
}

#Preview {
    RoutePlannerView(routePlanningService: DependencyContainer.uiTesting().routePlanningService)
}
```

- [ ] **Step 3: 앱 첫 화면을 교체한다**

`Trace/TraceApp.swift`

```swift
import SwiftUI

@main
struct TraceApp: App {
    private let container: DependencyContainer

    init() {
        if ProcessInfo.processInfo.arguments.contains("-traceUITesting") {
            container = .uiTesting()
        } else {
            container = .live()
        }
    }

    var body: some Scene {
        WindowGroup {
            RoutePlannerView(routePlanningService: container.routePlanningService)
        }
    }
}
```

`Trace/ContentView.swift`

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
            RoutePlannerView(routePlanningService: DependencyContainer.live().routePlanningService)
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 4: 빌드한다**

Run:

```bash
xcodebuild build -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: `BUILD SUCCEEDED`.

---

### Task 5: UI 테스트 자동화

**Files:**
- Replace: `TraceUITests/TraceUITests.swift`

- [ ] **Step 1: UI 테스트를 작성한다**

`TraceUITests/TraceUITests.swift`

```swift
import XCTest

final class TraceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSelectingTwoPointsShowsDistance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-traceUITesting"]
        app.launch()

        let map = app.otherElements["routePlanner.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))

        map.tapCoordinate(xRatio: 0.35, yRatio: 0.45)
        map.tapCoordinate(xRatio: 0.65, yRatio: 0.55)

        XCTAssertTrue(app.staticTexts["1.20 km"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRouteFailureShowsError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-traceUITesting", "-traceRouteFailure"]
        app.launch()

        let map = app.otherElements["routePlanner.map"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))

        map.tapCoordinate(xRatio: 0.35, yRatio: 0.45)
        map.tapCoordinate(xRatio: 0.65, yRatio: 0.55)

        XCTAssertTrue(app.staticTexts["도보 경로를 찾을 수 없습니다."].waitForExistence(timeout: 5))
    }
}

private extension XCUIElement {
    func tapCoordinate(xRatio: CGFloat, yRatio: CGFloat) {
        let coordinate = coordinate(
            withNormalizedOffset: CGVector(dx: xRatio, dy: yRatio)
        )
        coordinate.tap()
    }
}
```

- [ ] **Step 2: UI 테스트를 실행한다**

Run:

```bash
xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TraceUITests
```

Expected: `TEST SUCCEEDED`. Simulator에서 앱이 실행되고 지도 영역을 두 번 탭하는 흐름이 보인다.

---

### Task 6: 실제 MapKit 스모크 검증

**Files:**
- No file changes

- [ ] **Step 1: 앱을 Simulator에서 실행한다**

Run:

```bash
xcodebuild build -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2: 실제 앱을 실행해 확인한다**

XcodeBuildMCP 또는 Xcode에서 앱을 실행한다.

확인할 것:

- 지도가 보인다.
- 첫 탭 후 출발 마커가 보인다.
- 두 번째 탭 후 도착 마커가 보인다.
- 경로선은 직선이 아니라 실제 도보 경로 형상을 따른다.
- 출발/도착 마커가 경로선에 가려지지 않는다.
- 거리 패널이 표시된다.
- 경로 실패 시 직선 대체 경로를 그리지 않는다.

---

### Task 7: 전체 검증과 정리

**Files:**
- Modify if needed: files changed by prior tasks only

- [ ] **Step 1: 전체 테스트를 실행한다**

Run:

```bash
xcodebuild test -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 2: SwiftLint를 실행한다**

Run:

```bash
swiftlint
```

Expected: no errors.

- [ ] **Step 3: 상태를 확인한다**

Run:

```bash
git status --short
```

Expected: 의도한 구현 파일, 테스트 파일, 문서 파일만 변경됨.

- [ ] **Step 4: 사용자가 커밋을 요청한 경우에만 명시적 경로로 stage/commit한다**

Run only after user asks for a commit:

```bash
git add docs/superpowers/specs/2026-06-17-route-planner-mvp-design.md
git add docs/superpowers/plans/2026-06-17-route-planner-mvp.md
git add docs/agent-rules/authoring.md
git add docs/agent-rules/project-decisions.md
git add Trace/App/DependencyContainer.swift
git add Trace/Features/RoutePlanner/Domain/PlannedRoute.swift
git add Trace/Features/RoutePlanner/Domain/RoutePlanningService.swift
git add Trace/Features/RoutePlanner/Infrastructure/MapKitRoutePlanningService.swift
git add Trace/Features/RoutePlanner/Presentation/RoutePlannerView.swift
git add Trace/Features/RoutePlanner/Presentation/RoutePlannerViewModel.swift
git add Trace/TraceApp.swift
git add Trace/ContentView.swift
git add TraceTests/TraceTests.swift
git add TraceUITests/TraceUITests.swift
git commit -m "feat: 러닝 코스 계획 MVP 추가"
```

Expected: commit succeeds only on feature branch, not on `main`.

---

## 자체 검토

- 스펙의 핵심 요구사항인 "직선 대체 금지"는 `MapKitRoutePlanningService`와 실패 상태 테스트에 반영했다.
- 포트/어댑터 구조는 `RoutePlanningService`와 `MapKitRoutePlanningService`, `UITestingRoutePlanningService`로 분리했다.
- UI 테스트는 실제 사용자처럼 지도 영역을 두 번 탭하고 거리/에러 상태를 확인한다.
- 실제 `MapKit` E2E는 흔들리는 필수 게이트로 두지 않고 수동 스모크 검증으로 분리했다.
- 계획 문서에 미완성 표시나 빈 구현 지시를 남기지 않았다.
