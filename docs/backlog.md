# Backlog

실기기 테스트·리뷰에서 나온 개선/수정 후보와 미룬 기술부채를 모으는 곳.
**규칙:** backlog 항목은 **마일스톤 후보**다 — 묶어서 새 MVP를 구성하거나 기존 MVP의 마일스톤으로 편입한다(작고 명확하면 spec/plan 바로, 결정·모호하면 brainstorm). 큐가 아니라 **메뉴** — 새 기능을 먼저 해도 된다. 단위·흐름은 `docs/agent-rules/workflow.md`, 현재 위치는 `docs/roadmap.md`, 캡처/소비 흐름은 `testing.md`·`skills.md` 참고.
상태: `open`(미착수) / `planned`(마일스톤 잡힘) / `done`(완료).

## 마커 그리기 + 스냅 MVP (2026-06-20) 실기기 피드백

- [x] **위치 시작 화면** — MVP2에서 해결: 500m 줌 + UserAnnotation + 내 위치 버튼. `done`
- [x] **그리기 모드 표시 명확화** — MVP2에서 해결: "그리기 중" 라벨 + pencil.tip 아이콘 + 배경색. `done`
- [x] **그린 코스에 출발/도착 핀** — MVP2에서 해결: course 첫/끝 좌표 기반 출발/도착 핀. `done`
- [x] **상태 잔상 정리 + 상호작용 모델** — MVP2에서 해결: 단일 모드 전환(InteractionMode), 모드 전환 시 반대 모드 상태 초기화. `done`
- [x] **권한 거부 UX** — MVP2에서 해결: 설정 이동 알럿 + 서울시청 폴백. `done`

## MVP2 UX + 스로틀 (2026-06-23) 실기기 피드백

- [x] **앱 시작 시 카메라 점프 제거** — MVP3에서 해결: UserDefaults 카메라 저장/복원 + 서울시청 초기값 + 백그라운드 저장. `done`
- [x] **비연속 구간 그리기 시 이상한 결과** — MVP3에서 해결: 4쌍 거리 비교 자동 방향 감지 + 스트로크 reverse + 증분 계산. `done`
- [x] **그리기 중 지도 이동 UX** — MVP4에서 해결: MKMapView(UIViewRepresentable) 마이그레이션 + isScrollEnabled/isZoomEnabled 토글 + 커스텀 2손가락pan/pinch GR. 2손가락 핀치 UX는 개선 여지 있음(아래 백로그). `done`
- [x] **스로틀 한계 측정 + 모니터링** — MVP3에서 해결: 증분 계산(새 구간만 라우팅) + `.throttled` 에러 감지 + 사용자 안내 메시지. `done`

## MVP3 (2026-06-25) 실기기 피드백

- [x] **스로틀 에러 메시지 미표시** — MVP4에서 확인: 실기기 로그가 `GEOErrorDomain Code=-3`이고 isThrottled 조건에 이미 포함되어 있음. 에러 메시지 정상 표시 확인. `done`

## 기술부채

- [x] **MKDirections 스로틀 완화** — MVP3에서 해결: 증분 계산으로 기존 구간 재호출 제거. 근본책(맵매칭 제공자)은 여전히 미래 옵션. `done`
- [x] **테스트 시뮬레이터 iOS 버전 전략** — MVP5에서 문서화 완료: iOS 18.x `@Observable` malloc 크래시는 Apple 런타임 버그로 확인, iOS 26.5로 우회 결정. 상세: `docs/solutions/workflow-issues/ios18-observable-malloc-crash.md`. `done`
- [x] **SwiftUI Map → MKMapView 교체** — MVP4에서 해결: MKMapView(UIViewRepresentable) 마이그레이션 완료, MKOverlay/MKAnnotation delegate 방식으로 전환. `done`

## MVP5 (2026-06-28) 실기기 피드백

- [x] **탭 경로 연속 누적 불가** — MVP6에서 해결: CourseEditSession.attach로 세그먼트 누적, 탭마다 이어붙이기. `done`
- [x] **탭↔그리기 경로 자동 이어붙이기** — MVP6에서 해결: session 끝점 기준 방향 감지 + gap 라우팅 자동 연결. `done`
- [x] **undo/clear 그리기 모드 전용** — MVP6에서 해결: canUndo 모드 무관 통합, session.undo() 폴스루. `done`

## 코스 편집 UX 개선 (2026-07-01) 실기기 피드백

