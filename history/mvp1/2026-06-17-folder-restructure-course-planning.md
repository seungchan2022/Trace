# 폴더 구조 개편: CoursePlanning 도메인 정렬 Implementation Plan

**Goal:** 라우트 플래너 MVP 코드를 `architecture.md`/`project-decisions.md`가 정한 새 구조
(`Domain` / `Infrastructure` / `Pages` 레이어 + `CoursePlanning` 네이밍)로 이동·rename한다.

**Architecture:** page-first MVVM + Clean Architecture 경계. Xcode 프로젝트는
`PBXFileSystemSynchronizedRootGroup`이라 파일 이동만으로 자동 반영된다(pbxproj 수동 수정 불필요).
소스는 아직 git 미추적이므로 `git mv`가 아닌 일반 파일 작성/삭제로 옮긴다.

## 파일·타입 매핑

| 현재 (구버전) | 목표 (새 구조) |
|---|---|
| `Shared/Routing/PlannedRoute.swift` → `PlannedRoute` | `Domain/CoursePlanning/Entity/PlannedCourse.swift` → `PlannedCourse` |
| `Shared/Routing/RouteCoordinate.swift` → `RouteCoordinate` | `Domain/CoursePlanning/Entity/CourseCoordinate.swift` → `CourseCoordinate` |
| `Shared/Routing/RoutePlanningService.swift` → `RoutePlanningService` + `RoutePlanningError` | `Domain/CoursePlanning/Protocol/CoursePlanningServiceProtocol.swift` + `Domain/CoursePlanning/CoursePlanningError.swift` |
| `Services/Routing/MapKit/MapKitRoutePlanningService.swift` → `MapKitRoutePlanningService` | `Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift` → `MapKitCoursePlanningService` |
| `Features/RoutePlanner/Presentation/RoutePlannerView.swift` → `RoutePlannerView` | `Pages/CoursePlannerPage/CoursePlannerPage.swift` → `CoursePlannerPage` |
| `Features/RoutePlanner/Presentation/RoutePlannerViewModel.swift` → `RoutePlannerViewModel` | `Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift` → `CoursePlannerPageViewModel` |
| `App/DependencyContainer.swift` | 위치 유지, 식별자 rename |

식별자: `routePlanningService` → `coursePlanningService`, 프로퍼티 `route` → `course`,
`calculateRoute()` → `calculateCourse()`, accessibilityId `routePlanner.*` → `coursePlanner.*`.
메서드 `route(from:to:)`와 launch argument `-traceRouteFailure`/`-traceUITesting`은 동작 의미라 유지.

## Tasks

- [x] **Task 1: Domain 레이어 작성** — `Entity/PlannedCourse.swift`, `Entity/CourseCoordinate.swift`, `Protocol/CoursePlanningServiceProtocol.swift`, `CoursePlanningError.swift`
- [x] **Task 2: Infrastructure 레이어 작성** — `Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift`
- [x] **Task 3: Pages 레이어 작성** — `Pages/CoursePlannerPage/CoursePlannerPage.swift`, `CoursePlannerPageViewModel.swift`
- [x] **Task 4: App/진입점 갱신** — `DependencyContainer.swift`, `TraceApp.swift`, `ContentView.swift`
- [x] **Task 5: 테스트 타겟 rename** — `TraceTests`, `TraceUITests`
- [x] **Task 6: 옛 디렉터리 삭제** — `Shared/Routing`, `Services`, `Features`
- [x] **Task 7: spec 문서 정합화** — `docs/superpowers/specs/2026-06-17-route-planner-mvp-design.md`를 새 구조/네이밍으로
- [x] **Task 8: 빌드 + 테스트 검증** — 빌드 ✅, 단위 테스트 3/3 통과 ✅ (`** TEST SUCCEEDED **`, iPhone 16 시뮬레이터)

커밋은 Trace 규칙상 사용자가 요청할 때만 한다.
