# MVP16 draw-gesture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 그리기 모드의 제스처를 "한 손가락 = 항상 지도 이동, 그리기 = 롱프레스-드래그"로 개편해, 다음 그릴 곳을 찾으려 지도를 옮길 때 원치 않는 선이 그려지는 실사용 문제를 없앤다.

**Architecture:** 핵심은 **지도 스크롤 잠금의 소유권을 "모드 경계"에서 "스트로크 생명주기"로 옮기는 것**이다. 지금은 `updateUIView`의 `wasDrawing != isDrawingMode` 블록이 그리기 모드 진입 시 `isScrollEnabled = false`로 지도를 통째로 얼려버린다(그래서 한 손가락이 곧 그리기다). 개편 후 그리기 모드는 **두 하위 상태**를 갖는다 — *대기(지도 이동 가능, `isScrollEnabled = true`)* 와 *스트로크 진행 중(지도 고정, `isScrollEnabled = false`)*. 잠금은 롱프레스가 인식된 `.began` 시점에 걸고 `.ended`/`.cancelled`에서 푼다. 즉시 인식되던 `UIPanGestureRecognizer`(drawGR)는 `UILongPressGestureRecognizer`로 교체하는데, 롱프레스는 인식 후에도 손가락 이동에 따라 `.changed`를 계속 보내므로 **인식기 하나로 "꾹 누르기 + 드래그"를 모두 처리**할 수 있다(추가 인식기 불필요 → `require(toFail:)` 함정 회피).

**Tech Stack:** SwiftUI (iOS 17+), UIKit 제스처 인식기(`UILongPressGestureRecognizer`), MapKit(`MKMapView`), Swift 6(클래식 격리), XCTest, XcodeBuildMCP(시뮬레이터 검증)

**Specs:** `docs/superpowers/specs/2026-07-19-mvp16-ui-restructure-kickoff-design.md` §2.5 + `docs/superpowers/specs/2026-07-18-run-ui-restructure-direction.md` "항목 2"

**실행 브랜치:** `feature/mvp16-draw-gesture` (main에서 생성, 이미 존재)

---

## Global Constraints

- Swift 6 언어 모드, 격리 기본값은 클래식(기본 nonisolated + UI 타입만 명시 `@MainActor`) — 새 순수 타입에는 어노테이션을 붙이지 않는다 (`docs/agent-rules/project-decisions.md`).
- **실제 필요 없는 곳에 어노테이션/코드를 남기지 않는다** (추가·제거 양쪽 모두).
- 색·폰트는 `DesignToken`만 사용 (직접 `Color`/`Font` 리터럴 금지). — 이번 사이클은 시각 변경이 없어 해당 없음.
- ViewModel은 MapKit/UIKit을 import하지 않는다 (아키텍처 규칙). `CGPoint`는 `TapClassifier` 한정, ViewModel 금지.
- 시뮬레이터는 **하나만** 사용: iPhone 17 Pro / iOS 26.5 (UUID `D887D0A4-074C-4AFB-8D08-D87329D0EFD4`). 실패해도 다른 시뮬레이터로 전환하지 않는다.
- **스코프 경계:** 변경은 `MapViewRepresentable.swift`(+ 그 `Coordinator`)에 가둔다. ViewModel·저장 스키마·경로 계산 로직은 건드리지 않는다. `isDrawingMode`는 지금도 ViewModel에서 파생만 되고(`interactionMode == .draw`) 제스처 배선은 전부 representable 안에 있으므로 이 경계는 이미 성립한다.
- **금지:** `UITapGestureRecognizer.require(toFail:)`로 탭 충돌을 풀지 않는다 — 탭 위치를 구분하지 않아 서로 다른 두 지점의 정상 연속 탭까지 잡아먹는 회귀가 실측된 바 있다 (`docs/solutions/design-patterns/uikit-double-tap-require-to-fail-location-agnostic.md`).
- **탭 모드는 건드리지 않는다.** `tapGR`·`touchObserver`·`TapClassifier`는 그리기 모드에서 비활성이고 개편 후에도 그대로 비활성이다. 다만 Task 1·2가 이들의 공용 enable/disable 블록을 수정하므로 **탭 모드 회귀 검증(Task 3)이 필수**다.
- 검증 명령 (모든 태스크 공통):
  - 빌드: `xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" build`
  - 테스트: 같은 명령에 `-parallel-testing-enabled NO test` (병렬 금지 필수)
  - 린트: `swiftlint`
  - 각각 통과 후 `touch .git/trace-verify-build.ok` / `trace-verify-test.ok` / `trace-verify-lint.ok` (pre-commit 훅 요건)
