# MVP10 제스처 정합성 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 탭 즉시 확정을 "0.35초 보류 → 확정/취소"로 교체해 더블탭·원핑거 줌과 분리하고, 그리기 시작점 근접 판정에 화면 24pt 기준을 추가하며, 그리기 모드 두손가락 제스처 경쟁을 delegate로 조정한다.

**Architecture:** 순수 Swift 상태 머신 `TapClassifier`(시간 주입, UIKit 비의존)가 판별을 담당하고, `MapViewRepresentable.Coordinator`가 원시 터치 관찰 GR + 기존 탭 GR로 이벤트를 공급한다. ViewModel은 보류/확정/취소 3신호만 받는다(MapKit 비의존 유지). 스펙: `docs/superpowers/specs/2026-07-04-gesture-consistency-design.md` (문서 리뷰 반영 완료본).

**Tech Stack:** Swift 6 (async/await, `@MainActor`), iOS 17+ Observation(`@Observable`), UIKit 제스처(MKMapView), XCTest.

## Global Constraints

- 강제 언랩/강제 캐스트/강제 try 금지 — swiftlint 에러 + pre-commit 훅이 차단.
- ViewModel은 MapKit/UIKit을 import하지 않는다 (CoreGraphics의 `CGPoint`는 TapClassifier 한정, ViewModel 금지).
- 새 `.swift` 파일은 해당 폴더에 생성만 하면 됨 — 프로젝트가 `PBXFileSystemSynchronizedRootGroup`(폴더 동기화)라 pbxproj 수정 불필요.
- 시뮬레이터: 세션 시작 시 iOS 26.5 iPhone UDID 하나를 고정(`xcrun simctl list devices available | grep iPhone`), 이후 절대 변경 금지. 테스트는 raw `xcodebuild ... -parallel-testing-enabled NO test`로만 실행 (XcodeBuildMCP 테스트 툴 금지). `docs/agent-rules/testing.md`.
- 각 태스크의 커밋 전: 빌드/테스트/린트 3종 통과 후 `.git/trace-verify-{build,test,lint}.ok` 스탬프 생성 (pre-commit 훅 요건).
- 커밋은 `scripts/trace-commit.sh -m "tag: 한국어 제목\n\n- 본문 3~4줄" -- <경로들>`로 경로 명시 스테이징. `git push` 금지.
- 검증 명령 (UDID는 고정값 사용):
  - 빌드: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build`
  - 테스트: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test`
  - 린트: `swiftlint`

---

### Task 1: TapClassifier 상태 머신 (마일스톤 1 핵심 로직, TDD)

**Files:**
- Create: `Trace/Pages/CoursePlannerPage/TapClassifier.swift`
- Test: `TraceTests/TapClassifierTests.swift`

**Interfaces:**
- Consumes: 없음 (순수 Swift, `Foundation` + `CoreGraphics`만 import)
- Produces: `TapClassifierEvent` enum(`.pending(CGPoint)`/`.confirmed(CGPoint)`/`.cancelled`)과 `TapClassifier` 클래스 — `tapEnded(at:time:)`, `touchBegan(at:time:)`, `windowElapsed(time:)`, `reset()` 각각 `[TapClassifierEvent]` 반환, `var window: TimeInterval`, `var sameSpotRadius: CGFloat`, `var hasPending: Bool`. Task 3의 Coordinator가 이 시그니처 그대로 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import Trace

final class TapClassifierTests: XCTestCase {
    private let p1 = CGPoint(x: 100, y: 100)
    private let near = CGPoint(x: 110, y: 110)   // 40pt 이내
    private let far = CGPoint(x: 300, y: 300)    // 40pt 밖

    func testSingleTapConfirmsAfterWindow() {
        let sut = TapClassifier()
        XCTAssertEqual(sut.tapEnded(at: p1, time: 0), [.pending(p1)])
        XCTAssertEqual(sut.windowElapsed(time: 0.36), [.confirmed(p1)])
        XCTAssertFalse(sut.hasPending)
    }