- [x] **undo가 prepend된 최근 구간을 못 지움** — 이번에 해결: `segments`는 "공간순"인데 attach는 "시간순"이라 prepend 시 두 순서가 갈라져 undo가 엉뚱한 구간을 지우던 버그. `CourseEditSession`에 `Entry{id, order, segment}` 도입해 시간순(`order`)을 별도 추적, undo는 `order` 최대값 제거로 수정. `segmentColorKeys`(attach 생성 순서)를 분리해 prepend 후에도 기존 구간 색상이 안 바뀌도록 함. 실기기 검증 완료. `done`
- [x] **(C) 짧은 거리 도착 마커 미표시** — 이번에 해결: 거리 라벨 annotation과 위치가 겹칠 때 MapKit이 충돌 처리로 핀을 자동으로 숨기던 문제. `MKAnnotationView.displayPriority = .required`, `collisionMode = .none`으로 수정(핀은 최대 2개뿐이라 성능 영향 없음). 좌표 2개 미만의 축약된 route 결과에 대한 방어 guard도 함께 추가. 실기기 검증 완료. `done`
- [x] **(D) 내 위치 이동 버튼 오작동/지연** — 이번에 해결: `CoreLocationService.currentLocation()`이 단일 `continuation`으로 재진입을 막아, 부트스트랩(`.task`)이 위치를 기다리는 동안 버튼을 누르면 즉시 `.unavailable`로 실패하고 `recenterToCurrentLocation()`의 `try?`가 그 에러를 조용히 삼켰다. `ContinuationBroadcaster`를 도입해 겹친 요청이 같은 결과를 함께 기다리도록 수정. `done`
- [x] **실시간 구간 패널 무한 확장** — MVP8 `course-ux-polish`에서 해결: 최대 높이(지도 높이 40%) + 내부 스크롤 + 채팅 앱 방식 자동 스크롤. `done`
- [x] **겹치는 경로 렌더링 방식** — MVP8 `overlap-offset`에서 해결: 점-대-선분 겹침 감지 + 생성 순서 우선 + 4m×n 오프셋 + 실거리 테이퍼. 2026-07-03 실기기 디버그 로그로 `maxDisplacementMeters≈4.0` 확인, 정상 동작 검증 완료. `done`

## MVP8 (2026-07-03) 실기기 QA 피드백

- [x] **구간 패널 스크롤 인디케이터가 콘텐츠와 함께 안쪽으로 밀림** — 이번에 해결: `.padding()`이 ScrollView 전체를 감싸 인디케이터까지 밀렸던 것을 `contentMargins(for: .scrollContent)`로 분리. `done`
- [x] **탭 모드로는 온전한 길이의 왕복(출발점까지 되짚기) 구간을 만들 수 없음** — *where:* `CoursePlannerPageViewModel.handleMapTap`/`nearestEndpoint` / *now:* 탭 한 번 = "가장 가까운 기존 끝점 → 지금 탭한 지점"으로 즉시 라우팅·연결되는데, 원래 출발점을 다시 탭하면 "그 지점에서 그 지점까지"가 되어 0m로 귀결됨 — 탭만으로는 중간 지점을 거치는 전체 길이의 왕복 구간을 만들 방법이 없음(그리기 모드는 가능, 2026-07-03 실기기 확인). MVP5~6 설계의 특성이라 겹침 오프셋(MVP8)과는 무관 / *desired:* 아직 미정 — "왕복" 전용 액션을 추가할지, 탭 모드의 연결 규칙을 조정할지 브레인스토밍 필요 → MVP9 `edit-consistency`에서 해결: 끝점 근접 탭(반경 20m) = 반대 끝점에서 그 끝점까지 라우팅. 스펙: `history/mvp9/2026-07-03-edit-consistency-design.md`. `done`
- [ ] **두 손가락 탭 줌아웃과 커스텀 2손가락 pan을 빠르게 연속 시도하면 서로 제대로 동작 안 할 때 있음** — *where:* `MapViewRepresentable` 그리기 모드 제스처 / *now:* 천천히 하면 각각 정상 동작, 빠르게 하면 제스처 인식기 경쟁으로 판정이 애매해짐(2026-07-03 실기기 확인) / *desired:* `UIGestureRecognizer` `shouldRecognizeSimultaneously`/`require(toFail:)` 조정 필요, 실기기 튜닝 필요 → MVP10 `two-finger-gesture-tuning`. `planned`
- [ ] **구간 패널: 출발 지점(prepend)에 구간 추가 시 스크롤 위치가 한 칸씩 밀리는 느낌** — *where:* `CoursePlannerPage+SegmentPanelComponent` / *now:* 도착 지점 추가(append)는 위치 유지되는데, 출발 지점 추가(prepend)는 보던 위치가 밀리는 현상(2026-07-03 실기기 확인) — `scrollPosition(id:anchor:)`가 prepend 시 자동 위치보존을 완전히 못 하는 것으로 추정, 확정 원인 미조사 / *desired:* 2026-07-03 MVP9 킥오프에서 검토 — 위쪽 추가 시 아래로 밀리는 것은 리스트의 자연스러운 동작으로 판단, 보정하지 않기로 보류. 실사용 불편이 다시 확인되면 재검토. `open`(보류)
- [ ] **그리기 모드 핀치 줌 네이티브 복원, 체감 개선 미미** — MVP8 `course-ux-polish`에서 커스텀 핀치를 네이티브로 교체했으나(2026-07-03 실기기 확인) 사용자 체감상 뚜렷한 개선은 못 느낌. 버그는 아니고 기록만. `done`(코드 변경 자체는 완료, 체감 효과는 낮음)
- [x] **왕복(prepend) 시 출발/도착 핀이 실제 뛴 순서와 반대로 붙을 수 있음** — *where:* `CoursePlannerPage.mapPins`(`course.coordinates.first/last`) + `CourseEditSession.attach`의 prepend 분기 / *now:* 출발·도착 핀은 "배열상 첫/마지막 좌표" 기준인데, 왕복 구간을 그려서 prepend로 붙으면 그 새 구간의 시작점(물리적으로 기존 "도착" 지점 근처)이 배열 맨 앞으로 와서 "출발"로 라벨링됨 — 결과적으로 출발·도착 핀이 물리적으로 같은 지점(원래 도착 지점 근처)에 몰려 보임(2026-07-03 실기기 확인, 도착에서 시작해 출발로 되짚어 그린 테스트에서 재현). 순수 연장(같은 방향으로 더 뻗어나가는 prepend)에서는 지금 방식이 맞을 수 있어 왕복으로 인한 prepend와 구분이 필요함 / *desired:* 미정 — 브레인스토밍 필요. 후보: (1) "출발"을 배열 순서가 아니라 세션에서 가장 먼저 만든 지점(현재 `segmentColorKeys`처럼 시간순 `order` 활용)으로 재정의, (2) 코스 저장(다음 MVP 후보) 설계 시 "진짜 출발점"을 명시적 필드로 결정하면서 함께 정리, (3) prepend 시 "방향 연장 vs 왕복 되짚기"를 구분하는 별도 판정 로직 추가. 크래시·데이터 손실 없는 라벨링 혼동 수준이라 급하지 않음. MVP5~6 설계 특성이라 겹침 오프셋(MVP8)과는 무관 → MVP9 `edit-consistency`에서 해결: attach 판정을 "새 구간 시작점 기준 2쌍 비교"로 교체(자동 방향 감지 제거)해 왕복이 항상 append로 붙음 + 닫힌 코스 병합 핀. 스펙: `history/mvp9/2026-07-03-edit-consistency-design.md`. `done`