- 커밋: `scripts/trace-commit.sh -m "<tag>: 한국어 제목" -- <paths>` — 경로 명시 스테이징, `git add -A` 금지. push 금지, `main` 직접 커밋 금지.
- 새 Swift 파일은 pbxproj 수정 불필요 — 프로젝트가 PBXFileSystemSynchronizedRootGroup(폴더 동기화) 방식이라 `Trace/`·`TraceTests/` 아래 파일은 자동 포함된다.

---

## 🚦 결정 게이트 (반증 조건 — 패치 금지선)

킥오프 §2.5가 못박은 조건을 이 플랜의 **중단 규칙**으로 승격한다:

> 배타 처리가 실기기에서 실패하면(꾹 누르는 동안·드래그 중 지도가 같이 움직이면) **A안 자체의 반증 조건**으로 취급.

**규칙:** Task 4 실기기 QA에서 "홀드/드래그 중 지도가 따라 움직인다"가 재현되면,
1. **먼저** Task 1 Step 1에서 정의한 임계값 두 개(`minimumPressDuration`, `allowableMovement`)를 **정해진 범위 안에서만** 조정해 재시도한다 (범위: 아래 Task 4 시나리오 4 참고).
2. 그 범위 안에서 해결되지 않으면 **거기서 멈춘다.** 인식기를 추가하거나 delegate 규칙을 더 쌓지 않는다. A안 반증으로 기록하고 `docs/backlog.md`에 설계 재검토 항목으로 올린 뒤 사용자에게 보고한다.

**근거:** 직전 `landscape-sheet-overflow` 사이클에서 회귀를 패치로 쫓다가 플랜이 명시적으로 범위 밖이라 못박아둔 영역까지 들어갔고, 마무리 메모의 결론은 "원래 YAGNI 경계가 맞았다"였다. 같은 실패 모드를 이번엔 플랜 텍스트로 차단한다.

---

## 검증 현실 (정직하게)

이 사이클의 성패는 **제스처 중재의 실기기 체감**에서 갈린다 — 스트로크 도중 `isScrollEnabled = false`가 이미 시작된 네이티브 팬을 깨끗이 끊는지, "꾹 누르기 vs 빠르게 훑기"가 손끝에서 갈리는지. 이건 UIKit 제스처 중재 영역이라 **단위 테스트로 커버되지 않는다.** 억지로 TDD 형태를 만들지 않는다.

- **단위 테스트로 지키는 것:** 기존 350개 테스트 전부 통과(회귀 방지). `TapClassifierTests`가 탭 모드 판별 로직을 이미 커버한다 — 이번 개편이 그 로직을 건드리지 않았음을 이 테스트로 확인한다.
- **시뮬레이터 스모크로 지키는 것:** 그리기 모드에서 한 손가락 드래그 = 지도 이동(확실히 검증 가능), 탭 모드 정상 동작. **롱프레스-드래그로 선이 그려지는지는 시뮬레이터에서 합성이 안 될 수 있다** — XcodeBuildMCP에 "누른 채 이동"을 하나의 연속 터치로 만드는 프리미티브가 없다(Task 3 Step 3에 상세). 즉 **그리기 동작 자체는 실기기가 첫 검증**일 가능성이 높다.
- **실기기 QA로만 지킬 수 있는 것:** 임계값 체감, 홀드 중 지도 미동작, 더블탭 줌·원핑거 줌과의 충돌(시뮬레이터 재현 난이도 높음 — MVP10 체크리스트에도 "실기기 확인 필수"로 명시됨).