    func testWindowNotElapsedYieldsNothing() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        XCTAssertEqual(sut.windowElapsed(time: 0.2), [])
        XCTAssertTrue(sut.hasPending)
    }

    func testDoubleTapCancelsAndSwallowsSecondTap() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        XCTAssertEqual(sut.touchBegan(at: near, time: 0.15), [.cancelled])
        XCTAssertEqual(sut.tapEnded(at: near, time: 0.2), [])   // 더블탭의 두 번째 탭은 삼킴
        XCTAssertEqual(sut.windowElapsed(time: 0.4), [])        // 잔여 타이머 발화는 무해
    }

    func testOneFingerZoomCancelsWithoutTapCompletion() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        XCTAssertEqual(sut.touchBegan(at: near, time: 0.15), [.cancelled])
        // 두 번째 터치는 드래그로 끝나 tapEnded가 안 옴 — 이후 탭은 정상 동작
        XCTAssertEqual(sut.touchBegan(at: far, time: 2.0), [])
        XCTAssertEqual(sut.tapEnded(at: far, time: 2.1), [.pending(far)])
    }

    func testFarQuickSecondTapConfirmsFirstEarly() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        // 다른 위치 빠른 연속 탭 → 첫 탭 조기 확정, 둘 다 포인트가 된다 (기존 회귀 케이스)
        XCTAssertEqual(sut.touchBegan(at: far, time: 0.15), [.confirmed(p1)])
        XCTAssertEqual(sut.tapEnded(at: far, time: 0.2), [.pending(far)])
    }

    func testResetCancelsPendingOnce() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        XCTAssertEqual(sut.reset(), [.cancelled])
        XCTAssertEqual(sut.reset(), [])
    }

    func testLateTouchAfterWindowConfirmsPending() {
        let sut = TapClassifier()
        _ = sut.tapEnded(at: p1, time: 0)
        // 창이 지났는데 타이머보다 터치가 먼저 온 경합 → 확정 처리
        XCTAssertEqual(sut.touchBegan(at: near, time: 0.5), [.confirmed(p1)])
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test 2>&1 | tail -20`
Expected: 컴파일 실패 — `cannot find 'TapClassifier' in scope`

- [ ] **Step 3: 최소 구현**

```swift
import CoreGraphics
import Foundation

/// 탭 판별기 이벤트 — View(Coordinator)가 배열 순서대로 처리한다.
enum TapClassifierEvent: Equatable {
    case pending(CGPoint)    // 첫 탭 업: 보류 시작 (임시 마커 표시)
    case confirmed(CGPoint)  // 판별 창 통과: 싱글탭 확정
    case cancelled           // 더블탭류(더블탭/원핑거 줌)로 판명: 보류 취소
}

/// "탭 즉시 확정"을 "보류 → 확정/취소"로 바꾸는 순수 상태 머신.
/// require(toFail:)는 즉시 보류 신호를 못 내고, 탭 GR+타이머는 원핑거 줌의 두 번째 터치를
/// 못 보므로 원시 터치 관찰이 필수 (스펙 '구조' 절). 시간 주입으로 유닛 테스트한다.
final class TapClassifier {
    // 판별 창 — 내장 더블탭 창보다 크거나 같게 실기기 튜닝
    var window: TimeInterval = 0.35
    // "같은 자리" 반경 — 기존 디바운스 40pt 승계
    var sameSpotRadius: CGFloat = 40

    private var pendingPoint: CGPoint?
    private var pendingTime: TimeInterval?
    // 보류를 취소시킨 두 번째 터치가 탭으로 완성되면 그 탭을 삼킨다 (더블탭의 두 번째 탭)
    private var swallowNextTap = false

    var hasPending: Bool { pendingPoint != nil }

    func tapEnded(at point: CGPoint, time: TimeInterval) -> [TapClassifierEvent] {
        if swallowNextTap {
            swallowNextTap = false
            return []
        }
        pendingPoint = point
        pendingTime = time
        return [.pending(point)]
    }

    func touchBegan(at point: CGPoint, time: TimeInterval) -> [TapClassifierEvent] {
        // 새 터치 시작은 이전 삼킴 예약을 무효화 (드래그로 끝난 원핑거 줌 뒤 정상 복귀)
        swallowNextTap = false
        guard let pending = pendingPoint, let started = pendingTime else { return [] }
        if time - started >= window {
            return finishPending(with: .confirmed(pending))
        }
        if hypot(point.x - pending.x, point.y - pending.y) <= sameSpotRadius {
            // 같은 자리 두 번째 터치 = 더블탭 or 원핑거 줌 시작 → 취소
            swallowNextTap = true
            return finishPending(with: .cancelled)
        }
        // 먼 곳 터치 → 이 보류는 더블탭이 될 수 없음 → 조기 확정
        return finishPending(with: .confirmed(pending))
    }

    func windowElapsed(time: TimeInterval) -> [TapClassifierEvent] {
        guard let pending = pendingPoint, let started = pendingTime,
              time - started >= window else { return [] }
        return finishPending(with: .confirmed(pending))
    }

    func reset() -> [TapClassifierEvent] {
        swallowNextTap = false
        guard pendingPoint != nil else { return [] }
        return finishPending(with: .cancelled)
    }

    private func finishPending(with event: TapClassifierEvent) -> [TapClassifierEvent] {
        pendingPoint = nil
        pendingTime = nil
        return [event]
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: 위 테스트 명령 재실행
Expected: `TapClassifierTests` 7개 전부 PASS (기존 스위트도 전부 PASS)

- [ ] **Step 5: 린트/빌드 확인 후 커밋**

```bash
swiftlint && touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "feat: 탭 판별기 상태 머신 추가

- 탭 즉시 확정을 보류-확정/취소로 바꾸는 TapClassifier를 추가한다
- 더블탭/원핑거 줌/조기 확정/삼킴 케이스를 시간 주입으로 테스트한다
- View 배선은 다음 태스크에서 연결한다" -- Trace/Pages/CoursePlannerPage/TapClassifier.swift TraceTests/TapClassifierTests.swift
```
(빌드·테스트는 Step 2/4에서 실제 실행했으므로 스탬프 생성이 정당함. 실행 안 했으면 생성 금지.)

---

### Task 2: ViewModel 보류 신호 API (TDD)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`
- Test: `TraceTests/CoursePlannerViewModelTests.swift` (케이스 추가)

**Interfaces:**
- Consumes: 기존 `handleMapTap(at:hitPin:)`, `interactionMode`, `toggleDrawingMode()`
- Produces: `private(set) var pendingTapMarker: CourseCoordinate?`, `func pendingTapBegan(at coordinate: CourseCoordinate, hitPin: CoursePinRole?)`, `func pendingTapCancelled()` — Task 3의 Page 바인딩과 mapPins가 사용.

- [ ] **Step 1: 실패하는 테스트 작성** — `CoursePlannerViewModelTests.swift`에 추가 (기존 파일의 스텁 서비스/헬퍼 패턴을 그대로 따를 것):

```swift
func testPendingTapShowsMarkerOnlyWhenNoPinHit() {
    let sut = makeSUT()   // 기존 테스트 헬퍼 사용
    sut.pendingTapBegan(at: CourseCoordinate(latitude: 37.5, longitude: 127.0), hitPin: nil)
    XCTAssertNotNil(sut.pendingTapMarker)
    sut.pendingTapBegan(at: CourseCoordinate(latitude: 37.5, longitude: 127.0), hitPin: .start)
    XCTAssertNil(sut.pendingTapMarker)   // 핀 위 탭은 임시 마커 없음
}

func testPendingTapIgnoredInDrawMode() async {
    let sut = makeSUT()
    await sut.toggleDrawingMode()   // .tap → .draw
    sut.pendingTapBegan(at: CourseCoordinate(latitude: 37.5, longitude: 127.0), hitPin: nil)
    XCTAssertNil(sut.pendingTapMarker)
}

func testPendingTapCancelledClearsMarker() {
    let sut = makeSUT()
    sut.pendingTapBegan(at: CourseCoordinate(latitude: 37.5, longitude: 127.0), hitPin: nil)
    sut.pendingTapCancelled()
    XCTAssertNil(sut.pendingTapMarker)
}

func testHandleMapTapClearsMarkerOnSuccessAndFailure() async {
    // 성공 경로: 확정 흐름이 끝나면 마커 제거
    let sut = makeSUT()
    sut.pendingTapBegan(at: CourseCoordinate(latitude: 37.5, longitude: 127.0), hitPin: nil)
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.6, longitude: 127.0))
    XCTAssertNil(sut.pendingTapMarker)
    // 실패 경로: 라우팅 실패해도 유령 마커가 남지 않음 (기존 실패 스텁 헬퍼 사용)
    let failing = makeSUT(routeResult: .failure(CoursePlanningError.routeNotFound))
    failing.pendingTapBegan(at: CourseCoordinate(latitude: 37.5, longitude: 127.0), hitPin: nil)
    await failing.handleMapTap(at: CourseCoordinate(latitude: 37.5, longitude: 127.0))
    await failing.handleMapTap(at: CourseCoordinate(latitude: 37.6, longitude: 127.0))
    XCTAssertNil(failing.pendingTapMarker)
}

func testToggleDrawingModeClearsPendingMarker() async {
    let sut = makeSUT()
    sut.pendingTapBegan(at: CourseCoordinate(latitude: 37.5, longitude: 127.0), hitPin: nil)
    await sut.toggleDrawingMode()
    XCTAssertNil(sut.pendingTapMarker)
}
```

(`makeSUT` 시그니처는 기존 테스트 파일의 실제 헬퍼에 맞춰 조정. 실패 스텁이 없으면 기존 스텁 서비스에 실패 케이스 파라미터를 추가.)

- [ ] **Step 2: 테스트 실패 확인** — 컴파일 실패 (`pendingTapMarker` 없음) 예상.

- [ ] **Step 3: 최소 구현** — `CoursePlannerPageViewModel.swift`:

`pendingTapStart` 선언 아래에 추가:

```swift
// Tap mode: 판별 창(0.35s) 통과를 기다리는 보류 탭 — 임시 마커 표시용.
// 수명: 보류~확정 흐름 종료(성공/실패/정보 경로)까지. 스펙 '임시 마커' 절.
private(set) var pendingTapMarker: CourseCoordinate?

func pendingTapBegan(at coordinate: CourseCoordinate, hitPin: CoursePinRole?) {
    guard interactionMode == .tap else { return }
    pendingTapMarker = hitPin == nil ? coordinate : nil
}

func pendingTapCancelled() {
    pendingTapMarker = nil
}
```

`handleMapTap` 첫 guard 바로 다음에 추가 (async 함수의 defer는 라우팅 await 완료 후 실행되므로, 성공·실패·정보 경로 전부에서 "흐름이 끝난 시점"에 마커가 제거된다):

```swift
defer { pendingTapMarker = nil }
```

`toggleDrawingMode()`의 `.tap` 분기(→ draw 진입)에 `pendingTapMarker = nil` 추가.

- [ ] **Step 4: 테스트 통과 확인** — 신규 5개 + 기존 전체 PASS.

- [ ] **Step 5: 린트 후 커밋**

```bash
swiftlint && touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "feat: 보류 탭 마커 상태를 ViewModel에 추가

- 보류/취소 신호를 받는 pendingTapBegan/Cancelled를 추가한다
- handleMapTap 종료 시(성공·실패·정보 경로) 마커를 defer로 제거한다
- 모드 전환 시 보류 마커를 정리한다" -- Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift TraceTests/CoursePlannerViewModelTests.swift
```

---

### Task 3: View 배선 — 원시 터치 관찰 + 판별기 연결 (마일스톤 1 완성)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift`

**Interfaces:**
- Consumes: Task 1 `TapClassifier`/`TapClassifierEvent`, Task 2 `pendingTapBegan/pendingTapCancelled/pendingTapMarker`
- Produces: `MapViewRepresentable`에 `var onPendingTap: ((CourseCoordinate, CoursePinRole?) -> Void)?`, `var onPendingTapCancelled: (() -> Void)?` 추가 (`onMapTap` 시그니처는 불변 — 확정 신호로 의미만 변경).

- [ ] **Step 1: TouchObserverGestureRecognizer 추가** — `MapViewRepresentable.swift`의 Coordinator 정의 아래에:

```swift
// 원시 터치 다운만 관찰해 탭 판별기에 공급한다. 절대 인식 상태로 전이하지 않으므로
// 네이티브 줌을 포함한 다른 인식기를 방해하지 않는다 (스펙 '구조' 절: 관찰 필수 근거).
final class TouchObserverGestureRecognizer: UIGestureRecognizer {
    var onTouchBegan: ((CGPoint) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        onTouchBegan?(touch.location(in: view))
    }
}
```

- [ ] **Step 2: Coordinator에 판별기 배선** — 기존 `lastTapTime`/`lastTapPoint` 디바운스 필드와 `handleTap`의 디바운스 블록(주석 포함)을 **삭제**하고 대체:

```swift
// MARK: Tap Classification

let tapClassifier = TapClassifier()
weak var touchObserverRecognizer: TouchObserverGestureRecognizer?
private var confirmWorkItem: DispatchWorkItem?
// 보류 시점에 좌표·핀 히트를 동봉해 확정 시 그대로 사용 (판별 창 중 지도 이동에 안전)
private var pendingCoordinate: CourseCoordinate?
private var pendingPinRole: CoursePinRole?

@objc func handleTap(_ recognizer: UITapGestureRecognizer) {
    guard let mapView = recognizer.view as? MKMapView else { return }
    let point = recognizer.location(in: mapView)
    process(tapClassifier.tapEnded(at: point, time: CACurrentMediaTime()), in: mapView)
}

func observedTouchBegan(at point: CGPoint, in mapView: MKMapView) {
    process(tapClassifier.touchBegan(at: point, time: CACurrentMediaTime()), in: mapView)
}

func resetTapClassification(in mapView: MKMapView) {
    process(tapClassifier.reset(), in: mapView)
}

private func process(_ events: [TapClassifierEvent], in mapView: MKMapView) {
    for event in events {
        switch event {
        case .pending(let point):
            let clCoord = mapView.convert(point, toCoordinateFrom: mapView)
            pendingCoordinate = CourseCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude)
            pendingPinRole = pinHit(at: point, in: mapView)
            if let coordinate = pendingCoordinate {
                parent.onPendingTap?(coordinate, pendingPinRole)
            }
            scheduleConfirm(in: mapView)
        case .cancelled:
            confirmWorkItem?.cancel()
            confirmWorkItem = nil
            pendingCoordinate = nil
            pendingPinRole = nil
            parent.onPendingTapCancelled?()
        case .confirmed:
            confirmWorkItem?.cancel()
            confirmWorkItem = nil
            guard let coordinate = pendingCoordinate else { break }
            let role = pendingPinRole
            pendingCoordinate = nil
            pendingPinRole = nil
            parent.onMapTap?(coordinate, role)
        }
    }
}

private func scheduleConfirm(in mapView: MKMapView) {
    confirmWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self, weak mapView] in
        guard let self, let mapView else { return }
        self.process(self.tapClassifier.windowElapsed(time: CACurrentMediaTime()), in: mapView)
    }
    confirmWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + tapClassifier.window, execute: item)
}
```

주의: `.confirmed(let point)`의 point는 사용하지 않는다 — 좌표는 보류 시점에 이미 변환·저장했다(지도 이동 안전). `case .confirmed:`로 바인딩 없이 매칭.

- [ ] **Step 3: makeUIView/updateUIView 배선** — `makeUIView`의 tapGR 추가 직후에:

```swift
let touchObserver = TouchObserverGestureRecognizer()
touchObserver.cancelsTouchesInView = false
touchObserver.delaysTouchesBegan = false
touchObserver.onTouchBegan = { [weak coordinator = context.coordinator, weak mapView] point in
    guard let coordinator, let mapView else { return }
    coordinator.observedTouchBegan(at: point, in: mapView)
}
touchObserver.isEnabled = !isDrawingMode
mapView.addGestureRecognizer(touchObserver)
context.coordinator.touchObserverRecognizer = touchObserver
```

(`makeUIView`에서 `let mapView`는 클로저 캡처를 위해 `weak` 참조 — GR가 mapView에 붙어 순환 참조 방지.)

`updateUIView`의 모드 전환 블록(`if wasDrawing != isDrawingMode`)에 두 줄 추가:

```swift
context.coordinator.touchObserverRecognizer?.isEnabled = !isDrawingMode
context.coordinator.resetTapClassification(in: uiView)   // 판별 창 중 모드 전환 → 보류 취소
```

`MapViewRepresentable` 프로퍼티에 콜백 2개 추가 (`onMapTap` 선언 옆):

```swift
var onPendingTap: ((CourseCoordinate, CoursePinRole?) -> Void)?
var onPendingTapCancelled: (() -> Void)?
```

- [ ] **Step 4: Page 바인딩 + 임시 핀** — `CoursePlannerPage.swift`의 `MapViewRepresentable(...)` 호출에 추가:

```swift
onMapTap: { coord, hitPin in Task { await viewModel.handleMapTap(at: coord, hitPin: hitPin) } },
onPendingTap: { coord, hitPin in viewModel.pendingTapBegan(at: coord, hitPin: hitPin) },
onPendingTapCancelled: { viewModel.pendingTapCancelled() }
```

`mapPins`의 `pendingTapStart` 블록 다음에 추가:

```swift
// 판별 창 보류 중 임시 마커 — 확정이 수렴하는 모양(첫 탭=출발, 이후=도착)과 동일 (스펙 '임시 마커' 절)
if viewModel.interactionMode == .tap, let pending = viewModel.pendingTapMarker {
    let isFirstPoint = viewModel.course == nil && viewModel.pendingTapStart == nil
    pins.append(MapPin(
        coordinate: CLLocationCoordinate2D(latitude: pending.latitude, longitude: pending.longitude),
        title: isFirstPoint ? "출발" : "도착",
        color: isFirstPoint ? .systemGreen : .systemRed,
        systemImage: isFirstPoint ? "figure.run" : "flag.checkered",
        role: .pendingStart
    ))
}
```

- [ ] **Step 5: 빌드 + 전체 테스트 + 시뮬레이터 스모크**

Run: 빌드/테스트 명령 (Global Constraints). Expected: PASS.
시뮬레이터 스모크(XcodeBuildMCP `build_run_sim` — 테스트 툴 아님): 탭 → 마커 즉시 표시 → ~1초 내 경로 계산 확인. 빠른 연속 두 지점 탭 → 두 포인트 모두 생성 확인.
(더블탭 줌·원핑거 줌 취소는 시뮬레이터 재현이 불안정 — 실기기 QA 항목, Task 6 체크리스트로.)

- [ ] **Step 6: 커밋**

```bash
swiftlint && touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "feat: 탭 보류 확정 배선 — 더블탭/원핑거 줌과 분리

- 원시 터치 관찰 GR와 TapClassifier를 Coordinator에 연결한다
- 기존 시간+거리 자체 디바운스를 판별기로 대체 삭제한다
- 보류 중 임시 마커(출발/도착 모양)를 Page 핀에 추가한다
- pinHit는 탭 시점에 판정해 확정 시 재사용한다" -- Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift
```

---

### Task 4: 그리기 시작점 화면 24pt 판정 + 20m 폴백 (마일스톤 2, TDD)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift:206-237` (`appendStroke`, `snappedStrokeStart`)
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` (`onStrokeEnded` 시그니처, `handleDraw`)
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift` (바인딩)
- Test: `TraceTests/CoursePlannerViewModelTests.swift`

**Interfaces:**
- Consumes: 기존 `CourseEditSession.connectionThresholdMeters`, `pinHit(at:in:)`
- Produces: `onStrokeEnded: ([CourseCoordinate], CoursePinRole?) -> Void` (힌트 추가), `func appendStroke(_ stroke: [CourseCoordinate], startPinHit: CoursePinRole? = nil) async`

- [ ] **Step 1: 실패하는 테스트 작성** — 기존 appendStroke 테스트 패턴을 따라 추가:

```swift
func testStrokeStartSnapsToPinHitRegardlessOfDistance() async {
    // 코스 생성 후, 힌트 .start로 그리기 시작 — 실거리 20m 밖이어도 출발 좌표로 치환되어
    // 반전 prepend(attach 규칙 3)가 성립해야 한다
    let sut = makeSUT()
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
    let strokeStart = CourseCoordinate(latitude: 37.5004, longitude: 127.00)   // 출발점에서 ~44m
    await sut.appendStroke([strokeStart, CourseCoordinate(latitude: 37.49, longitude: 127.00)],
                           startPinHit: .start)
    guard let course = sut.course else { return XCTFail("코스 없음") }
    XCTAssertEqual(course.coordinates.first?.latitude, 37.49)   // 출발 방향 연장(prepend) 성립
}

func testStrokeStartFallsBackToRealDistanceWithoutHint() async {
    // 힌트 없음 + 실거리 20m 이내 → 기존 폴백 동작 유지 (도착점 치환 append)
    let sut = makeSUT()
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.50, longitude: 127.00))
    await sut.handleMapTap(at: CourseCoordinate(latitude: 37.51, longitude: 127.00))
    let nearEnd = CourseCoordinate(latitude: 37.51009, longitude: 127.00)      // 도착점에서 ~10m
    await sut.appendStroke([nearEnd, CourseCoordinate(latitude: 37.52, longitude: 127.00)],
                           startPinHit: nil)
    guard let course = sut.course else { return XCTFail("코스 없음") }
    XCTAssertEqual(course.coordinates.last?.latitude, 37.52)
    XCTAssertEqual(course.segments.count, 2)   // gap 라우팅 없이 이어붙음
}
```

(좌표·검증값은 기존 appendStroke 테스트 헬퍼/스텁의 라우팅 동작에 맞춰 조정. 핵심 어서션: 힌트가 거리와 무관하게 치환하고, 힌트 없으면 20m 폴백이 살아 있다.)

- [ ] **Step 2: 테스트 실패 확인** — `startPinHit` 파라미터 없음, 컴파일 실패.

- [ ] **Step 3: ViewModel 구현** — `appendStroke`/`snappedStrokeStart` 교체:

```swift
func appendStroke(_ stroke: [CourseCoordinate], startPinHit: CoursePinRole? = nil) async {
    infoMessage = nil
    guard stroke.count >= 2 else { return }
    recomputeGeneration += 1
    let generation = recomputeGeneration
    try? await Task.sleep(nanoseconds: 300_000_000)
    guard generation == recomputeGeneration else { isLoading = false; return }
    await routeStrokeAndAttach(stroke, startPinHit: startPinHit, generation: generation)
}

// 시작점 치환: 화면 24pt 핀 히트(줌 무관 시각 근접) 우선, 실거리 20m 폴백(고배율 줌인에서
// 24pt < 20m인 구간을 커버 — 문서 리뷰 2026-07-04). 치환이 없으면 도로 스냅 드리프트로
// attach 근접 판정이 깨진다 (기존 주석의 원 문제).
private func snappedStrokeStart(
    _ sampled: [CourseCoordinate], startPinHit: CoursePinRole?
) -> CourseCoordinate? {
    guard let course = session.course,
          let existingStart = course.coordinates.first,
          let existingEnd = course.coordinates.last,
          let first = sampled.first else { return nil }
    switch startPinHit {
    case .end, .merged: return existingEnd
    case .start: return existingStart
    case .pendingStart, nil: break
    }
    let threshold = CourseEditSession.connectionThresholdMeters
    if first.distanceMeters(to: existingEnd) <= threshold { return existingEnd }
    if first.distanceMeters(to: existingStart) <= threshold { return existingStart }
    return nil
}
```

`routeStrokeAndAttach` 시그니처에 `startPinHit: CoursePinRole?` 추가, 내부의 `if let snappedStart = snappedStrokeStart(sampled)`를 `if let snappedStart = snappedStrokeStart(sampled, startPinHit: startPinHit)`로 교체.

- [ ] **Step 4: View 힌트 배관** — `MapViewRepresentable.swift`:

`onStrokeEnded` 선언을 `var onStrokeEnded: ([CourseCoordinate], CoursePinRole?) -> Void`로 변경.

Coordinator에 `private var strokeStartPinRole: CoursePinRole?` 추가. `handleDraw`:

- `.began` 분기 시작에: 
  ```swift
  if recognizer.state == .began {
      let hit = pinHit(at: point, in: mapView)
      strokeStartPinRole = hit == .pendingStart ? nil : hit   // 출발/도착/병합 핀만 유효
  }
  ```
  (`.began`과 `.changed`가 같은 case이므로 state 검사로 시작 시점만 캡처. 두 핀이 다 24pt 이내면 `pinHit`의 최근접 우선이 그대로 적용됨.)
- 멀티터치 취소 블록(`numberOfTouches > 1`)에 `strokeStartPinRole = nil` 추가.
- `.ended, .cancelled` 분기의 `parent.onStrokeEnded(stroke)`를:
  ```swift
  let startHit = strokeStartPinRole
  strokeStartPinRole = nil
  if stroke.count >= 2 {
      parent.onStrokeEnded(stroke, startHit)
  }
  ```

`CoursePlannerPage.swift` 바인딩:

```swift
onStrokeEnded: { stroke, startHit in Task { await viewModel.appendStroke(stroke, startPinHit: startHit) } },
```

- [ ] **Step 5: 테스트 통과 + 전체 검증** — 신규 2개 + 기존 전체 PASS, 빌드/린트 PASS.

- [ ] **Step 6: 커밋**

```bash
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "feat: 그리기 시작점 판정을 화면 24pt 우선 + 20m 폴백으로

- 그리기 시작 시점에 핀 히트(24pt)를 잡아 스트로크와 함께 전달한다
- 힌트가 있으면 거리와 무관하게 핀 좌표로 치환한다 (줌아웃 51m 문제 해결)
- 실거리 20m 판정은 폴백으로 유지해 고배율 줌인 회귀를 막는다" -- Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift TraceTests/CoursePlannerViewModelTests.swift
```

---

### Task 5: 두손가락 제스처 delegate 조정 (마일스톤 3)

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` (Coordinator delegate 채택, makeUIView)

**Interfaces:**
- Consumes: 기존 `twoFingerPanGestureRecognizer`, Task 3 `touchObserverRecognizer`
- Produces: 없음 (동작 변화만)

- [ ] **Step 1: delegate 구현** — Coordinator 선언을 `final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate`로 변경하고 추가:

```swift
// MARK: Gesture Delegate

func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
) -> Bool {
    // 커스텀 두손가락 팬 ↔ 네이티브 두손가락 탭 줌아웃 경쟁 완화: 동시 인식 허용.
    // 탭 줌아웃은 이동량이 없어 팬 로직에 영향이 없고, 실제 팬 중에는 탭 줌아웃이 스스로 실패한다.
    // 터치 관찰자는 인식 전이가 없어 항상 무해 — 명시적으로 허용해 둔다.
    gestureRecognizer === twoFingerPanGestureRecognizer
        || gestureRecognizer === touchObserverRecognizer
}
```

- [ ] **Step 2: makeUIView에서 delegate 지정** — twoFingerPanGR와 touchObserver 생성부에 각각 `.delegate = context.coordinator` 추가.

- [ ] **Step 3: 빌드 + 전체 테스트 PASS 확인.** 판정 감각은 시뮬레이터로 확인 불가 — 실기기 QA로 이관 (스펙: delegate 실험은 실기기 QA 1회분 한정, 미해소 시 백로그 기록 후 마일스톤 종료).

- [ ] **Step 4: 커밋**

```bash
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
scripts/trace-commit.sh -m "feat: 두손가락 팬과 네이티브 탭 줌아웃 동시 인식 허용

- Coordinator가 UIGestureRecognizerDelegate를 채택한다
- 커스텀 두손가락 팬의 동시 인식을 허용해 빠른 연속 조작 경쟁을 완화한다
- 최종 판정은 실기기 QA 1회분으로 확인한다" -- Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift
```

---

### Task 6: 최종 검증 + 실기기 QA 체크리스트 + 진행 기록

**Files:**
- Create: `docs/qa/2026-07-XX-gesture-consistency-device-checklist.md` (실행일 날짜로)
- Modify: `docs/roadmap.md` (MVP10 마일스톤 체크박스)

- [ ] **Step 1: 전체 검증 3종 재실행** (빌드/테스트/린트, Global Constraints 명령) — 전부 PASS 후 스탬프 갱신. `superpowers:verification-before-completion` 적용: 명령과 결과를 그대로 보고.

- [ ] **Step 2: 시뮬레이터 스모크** — 탭 2회(경로 생성), 빠른 연속 다른 위치 탭 2회(둘 다 포인트), 그리기 모드 전환 후 스트로크 1회, undo. 크래시·유령 마커 없음 확인.

- [ ] **Step 3: 실기기 QA 체크리스트 작성** — `docs/agent-rules/testing.md` 템플릿 기반. 핵심 기능 섹션에 스펙 동작 사양 표의 행을 그대로 옮긴다:

```markdown
## 핵심 기능 (손으로 수행)
- [ ] 싱글탭: 마커 즉시 표시 → 경로 계산 (체감 지연 없음)
- [ ] 더블탭: 줌인만 — 포인트 안 생김, 임시 마커 깜빡임 수용 가능한지 메모
- [ ] 탭 후 두 번째 터치 유지 상하 드래그: 원핑거 줌만 — 포인트 안 생김
- [ ] 경계 간격(~0.3–0.4초) 더블탭: 줌+포인트 동시 발생 없음
- [ ] 서로 다른 위치 빠른 연속 탭: 둘 다 포인트
- [ ] 출발핀 탭 왕복: 기존과 동일 동작
- [ ] 판별 창 중 모드 전환: 잔류 마커 없음
- [ ] 줌아웃 상태에서 핀 옆(화면상)에서 그리기 시작: 이어붙음 (51m 케이스 해결 확인)
- [ ] 고배율 줌인에서 핀 근처(실거리 20m 이내) 그리기 시작: 여전히 이어붙음 (폴백 확인)
- [ ] 두손가락 탭줌아웃 ↔ 두손가락 팬 빠른 연속: 각각 정상 동작
```

- [ ] **Step 4: roadmap.md 마일스톤 체크박스 갱신 + 문서 커밋** — `docs` 태그로 체크리스트·roadmap 커밋. 실기기 QA 결과는 사용자 수행 후 백로그/roadmap에 반영 (발견 버그는 같은 브랜치에서 수정, 개선 아이디어는 backlog로).

---

## Self-Review 체크 결과 (플랜 작성 시점)

- 스펙 커버리지: 마일스톤 1 → Task 1·2·3, 마일스톤 2 → Task 4, 마일스톤 3 → Task 5, 검증 절 → 각 태스크 Step + Task 6. 임시 마커 수명 규칙 → Task 2 defer + Task 3 임시 핀. 누락 없음.
- 플레이스홀더: 테스트 좌표/헬퍼는 "기존 파일 패턴에 맞춰 조정"으로 명시 위임 — 실제 파일을 읽는 구현자가 확정한다 (파일 전체를 플랜에 복사하는 것보다 드리프트 위험이 낮음).
- 타입 일관성: `TapClassifierEvent`/`TapClassifier` 시그니처가 Task 1 정의 = Task 3 사용 동일. `onStrokeEnded` 시그니처가 Task 4의 View/Page/VM 세 곳에서 동일. `pendingTapMarker`/`pendingTapBegan`/`pendingTapCancelled`가 Task 2 정의 = Task 3 사용 동일.