## MVP9 (2026-07-04) 실기기 QA 피드백

MVP9 완료 직후 실기기 QA에서 5건 발견, 3건은 이번 세션에서 근본 원인까지 확정해 수정(그리기 모드 라우팅 스냅, 경유점-라벨 z-order를 오버레이 전환으로 해결, 병합 배지 크기). 아래 2건은 "빠른 임계값/지연값 조정"으로는 근본 해결이 안 된다고 판단해 다음 MVP로 미룸.

- [ ] **그리기 모드 "출발점 근접" 판정이 순수 실거리(20m) 임계값이라 육안 근접과 어긋남** — *where:* `CoursePlannerPageViewModel.snappedStrokeStart`, `CourseEditSession.attach` 규칙 3 / *now:* 디버그 로그로 실기기 확인(2026-07-04): 사용자가 "출발점 바로 옆"이라 여기고 그리기 시작한 지점이 실제로는 51m 떨어져 있어 20m 임계값을 초과, 정상적으로 규칙 4(먼 곳 gap append)로 처리됨 — 코드는 설계대로 동작하지만 실사용 정밀도와 안 맞음. 단순히 임계값을 60~80m로 올리는 안은 검토했으나 기각: 사용자 지적대로 "누가 봐도 출발점에 가까운데 조금 더 멀다는 이유로 도착점이 그리로 움직이는" 경계 문제가 다른 거리로 옮겨갈 뿐 근본 해결이 아님 / *desired:* 탭 모드의 "출발핀 탭 왕복"(Task 4/5, `MapViewRepresentable.pinHit`)처럼 화면 픽셀(24pt) 기준 히트 판정을 그리기 시작점에도 적용하는 재설계 필요 — 줌 레벨과 무관하게 "시각적으로 가까움"을 판정해야 함. 규모가 있는 작업(그리기 제스처 시작점을 화면 좌표로 View→ViewModel까지 전달하는 배관 필요)이라 다음 MVP에서 브레인스토밍부터 제대로 시작 → MVP10 `draw-start-pixel-snap`. `planned`
- [ ] **탭 모드에서 더블탭(줌) 시 그 자리에 코스 지점이 함께 찍힘** — *where:* `MapViewRepresentable.Coordinator.handleTap` / *now:* 자체 시간(0.35s)+거리(40pt) 디바운스로 더블탭의 "두 번째 탭"은 무시하지만, 첫 번째 탭은 즉시 반영되므로 더블탭-줌 시도 중에도 점 하나는 찍힘(2026-07-04 실기기 확인). 완전히 없애려면 모든 탭을 ~0.3s 지연 후 확정하는 방식이 필요한데, 이는 정상적인 단일 탭 조작에도 체감 지연을 유발함 — 사용자가 이 트레이드오프를 받아들이지 않기로 결정. 다른 지도 앱(애플 지도 등)은 특정 지점 더블탭 시 선택 없이 줌만 되는 것을 사용자가 직접 확인해, 지연 없이 가능한 방법이 있을 것으로 추정 / *desired:* 미정 — 지연 없이 "이 더블탭은 줌 의도"를 판별하는 방법을 다음 MVP에서 제대로 조사(예: 네이티브 더블탭 인식기의 실제 인식 시점을 gesture delegate로 관찰하는 방법 등). 시도했던 두 방법(require(toFail:), 자체 디바운스)의 한계는 `docs/solutions/design-patterns/uikit-double-tap-require-to-fail-location-agnostic.md`에 기록됨 → MVP10 `tap-pending-commit`(탭 보류 확정, 2026-07-04 리서치로 지연 확정 방식 채택 — 임시 마커로 체감 지연 상쇄). `planned`