---

## 파일 구조

| 파일 | 역할 | 이번 변경 |
|---|---|---|
| `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift` | MKMapView 래핑 + 제스처 배선 전체 | **유일한 코드 변경 지점** — Task 1·2 |
| `Trace/Pages/CoursePlannerPage/TapClassifier.swift` | 탭 보류/확정 순수 상태 머신 (MVP10) | **변경 없음** — Task 3에서 회귀만 확인 |
| `docs/qa/2026-07-21-draw-gesture-device-checklist.md` | 실기기 QA 체크리스트 | 신규 — Task 4 |

---

## Task 1: 롱프레스-드래그 그리기 + 스트로크 단위 스크롤 잠금

이 사이클의 핵심. 즉시 인식 팬을 롱프레스로 교체하고, 스크롤 잠금을 모드 경계에서 스트로크 생명주기로 옮긴다.

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:194-201` (drawGR 생성)
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:329-339` (모드 전환 블록)
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:513` (인식기 프로퍼티 타입)
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:524-565` (`handleDraw`)
- Modify: `Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift:52` (안내 문구)
- Modify: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift:209` (안내 문구)

**Interfaces:**
- Consumes: 기존 `parent.onStrokeUpdate([CGPoint])`, `parent.onStrokeEnded([CourseCoordinate], CoursePinRole?)`, `pinHit(at:in:) -> CoursePinRole?` — **시그니처 변경 없음**
- Produces: `Coordinator.drawGestureRecognizer`가 `UILongPressGestureRecognizer?` 타입으로 바뀐다 (Task 2·3이 이 이름을 그대로 참조)

---

- [x] **Step 1: 롱프레스 임계값을 이름 붙은 상수로 정의**

`MapViewRepresentable` 타입 본문(프로퍼티 `var isDrawingMode: Bool`이 있는 176행 근처)에 추가한다. 이 두 값은 실기기 튜닝 대상(Task 4)이므로 리터럴로 흩어두지 않는다.

```swift
    // 그리기 롱프레스 임계값 — 실기기 튜닝 대상 (플랜 Task 4).
    // 짧게 하면 지도를 옮기려던 손짓이 그리기로 오인되고, 길게 하면 매 스트로크 시작이 굼뜨다.
    private static let drawPressDuration: TimeInterval = 0.25
    // 인식 전 허용 이동량 — 이보다 많이 움직이면 롱프레스는 실패하고 네이티브 팬이 이긴다.
    // 이 값이 "빠르게 훑기 = 이동 / 꾹 누르기 = 그리기"를 가르는 실제 분기점이다.
    private static let drawAllowableMovement: CGFloat = 10
```

- [x] **Step 2: `drawGR`을 롱프레스 인식기로 교체**

`makeUIView` 안 194–201행을 아래로 교체한다.

```swift
        let drawGR = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDraw(_:))
        )
        // 롱프레스는 인식(.began) 이후에도 손가락 이동에 따라 .changed를 계속 보낸다 —
        // 인식기 하나로 "꾹 누르기 + 드래그"를 모두 처리한다.
        drawGR.numberOfTouchesRequired = 1
        drawGR.minimumPressDuration = Self.drawPressDuration
        drawGR.allowableMovement = Self.drawAllowableMovement
        drawGR.isEnabled = false
        mapView.addGestureRecognizer(drawGR)
        context.coordinator.drawGestureRecognizer = drawGR
```

- [x] **Step 3: 인식기 프로퍼티 타입 변경**

513행:

```swift
        weak var drawGestureRecognizer: UILongPressGestureRecognizer?
```

- [x] **Step 4: `handleDraw` 시그니처를 롱프레스로 바꾸고 스크롤 잠금/해제를 넣는다**

524–565행의 `handleDraw` 전체를 아래로 교체한다. 변경점은 세 가지 — ① 파라미터 타입, ② `.began`에서 `isScrollEnabled = false`(지도 고정), ③ `.ended`/`.cancelled`와 다중 터치 취소 경로에서 `isScrollEnabled = true`(지도 이동 복원). 좌표 수집·핀 히트·최소 2점 게이트 로직은 그대로다.

```swift
        @objc func handleDraw(_ recognizer: UILongPressGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }

            if recognizer.numberOfTouches > 1 {
                currentStrokePoints = []
                currentStrokeCoords = []
                strokeStartPinRole = nil
                parent.onStrokeUpdate([])
                mapView.isScrollEnabled = true
                recognizer.state = .cancelled
                return
            }

            let point = recognizer.location(in: mapView)
            let clCoord = mapView.convert(point, toCoordinateFrom: mapView)
            let coord = CourseCoordinate(latitude: clCoord.latitude, longitude: clCoord.longitude)

            if recognizer.state == .began {
                // 롱프레스가 인식된 이 순간부터만 지도를 고정한다. 그 전까지는 한 손가락이
                // 네이티브 팬으로 지도를 움직인다 (그리기 모드의 '대기' 하위 상태).
                mapView.isScrollEnabled = false
                let hit = pinHit(at: point, in: mapView)
                strokeStartPinRole = hit == .pendingStart ? nil : hit
            }

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
                let startHit = strokeStartPinRole
                strokeStartPinRole = nil
                parent.onStrokeUpdate([])
                // 스트로크가 끝났으니 한 손가락 지도 이동을 되살린다.
                mapView.isScrollEnabled = true
                if stroke.count >= 2 {
                    parent.onStrokeEnded(stroke, startHit)
                }
            default:
                break
            }
        }
```

- [x] **Step 5: 모드 전환 블록에서 스크롤 잠금을 걷어낸다**

329–339행을 아래로 교체한다. `isScrollEnabled`는 이제 모드가 아니라 스트로크가 소유하므로 이 블록에서 빠지고, 그리기 모드 진입 시 항상 `true`로 초기화한다(직전 스트로크가 `.cancelled`로 끝나 복원이 누락되는 경우의 안전망). `isPitchEnabled`/`isRotateEnabled`는 두 손가락 제스처라 그리기와 경쟁하지 않지만, 그리는 중 의도치 않은 회전·기울기를 막기 위해 기존대로 그리기 모드에서 비활성을 유지한다.

```swift
        let wasDrawing = context.coordinator.drawGestureRecognizer?.isEnabled ?? false
        if wasDrawing != isDrawingMode {
            // 한 손가락 지도 이동은 두 모드 모두에서 살아 있다 — 그리기 중 잠금은
            // handleDraw가 스트로크 단위로만 건다.
            uiView.isScrollEnabled = true
            uiView.isPitchEnabled = !isDrawingMode
            uiView.isRotateEnabled = !isDrawingMode
            context.coordinator.drawGestureRecognizer?.isEnabled = isDrawingMode
            context.coordinator.twoFingerPanGestureRecognizer?.isEnabled = isDrawingMode
            context.coordinator.tapGestureRecognizer?.isEnabled = !isDrawingMode
            context.coordinator.touchObserverRecognizer?.isEnabled = !isDrawingMode
            context.coordinator.resetTapClassification(in: uiView)   // 판별 창 중 모드 전환 → 보류 취소
        }
```

- [x] **Step 6: 빌드 + 기존 테스트 전체 통과 확인**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test
swiftlint
```
Expected: 빌드 성공, 테스트 전체 통과(기존 350개 기준 — 이번 태스크는 테스트를 추가하지 않으므로 개수가 줄면 안 된다), 린트 위반 0.

통과하면:
```bash
touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok
```

- [x] **Step 7: 안내 문구가 새 제스처를 가르치도록 수정**

지금 문구는 "손으로 경로를 그려보세요"라 **한 손가락으로 그으라는 뜻으로 읽힌다** — 개편 후엔 틀린 안내이고, 롱프레스의 유일한 실질 약점인 발견성(사용자가 꾹 눌러야 하는 걸 모름)을 방치하게 된다.

`Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift:52`:

```swift
        if viewModel.isDrawingMode && viewModel.course == nil { return "꾹 눌러서 경로를 그려보세요" }
```

`Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift:209`:

```swift
        if viewModel.isDrawingMode { return "지도를 꾹 눌러서 경로를 그려보세요" }
```

같은 파일 208행 `"도보 기준 · 탭해서 이어 그리기"`는 **탭 모드** 문구이므로 건드리지 않는다.

- [x] **Step 8: 빌드 + 테스트 + 린트 재실행**

Step 6과 동일한 명령 3개를 다시 돌린다(문구 변경 후 회귀 확인).
Expected: 빌드 성공, 테스트 전체 통과, 린트 위반 0.

통과하면 `touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok`

- [x] **Step 9: Commit**

```bash
scripts/trace-commit.sh -m "feat: 그리기를 롱프레스-드래그로 바꾸고 스크롤 잠금을 스트로크 단위로 이동" -- Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift Trace/Pages/CoursePlannerPage/CoursePlannerPage.swift Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift
```

---

## Task 2: 커스텀 두손가락 팬 제거

Task 1로 그리기 모드에서도 한 손가락 네이티브 팬이 살아났으므로, 그 부재를 메우려고 만들었던 커스텀 두손가락 팬은 존재 이유가 사라진다. `handleTwoFingerPan`은 `setRegion`으로 팬을 손수 재구현한 코드라 네이티브 팬보다 관성·감쇠가 없어 체감도 나쁘다. 제거하면 delegate 동시 인식 규칙도 함께 단순해진다.

**Files:**
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:203-212` (twoFingerPanGR 생성 — 삭제)
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:335` (모드 전환 블록의 enable 줄 — 삭제)
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:496-509` (delegate 동시 인식)
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:514` (프로퍼티 — 삭제), `:518` (`panStartCenter` — 삭제)
- Modify: `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift:661-685` (`handleTwoFingerPan` — 삭제)

**Interfaces:**
- Consumes: Task 1이 남긴 `drawGestureRecognizer: UILongPressGestureRecognizer?`
- Produces: `Coordinator`에서 `twoFingerPanGestureRecognizer`·`panStartCenter`·`handleTwoFingerPan`이 사라진다. 이후 태스크는 이 이름들을 참조하지 않는다.

---

- [x] **Step 1: `makeUIView`에서 twoFingerPanGR 생성 블록 삭제**

203–212행(`let twoFingerPanGR = ...`부터 `context.coordinator.twoFingerPanGestureRecognizer = twoFingerPanGR`까지) 전체를 삭제한다.

- [x] **Step 2: 모드 전환 블록에서 해당 줄 삭제**

Task 1 Step 5에서 만든 블록에서 아래 한 줄을 삭제한다:

```swift
            context.coordinator.twoFingerPanGestureRecognizer?.isEnabled = isDrawingMode
```

- [x] **Step 3: delegate 동시 인식 규칙 단순화**

496–509행을 아래로 교체한다. 커스텀 두손가락 팬이 사라졌으니 핀치 배제 규칙과 두손가락 팬 관련 주석도 함께 사라지고, 남는 건 "터치 관찰자는 인식 전이가 없어 항상 무해"뿐이다.

```swift
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // 터치 관찰자는 인식 상태로 전이하지 않아 다른 인식기를 방해하지 않는다 —
            // 네이티브 줌·팬과 동시 인식을 명시적으로 허용해 둔다.
            gestureRecognizer === touchObserverRecognizer
        }
```

- [x] **Step 4: Coordinator에서 죽은 프로퍼티·핸들러 삭제**

- 514행 `weak var twoFingerPanGestureRecognizer: UIPanGestureRecognizer?` 삭제
- 518행 `private var panStartCenter: CLLocationCoordinate2D?` 삭제
- 661–685행 `// MARK: Two-Finger Pan` 주석과 `handleTwoFingerPan(_:)` 메서드 전체 삭제

- [x] **Step 5: 잔재 없음 확인**

Run:
```bash
grep -rn 'twoFingerPan\|panStartCenter' Trace/
```
Expected: 출력 없음 (exit 1).