## 실사용 피드백 (2026-07-04)

- [ ] **탭 직후 빠른 한 손가락 드래그가 줌인/아웃으로 인식됨** — *where:* `MapViewRepresentable` 탭 모드 — `isZoomEnabled`는 어디서도 끄지 않아 MKMapView 네이티브 "원핑거 줌"(탭 → 곧바로 탭-드래그 상하 이동 = 줌, 애플 지도 한 손 줌) 제스처가 항상 활성 / *now:* 탭으로 코스 지점을 찍은 직후 빠르게 한 손가락으로 지도를 옮기려 하면, 직전 탭 + 새 터치-드래그가 원핑거 줌으로 묶여 지도가 줌인/아웃됨. 텀을 두고 드래그하면 일반 팬으로 정상 동작(2026-07-04 실사용 확인). MapKit 기본 제스처라 MVP1(SwiftUI Map)부터 존재했고, 탭 모드의 "탭 = 코스 지점 추가"와 겹치면서 체감 문제가 됨 / *desired:* "더블탭 줌 시 코스 지점 찍힘"과 같은 계열(네이티브 더블탭류 제스처 vs 우리 탭 처리) → MVP10 `tap-pending-commit`에서 함께 해결(탭 보류 확정 — 보류 중 두 번째 터치 유지 드래그 감지 시 취소). `planned`

## MVP8 킥오프 논의 (2026-07-02)

겹치는 경로 렌더링을 좌표 오프셋(α)으로 정하면서, α의 약점별 대비책을 트리거와 함께 보관.

- [ ] **겹침 렌더링 — 단일 코스 색 + 방향 화살표(β)** — *what:* 지도 위 구간별 색칠을 접고 단일 색 + 진행 방향 화살표로 표현, 구간 색·거리는 패널 전담 / *trigger:* α(좌표 오프셋) 적용 후에도 실기기 QA에서 구간 색·라벨 혼동이 남으면. MVP7 시각 언어(구간 색+라벨)를 상당 부분 되돌리는 방향 전환이므로 근거 없이 착수하지 않는다. `open`
- [ ] **겹침 렌더링 — 화면 포인트 기준 오프셋(안 3 원안)** — *what:* 오프셋 간격을 미터가 아닌 화면 포인트로 유지해 어느 줌에서도 겹친 선이 분리돼 보이게(지하철 노선도 방식). 줌마다 평행선을 재계산하는 커스텀 렌더러 필요 — 마일스톤 1개 규모 / *trigger:* α의 줌아웃 병합(축소 시 3~4m 간격이 1px 미만으로 줄어 한 줄로 보임)이 실사용에서 문제되면. `open`

## MVP4 (2026-06-27) 실기기 피드백

- [ ] **핀치 줌 UX 개선** — *where:* 그리기 모드 / *now:* `isZoomEnabled = false` + 커스텀 `UIPinchGestureRecognizer`로 구현 / *desired:* `drawGR.maximumNumberOfTouches = 1`이므로 충돌 없이 `isZoomEnabled = true` 고정 + 커스텀 pinchGR 제거로 네이티브 핀치 복원 가능. MVP8 `course-ux-polish`. `planned`
- [x] **탭↔그리기 경로 이어붙이기** — MVP5에서 해결: CourseSegment 세그먼트 배열 모델 + history 기반 탭↔그리기 이어붙이기. `done`