- [x] **Step 6: 빌드 + 테스트 + 린트**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test
swiftlint
```
Expected: 빌드 성공, 테스트 전체 통과, 린트 위반 0.

통과하면 `touch .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok`

- [x] **Step 7: Commit**

```bash
scripts/trace-commit.sh -m "refactor: 네이티브 한 손가락 팬 복원으로 불필요해진 커스텀 두손가락 팬 제거" -- Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift
```

---

## Task 3: 시뮬레이터 스모크 + 탭 모드 회귀 검증

킥오프 §2.5가 "구체적 검증 태스크로 명시할 것"을 요구한 항목 중 MVP10 탭 판정 충돌 점검을 여기서 처리한다. 코드 변경이 없는 **검증 전용 태스크**다 (임계값 상수는 Task 1 Step 1에서 이미 정의됨).

**Files:** 코드 변경 없음. 검증 결과만 보고한다.

**Interfaces:**
- Consumes: Task 1의 롱프레스 그리기 + Task 2의 정리된 delegate

---

- [ ] **Step 1: 빌드 + 테스트 + 린트**

Run:
```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4" -parallel-testing-enabled NO test
swiftlint
```
Expected: 빌드 성공, 테스트 전체 통과, 린트 위반 0.

- [ ] **Step 2: 시뮬레이터 스모크 — 그리기 모드 한 손가락 = 지도 이동**

XcodeBuildMCP로 앱을 띄우고 코스 탭에서 "그리기" 토글을 켠 뒤, 지도 위를 **빠르게** 한 손가락 드래그한다. `snapshot_ui`로 지도 elementRef를 얻어 `drag`(preDelay 없이, `duration`을 짧게)를 쓴다.

Expected: **지도가 이동한다. 선이 그려지지 않는다.** (개편 전이라면 선이 그려졌을 동작)

이 스텝은 도구로 확실히 합성 가능하며, **이 사이클이 없애려는 원래 불편이 사라졌는지를 직접 검증하는 핵심 스모크**다. 실패하면 구현 결함이다 — Step 4와 달리 도구 한계로 넘길 수 없다.

- [ ] **Step 3: 시뮬레이터 스모크 — 롱프레스-드래그 = 그리기 (합성 가능하면)**

⚠️ **이 스텝은 도구 한계로 실패할 수 있다. 실패는 정상이며, 막히면 즉시 다음으로 넘어간다 — 여기서 루프를 돌지 말 것.**

플랜 작성 시점(2026-07-21)에 XcodeBuildMCP 도구 스키마를 확인한 결과, "손가락을 내린 채 유지하다가 그대로 이동"을 하나의 연속 터치로 합성하는 프리미티브가 **없다**:
- `long_press` — 눌렀다 뗀다. 드래그로 이어지지 않음
- `touch` — `down: true`로 누른 상태를 만들 수 있으나, 그 터치를 이어받아 **이동시키는 도구가 없음**
- `drag` — 자체 터치 시퀀스를 새로 시작함. `preDelay` 파라미터가 있으나 "터치 다운 후 대기"인지 "제스처 시작 전 대기"인지 문서상 불명확

**시도 순서:**
1. `drag`에 `preDelay: 0.5`(임계값 0.25초보다 넉넉히 크게)를 주고 지도 elementRef 위에서 드래그한다. `preDelay`가 "다운 후 대기"라면 롱프레스가 인식돼 선이 그려진다.
2. 선이 그려지면 성공 — Expected: **선이 그려지고 지도는 움직이지 않으며**, 손을 뗀 뒤 경로 계산이 돌아 구간이 생긴다.
3. 선이 안 그려지고 지도만 움직이면 → `preDelay`가 다운 후 대기가 아니라는 뜻이다. **이것만으로는 구현 실패로 판정하지 않는다** (도구 한계와 구현 결함이 구분되지 않으므로). 결과를 "시뮬레이터 합성 불가"로 기록하고 **실기기 QA 시나리오 2로 이관**한 뒤 다음 스텝으로 넘어간다.

**중요:** 이 스텝이 3번으로 끝나면 **이번 사이클의 핵심 동작(그리기)은 실기기 전까지 검증되지 않은 상태**다. 그 사실을 태스크 보고에 명시한다 — "스모크 통과"로 뭉뚱그리지 않는다. 반대로 Step 2(한 손가락 = 이동)은 도구로 확실히 검증 가능하고, 이 사이클이 없애려는 **원래 불편이 사라졌는지를 직접 보는** 스텝이므로 그쪽이 실패하면 그건 진짜 구현 실패다.

- [ ] **Step 4: 탭 모드 회귀 검증 (MVP9/MVP10 이력 충돌 점검)**

Task 1·2가 탭 모드 인식기들의 공용 enable/disable 블록과 delegate를 수정했으므로, 아래 세 시나리오를 시뮬레이터에서 확인한다. 각 시나리오의 출처는 `history/mvp10/2026-07-04-gesture-consistency-device-checklist.md`다.

| # | 시나리오 | 기대 결과 | 출처 |
|---|---|---|---|
| a | 탭 모드에서 싱글탭 | ~0.35초 뒤 마커 확정 + 경로 계산 | MVP10 시나리오 1 |
| b | **서로 다른 두 위치를 빠르게 연속 탭** | **둘 다 포인트로 인정** (이게 `require(toFail:)` 회귀의 지표 — 하나라도 씹히면 즉시 중단) | MVP10 시나리오 5 / MVP9 회귀 |
| c | 탭 모드 ↔ 그리기 모드를 빠르게 반복 전환 | 임시 마커가 남지 않고 상태가 꼬이지 않음 | MVP10 시나리오 7·12 |

`TapClassifierTests`가 Step 2에서 이미 통과했으므로 판별 **로직**은 무사하다. 이 스모크는 **배선**(인식기 enable/disable, delegate)이 무사한지를 본다.

Expected: 세 시나리오 모두 기대대로 동작. b가 실패하면 delegate 변경(Task 2 Step 3)을 최우선 의심한다.

- [ ] **Step 5: 결과 기록**

코드 변경이 없으므로 커밋하지 않는다. Step 1~4의 결과(특히 Step 3이 도구 한계로 넘어갔는지, Step 4 표의 세 행이 각각 통과했는지)를 태스크 보고서에 그대로 적는다. Step 2가 실패했다면 구현 결함이므로 여기서 멈추고 보고한다.

---

## Task 4: 실기기 QA 체크리스트 작성

시뮬레이터로 재현이 안 되는 항목(더블탭 줌·원핑거 줌 충돌, 임계값 체감, 홀드 중 지도 미동작)을 실기기에서 확인할 체크리스트를 만든다. 형식은 시나리오 카드 + 평이한 언어(`docs/agent-rules/testing.md` 템플릿).

**Files:**
- Create: `docs/qa/2026-07-21-draw-gesture-device-checklist.md`

---

- [ ] **Step 1: 체크리스트 작성**

`docs/qa/2026-07-20-run-fullscreen-device-checklist.md`의 형식을 그대로 따르되, 아래 시나리오를 반드시 포함한다:

1. **그리기 모드에서 지도 옮기기** — 그리기 토글을 켠 채 한 손가락으로 지도를 이리저리 움직여본다. 선이 한 번도 안 그려져야 한다. (이 사이클이 없애려는 원래 불편이 사라졌는지 보는 시나리오)
2. **꾹 눌러서 그리기** — 꾹 누른 뒤 드래그해 선을 긋는다. **누르고 있는 동안 지도가 미세하게라도 따라 움직이면 안 된다.** ← 🚦 결정 게이트 항목
3. **줌인 상태에서 그리기 → 이동 → 이어 그리기** — 방향 스펙이 적어둔 실제 시나리오(줌 인 → 선 긋기 → 다음 그릴 곳 찾으러 이동 → 이어 긋기)를 그대로 해본다. 흐름이 끊기지 않는지.
4. **임계값 체감** — 매 스트로크 시작의 "꾹" 마찰이 거슬리는지. 반대로 지도를 옮기려다 선이 그려지는 일이 있는지. 둘 다 있으면 조정 범위: `drawPressDuration` 0.2–0.4초, `drawAllowableMovement` 5–20pt. **이 범위를 벗어나야 해결된다면 결정 게이트 발동.**
5. **두 손가락 핀치 줌** — 그리기 모드에서 핀치 줌이 부드러운지(커스텀 두손가락 팬 제거의 부수 효과 확인).
6. **더블탭 줌** — 탭 모드에서 더블탭 시 줌만 되고 포인트가 안 생기는지. (MVP10 시나리오 2 — 실기기 필수)
7. **탭 후 손가락 유지한 채 드래그(원핑거 줌)** — 줌만 되고 포인트가 안 생기는지. (MVP10 시나리오 3 — 실기기 필수)
8. **핀 근처에서 그리기 시작** — 출발핀 옆에서 꾹 눌러 긋기 시작하면 기존처럼 이어붙는지. (MVP10 시나리오 8·9 — 롱프레스 전환으로 `.began` 시점의 핀 히트 판정이 바뀌지 않았는지 확인)
9. **왕복 그리기** — 기존처럼 잘 되는지. (MVP10 시나리오 18)

각 시나리오에 "무엇을 한다 / 무엇이 보여야 한다 / 결과(☐ 통과 ☐ 실패 + 메모)" 3단 구성을 넣는다.

- [ ] **Step 2: Commit**

```bash
scripts/trace-commit.sh -m "docs: draw-gesture 실기기 QA 체크리스트 추가" -- docs/qa/2026-07-21-draw-gesture-device-checklist.md
```

---

## 완료 후

1. **실기기 QA 실행** — 사용자가 체크리스트대로 확인. 🚦 결정 게이트 규칙 적용.
2. QA 통과 시 `docs/roadmap.md`의 MVP16 `draw-gesture` 항목을 `[x]`로 바꾸고 결과 요약을 적는다. 이걸로 **MVP16의 마일스톤 4개가 모두 완료**된다.
3. MVP16 아카이빙(`/trace-archive`)은 별도 단계 — 단, `docs/backlog.md`에 남은 가로모드 시트 설계 재검토 항목이 MVP16 소속이므로 아카이빙 전에 그 항목의 거취(다음 MVP로 이월 vs MVP16에 잔류)를 사용자와 정한다.
4. 이번 사이클에서 재사용 가능한 학습이 나오면 `ce-compound`로 `docs/solutions/`에 기록한다 — 특히 "롱프레스 `.began`에서 `isScrollEnabled`를 끄면 진행 중인 네이티브 팬이 어떻게 되는가"는 실측값이 나오면 문서화 가치가 있다.

---

## 자기 점검 결과 (플랜 작성자)

- **스펙 커버리지:** §2.5의 요구 4개 — ① 방향 A 구현(Task 1), ② 롱프레스 임계값 튜닝을 구체적 검증 태스크로(Task 1 Step 1 + Task 4 시나리오 4), ③ MVP10 탭 판정 충돌 점검을 구체적 검증 태스크로(Task 3 Step 4 표 + Task 4 시나리오 6·7), ④ 제스처 중재 재설계 — 네이티브 팬 vs 롱프레스 배타 처리(Task 1 Step 4·5)와 두손가락 팬·탭 판별기의 거취(Task 2 = 제거, Task 3 = 탭 판별기 유지 확인). 반증 조건은 🚦 결정 게이트로 승격. **누락 없음.**
- **플레이스홀더 스캔:** 코드가 바뀌는 모든 스텝에 실제 코드 블록 있음. "적절히 처리" 류 표현 없음.
- **타입 일관성:** `drawGestureRecognizer`는 Task 1에서 `UILongPressGestureRecognizer?`로 정의되고 Task 2·3이 같은 이름·타입으로 참조. `drawPressDuration`/`drawAllowableMovement`는 Task 1에서 정의되고 Task 4가 같은 이름으로 참조. `handleDraw(_:)`는 Task 1에서 파라미터 타입이 바뀌고 Step 1의 `#selector`가 같은 메서드를 가리킴.
