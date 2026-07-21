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

- [ ] **앱 코드 린트 경고 44건 — 세 갈래로 갈라서 처리** — *what:* 2026-07-21 린트 범위를 바로잡으면서(테스트 43개 파일 편입, 커밋 `37154d8`) 앱 코드에 오래 쌓인 경고 44건이 드러났다. 전부 warning이라 커밋을 막지는 않는다. **44건이 모두 "고쳐야 할 결함"이 아니라는 게 핵심** — 착수 전에 아래 셋을 갈라야 한다. *①규칙 조정 후보(28건, identifier_name):* 대부분 한 줄 switch 패턴 바인딩의 `d`·`i`다(예: `case .tapped(_, let d), .drawn(_, let d): return d`). 스코프가 한 줄이라 긴 이름이 오히려 읽기 나쁠 수 있어, **코드를 고칠지 규칙 최소 길이를 낮출지가 먼저 정할 문제**다(테스트 폴더에서 한글 이름을 두고 내린 판단과 같은 종류). 많은 곳: `OverlapOffsetResolver`(6) · `RunPersistenceDTO`(5) · `CoursePersistenceDTO`(4). *②기계적 수정(9건, line_length):* 판단할 것 없이 줄만 나누면 된다. *③진짜 구조 신호(7건):* `MapViewRepresentable.swift`가 672줄(상한 500)에 특정 함수가 91줄·복잡도 12다. 이건 경고가 실제 설계 부담을 가리키는 경우라 **쪼개기 자체가 마일스톤 1개 규모** — 곁다리로 붙이면 안 된다. *why deferred:* 2026-07-21 세션의 작업(세로 고정·시트 예산 수정)과 무관한 기존 부채라, 같이 고치면 검증된 변경에 관계없는 수정이 섞인다(`git.md` "Do not mix unrelated changes"). 실제로 `swiftlint --fix`가 앱 파일 하나를 건드린 것을 그 자리에서 되돌렸다. *trigger:* ②는 아무 때나. ①은 "짧은 이름 때문에 실제로 코드를 못 읽겠다"는 판단이 서면 착수하되 규칙 조정 쪽을 먼저 검토. ③은 `MapViewRepresentable`을 어차피 크게 손볼 마일스톤이 생기면 그때 함께. `open`

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
- [x] **두 손가락 탭 줌아웃과 커스텀 2손가락 pan을 빠르게 연속 시도하면 서로 제대로 동작 안 할 때 있음** — *where:* `MapViewRepresentable` 그리기 모드 제스처 / *now:* 천천히 하면 각각 정상 동작, 빠르게 하면 제스처 인식기 경쟁으로 판정이 애매해짐(2026-07-03 실기기 확인) / *desired:* `UIGestureRecognizer` `shouldRecognizeSimultaneously`/`require(toFail:)` 조정 필요, 실기기 튜닝 필요 → MVP10 `two-finger-gesture-tuning`에서 해결: delegate 조정(핀치 명시적 제외 포함) + 실기기 재검증 완료(2026-07-06). `done`
- [ ] **구간 패널: 출발 지점(prepend)에 구간 추가 시 스크롤 위치가 한 칸씩 밀리는 느낌** — *where:* `CoursePlannerPage+SegmentPanelComponent` / *now:* 도착 지점 추가(append)는 위치 유지되는데, 출발 지점 추가(prepend)는 보던 위치가 밀리는 현상(2026-07-03 실기기 확인) — `scrollPosition(id:anchor:)`가 prepend 시 자동 위치보존을 완전히 못 하는 것으로 추정, 확정 원인 미조사 / *desired:* 2026-07-03 MVP9 킥오프에서 검토 — 위쪽 추가 시 아래로 밀리는 것은 리스트의 자연스러운 동작으로 판단, 보정하지 않기로 보류. 실사용 불편이 다시 확인되면 재검토. `open`(보류)
- [ ] **그리기 모드 핀치 줌 네이티브 복원, 체감 개선 미미** — MVP8 `course-ux-polish`에서 커스텀 핀치를 네이티브로 교체했으나(2026-07-03 실기기 확인) 사용자 체감상 뚜렷한 개선은 못 느낌. 버그는 아니고 기록만. `done`(코드 변경 자체는 완료, 체감 효과는 낮음)
- [x] **왕복(prepend) 시 출발/도착 핀이 실제 뛴 순서와 반대로 붙을 수 있음** — *where:* `CoursePlannerPage.mapPins`(`course.coordinates.first/last`) + `CourseEditSession.attach`의 prepend 분기 / *now:* 출발·도착 핀은 "배열상 첫/마지막 좌표" 기준인데, 왕복 구간을 그려서 prepend로 붙으면 그 새 구간의 시작점(물리적으로 기존 "도착" 지점 근처)이 배열 맨 앞으로 와서 "출발"로 라벨링됨 — 결과적으로 출발·도착 핀이 물리적으로 같은 지점(원래 도착 지점 근처)에 몰려 보임(2026-07-03 실기기 확인, 도착에서 시작해 출발로 되짚어 그린 테스트에서 재현). 순수 연장(같은 방향으로 더 뻗어나가는 prepend)에서는 지금 방식이 맞을 수 있어 왕복으로 인한 prepend와 구분이 필요함 / *desired:* 미정 — 브레인스토밍 필요. 후보: (1) "출발"을 배열 순서가 아니라 세션에서 가장 먼저 만든 지점(현재 `segmentColorKeys`처럼 시간순 `order` 활용)으로 재정의, (2) 코스 저장(다음 MVP 후보) 설계 시 "진짜 출발점"을 명시적 필드로 결정하면서 함께 정리, (3) prepend 시 "방향 연장 vs 왕복 되짚기"를 구분하는 별도 판정 로직 추가. 크래시·데이터 손실 없는 라벨링 혼동 수준이라 급하지 않음. MVP5~6 설계 특성이라 겹침 오프셋(MVP8)과는 무관 → MVP9 `edit-consistency`에서 해결: attach 판정을 "새 구간 시작점 기준 2쌍 비교"로 교체(자동 방향 감지 제거)해 왕복이 항상 append로 붙음 + 닫힌 코스 병합 핀. 스펙: `history/mvp9/2026-07-03-edit-consistency-design.md`. `done`

## MVP9 (2026-07-04) 실기기 QA 피드백

MVP9 완료 직후 실기기 QA에서 5건 발견, 3건은 이번 세션에서 근본 원인까지 확정해 수정(그리기 모드 라우팅 스냅, 경유점-라벨 z-order를 오버레이 전환으로 해결, 병합 배지 크기). 아래 2건은 "빠른 임계값/지연값 조정"으로는 근본 해결이 안 된다고 판단해 다음 MVP로 미룸.

- [x] **그리기 모드 "출발점 근접" 판정이 순수 실거리(20m) 임계값이라 육안 근접과 어긋남** — MVP10 `draw-start-pixel-snap`에서 해결: 화면 픽셀(24pt) 기준 핀 히트 판정을 그리기 시작점에도 적용, 실거리 20m는 폴백으로 유지. 2026-07-05 디버그 로그로 핀 히트 판정 자체는 정상 동작 확인. 단, 이 수정 과정에서 핀 히트 범위 밖의 "애매한 중간지대"에 남아있던 더 근본적인 방향 판정 갭이 새로 발견됨 → 아래 MVP10 QA 섹션의 새 항목 참고. `done`
- [x] **탭 모드에서 더블탭(줌) 시 그 자리에 코스 지점이 함께 찍힘** — MVP10 `tap-pending-commit`에서 해결: 탭 즉시 확정을 0.35초 보류 → 확정/취소로 교체, 더블탭/원핑거줌 시 취소되어 포인트가 안 찍힘. 실기기 QA에서 임시 마커 깜빡임 잔여 이슈 발견 후 100ms 표시 지연 추가로 마무리(commit 119047c, 재검증 대기). `done`

## 실사용 피드백 (2026-07-04)

- [x] **탭 직후 빠른 한 손가락 드래그가 줌인/아웃으로 인식됨** — MVP10 `tap-pending-commit`에서 위 항목과 함께 해결(탭 보류 확정 — 보류 중 두 번째 터치 유지 드래그 감지 시 취소). `done`

## MVP10 (2026-07-05) 실기기 QA 피드백

MVP10 구현 완료 직후 실기기 QA에서 4건 발견, 전부 근본 원인까지 확정해 수정하고 실기기 재검증까지 완료(2026-07-06).

- [x] **임시 마커 라벨이 확정 직후 짧게 뒤바뀌어 보임** — 이번에 해결: `isFirstPoint`(`pendingTapStart == nil`) 판정이 라우팅 완료 전에 이미 바뀌어 출발/도착 핀 스타일을 순간적으로 오재사용하던 버그. 임시 마커를 중립 스타일("확인 중", 회색 `circle.dashed`)로 통일해 판정 자체를 제거. 커밋 119047c. 재검증 완료(`history/mvp10/2026-07-04-gesture-consistency-device-checklist.md` 시나리오 1). `done`
- [x] **더블탭/원핑거 줌 취소 시에도 임시 마커가 짧게 깜빡임** — 이번에 해결: 마커 표시를 100ms 지연(`markerShowDelay`)시켜 취소될 제스처에서는 거의 안 보이게 함. 커밋 119047c. 재검증 완료(시나리오 2·3). `done`
- [x] **그리기 모드 두손가락 탭줌아웃이 부드럽지 않고 뚝뚝 끊김** — 이번에 해결: `shouldRecognizeSimultaneouslyWith`가 네이티브 `UIPinchGestureRecognizer`와도 동시 인식을 허용해 커스텀 2손가락 팬과 충돌하던 것을, 핀치는 명시적으로 제외하도록 수정. 커밋 119047c. 재검증 완료(시나리오 10). `done`
- [x] **코스 이어붙이기 규칙 4(원거리 폴백)가 상대적 근접성을 무시하고 무조건 도착점 기준으로 붙임** — *where:* `CourseEditSession.attach` 규칙 4 / *now:* 그리기 시작점이 화면 픽셀 히트(24pt)도 실거리 임계값(20m)도 안 걸리지만, 도착점보다 출발점에 확실히 더 가까운 "중간지대"에서는 상대 비교 없이 무조건 도착점에서 gap 라우팅 append됨(2026-07-05 실기기 디버그 로그로 확인: distToStart=324m, distToEnd=1241m인데도 도착점 기준으로 처리됨). MVP9가 "거리 비교로 추측하지 않는다"고 정한 설계(왕복 시 판정 흔들림 방지)의 의도된 트레이드오프지만, "명백히 가까운 쪽"이 무시되는 체감 문제로 다시 확인됨 → MVP10 `attach-nearest-fallback`에서 재설계(2026-07-05 브레인스토밍·스펙 리뷰 완료): 시작점 단일 최근접 비교(탭 `nearestEndpoint`와 동일한 `<=`)로 교체, 왕복은 규칙 1·2 선점으로 보호. 실기기 QA(시나리오 19)에서 원거리 케이스가 방향에 따라 여전히 실패함을 재발견 → 스트로크 양끝 중 더 가까운 쪽(anchor)을 단일 상대 비교로 고르는 방식으로 확장(2026-07-06, 근접 처리가 왕복 모호성을 이미 가로채므로 안전). 스펙: `history/mvp10/2026-07-05-attach-nearest-fallback-design.md`. 실기기 재검증 완료(시나리오 18·19). `done`

## MVP11 킥오프 논의 (2026-07-07)

- [x] **되짚어 오기 (마지막 구간 역방향 붙이기)** — *what:* 구간 패널 마지막 구간에 "되짚어 오기" 액션 추가 — 역방향 하나만 붙여 코스 끝을 그 구간 시작점으로 되돌림(그리던 중 막다른 골목·방파제에서 돌아 나와 이어 그리기 용도). *resolved:* 2026-07-08 실기기 QA에서 기존 "왕복 추가"(역+정 병합, 3× 거리) 자체가 버그로 확인되어, 정확히 이 항목이 원하던 동작(역방향만, 자유 끝 전용, 2× 거리)으로 교체됨 — 별도 액션을 새로 만들 필요 없이 "왕복 추가"가 곧 "되짚어 오기"가 됨. 설계: `docs/superpowers/specs/2026-07-07-course-save-roundtrip-design.md` §4. `done`

## MVP11 (2026-07-08) 실기기 QA 피드백

- [x] **SwiftData ModelContext 생성 위치(affinity) 경고** — *where:* `SwiftDataCourseRepository` / *now:* 실기기에서 코스 저장 시 콘솔에 "SwiftData.ModelContext: Unbinding from the main queue..." 경고. 동시성 버그는 아니었음 — 저장소가 이미 `actor`라 접근은 직렬화되고, `init`(main 스레드에서 호출)에서 생성한 컨텍스트를 actor 실행기에서 쓰는 생성 위치 위반이 실체 / *resolved:* 2026-07-08 해결 — 컨텍스트를 `lazy var`로 바꿔 첫 사용 시 actor 실행기 위에서 생성(+ `makeContext` nonisolated). 시뮬레이터에서 fetch 경로 실행 후 시스템 로그 643줄 중 관련 경고 0건, 전체 테스트 그린. 결함 패턴 복제 걱정 없이 다음 persistence 확장 가능. `done`
- [x] **Swift 6 동시성 전면 리팩토링 — isolation·Sendable·동시성 문법 일괄 정리 + 언어 모드 전환** — *what:* @MainActor 감사에 국한하지 않고 동시성/Swift 6 관련 문법 전체를 리팩토링한다(2026-07-08 사용자 결정). 범위: ① **암묵 isolation** — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`라 순수 값 타입·DTO(`CourseCoordinate`·`CourseSegment`·`SavedCourse`·`CoursePersistenceDTO`·`CourseRecord`)까지 암묵적 @MainActor → actor 저장소·테스트에서 쓰일 때 "Swift 6에서 에러" 경고 ~40건(2026-07-08 전체 리빌드로 확인, 증분 빌드가 가려왔음). 부분 수정(`decodeCourseSegments` nonisolated)은 경고가 옆으로 옮겨갈 뿐임을 실험으로 확인 — 타입 단위 일괄 정리 필요 ② **명시 @MainActor 감사** — Domain **프로토콜** `LocationServiceProtocol`·`CoursePlanningServiceProtocol`에 붙어 있어 모든 구현체를 main으로 강제(재검토 대상, 사용자 지적). `CourseEditSession`·`DependencyContainer`·`ContinuationBroadcaster`도 계층별로 "정말 main 전용인가" 판정 ③ **Sendable 정합** — 값 타입 Sendable 명시, 클로저 경계(`@Sendable`) 정리 ④ **동시성 문법 현대화** — `DispatchQueue.main.asyncAfter`(MapViewRepresentable 탭 판별 타이머 등) → `Task`/`Clock` 검토, delegate 콜백의 `Task { @MainActor in }` 패턴(CoreLocationService) 점검 ⑤ 최종적으로 **`SWIFT_VERSION = 5.0 → 6` 전환** + 경고 0 확인 / *why now not:* 런타임 동작 문제는 없음. Domain·Infrastructure·테스트 전반을 건드리는 MVP급 작업이라 별도 사이클로 — 결정 근거는 `project-decisions.md`에 기록하며 진행 / *trigger:* 다음 persistence 확장 MVP(달리기 기록) 착수 전 정지작업으로 우선 검토 → MVP12 `swift6-migration` 마일스톤으로 편입(2026-07-10). *resolved:* 2026-07-11 — Task 1~7로 ①~⑤ 전부 완료 후, 실기기 크래시 발견(코스 불러오기 시 MapKit 오버레이, 커밋 `18fa11a`)을 계기로 격리 기본값 전략을 반대 방향(기본 nonisolated + 명시 `@MainActor`)으로 재전환(Task 7c, 커밋 `85e4899`). 178개 테스트 전체 통과, 경고 0, 브랜치 리뷰(머지 안전 판정)·실기기 QA 체크리스트 전부 통과 후 `main`에 병합(`6e2a968`). 결정 상세: `docs/agent-rules/project-decisions.md`. `done`

## MVP8 킥오프 논의 (2026-07-02)

겹치는 경로 렌더링을 좌표 오프셋(α)으로 정하면서, α의 약점별 대비책을 트리거와 함께 보관.

- [ ] **겹침 렌더링 — 단일 코스 색 + 방향 화살표(β)** — *what:* 지도 위 구간별 색칠을 접고 단일 색 + 진행 방향 화살표로 표현, 구간 색·거리는 패널 전담 / *trigger:* α(좌표 오프셋) 적용 후에도 실기기 QA에서 구간 색·라벨 혼동이 남으면. MVP7 시각 언어(구간 색+라벨)를 상당 부분 되돌리는 방향 전환이므로 근거 없이 착수하지 않는다. `open`
- [ ] **겹침 렌더링 — 화면 포인트 기준 오프셋(안 3 원안)** — *what:* 오프셋 간격을 미터가 아닌 화면 포인트로 유지해 어느 줌에서도 겹친 선이 분리돼 보이게(지하철 노선도 방식). 줌마다 평행선을 재계산하는 커스텀 렌더러 필요 — 마일스톤 1개 규모 / *trigger:* α의 줌아웃 병합(축소 시 3~4m 간격이 1px 미만으로 줄어 한 줄로 보임)이 실사용에서 문제되면. `open`

## MVP4 (2026-06-27) 실기기 피드백

- [x] **핀치 줌 UX 개선** — *where:* 그리기 모드 / *now:* `isZoomEnabled = false` + 커스텀 `UIPinchGestureRecognizer`로 구현 / *desired:* `drawGR.maximumNumberOfTouches = 1`이므로 충돌 없이 `isZoomEnabled = true` 고정 + 커스텀 pinchGR 제거로 네이티브 핀치 복원 가능 → MVP8 `course-ux-polish`에서 해결(네이티브 핀치 복원, 체감 개선은 미미 — 위 MVP8 QA 섹션 참고). `done`
- [x] **탭↔그리기 경로 이어붙이기** — MVP5에서 해결: CourseSegment 세그먼트 배열 모델 + history 기반 탭↔그리기 이어붙이기. `done`

## MVP12 design-apply P2 (2026-07-11 킥오프에서 이연)

- [x] **바텀시트 드래그로 높이 조절** — *what:* 탭 토글(P1)만으로는 손가락으로 시트를 끌어 임의 높이로 조절할 수 없음 / *trigger:* 실사용에서 탭 토글이 답답하다는 피드백이 나오면. 트리거 충족으로 2026-07-12 구현 완료 — 그래버에 DragGesture 추가(임계값 40pt, 두 detent 스냅), 탭 토글과 공존. `done`
- [x] **구간 선택 시 지도 위 halo 하이라이트** — *what:* 리스트에서 구간 선택 시 지도의 해당 폴리라인에 후광 효과 추가 / *trigger:* 카메라 핏만으로 선택 구간 식별이 어렵다는 피드백이 나오면. 트리거 충족으로 2026-07-12 구현 완료(`SegmentHaloPolyline`). `done`
- [ ] **km 마커 뱃지** — *what:* 경로를 따라 1km 간격 마커 표시 / *trigger:* 장거리 코스에서 거리 감각 파악이 어렵다는 피드백이 나오면. `open`
- [ ] **그리는 중 점선 행진 애니메이션** — *what:* 손으로 그리는 스트로크에 이동하는 점선 효과 / *trigger:* MapKit 오버레이로 구현 난이도가 있어 별도 검증 필요 — 시각적 임팩트 대비 우선순위 낮음. `open`
- [ ] **다크 모드 폴리라인 글로우** — *what:* 다크 테마에서 네온 민트 경로에 발광 효과 추가 / *trigger:* 다크 모드 실사용 피드백에서 케이싱만으로 부족하다는 의견이 나오면. `open`
- [ ] **커스텀 저장 다이얼로그** — *what:* 시스템 알럿 대신 디자인 시스템을 입힌 커스텀 다이얼로그 / *trigger:* 시스템 알럿이 브랜드 일관성을 크게 해친다는 판단이 서면. 킥오프에서 시스템 알럿 유지가 기본값으로 확정(2026-07-10 스펙 §3.2). `open`

## MVP13 킥오프 논의 (2026-07-13)

- [x] **러닝 오디오 안내 (km 경계 음성 안내)** — *what:* 러닝 시작·1km 경계마다 거리·페이스를 음성(TTS)으로 안내 / *why:* 뛰는 중에는 화면 확인이 어려움 — **확정 예정 기능**(트리거 대기 아님, 사용자 확정 2026-07-13). MVP13 구조상 `RunSession` 데이터의 소비자 하나를 추가하는 일이라 스키마 변경 없음. 새로 필요한 결정은 백그라운드 음성 재생·오디오 ducking뿐 → MVP14 `run-splits-audio` 마일스톤으로 편입(2026-07-15 킥오프에서 덕킹·발화 내용·백그라운드 오디오 결정 완료). 스펙: `docs/superpowers/specs/2026-07-15-run-experience-design.md`. `planned`

## MVP12 design-apply 실사용 피드백 (2026-07-13)

- [ ] **FAB 아이콘 버튼(되돌리기/앞으로/초기화/현재위치) 시각적 눈에 띄는 정도** — *where:* `CoursePlannerPage.editingFabGroup`/`recenterButton`, glass 아이콘 버튼 스타일 / *now:* 같은 세션에서 "가려져서 기능을 못 하는" 버그는 고쳤지만(FAB 앵커를 collapsed 시트 실측 높이 기준으로 변경), 사용자가 별도로 "버튼이 눈에 안 띈다"고 지적 — glass 스타일이 지도 배경과 대비가 약해 존재 자체를 알아채기 어려움 / *desired:* 미정 — 실기기로 며칠 써보고도 여전히 불편하면 대비(배경 불투명도, 테두리, 아이콘 색상 등) 조정. `open`

## MVP13 run-tracking (2026-07-14) 실기기 QA 피드백

- [x] **강제종료 후 잠금화면 카드 정리 — 실기기 확인 완료** — *where:* `RunActivityController.endOrphanedActivities()`(최종 브랜치 리뷰에서 발견된 고아 Live Activity 버그의 수정, `Activity<RunActivityAttributes>.activities` 스윕 + `.immediate` 종료) / *now:* 코드 구현 완료 + 리뷰어 승인(2026-07-14). MVP13 QA·MVP14 사이클 1(run-pause-resume) QA에서 두 차례 이월된 뒤, MVP14 사이클 2(run-splits-audio) 실기기 QA에서 사용자가 직접 수행(강제종료→재실행→잠금화면 확인)해 카드가 정상적으로 사라지는 것을 확인(2026-07-17). `done`
- [ ] **건물 밀집지에서 GPS 정확도 차이 — 환경상 미확인** — *where:* 체크리스트 시나리오 8 / *now:* 2026-07-14 QA 당시 주변에 높은 건물이 밀집한 곳이 없어 확인 못함(환경 의존 항목이라 버그 아님, 정확도 필터링 로직 자체는 단위 테스트로 이미 커버됨). MVP14 사이클 2(run-splits-audio) QA에서도 다시 실어 전달했으나 이번에도 기회가 없어 확인 안 함(2026-07-17, 다음 기회로 재이월) / *trigger:* 건물 밀집 지역에서 실사용 기회가 생기면 확인. `open`
- [ ] **배터리 소모 체감 — 짧은 테스트로는 확인 안 됨** — *where:* 체크리스트 배터리 항목 / *now:* 2026-07-14 QA가 5분 정도의 짧은 테스트라 체감 가능한 배터리 소모가 관찰 안 됨(정상 — 최고 정확도 GPS + 화면 꺼져도 유지가 배터리를 쓰긴 하지만 다른 러닝 앱들도 동일한 방식). MVP14 사이클 1(run-pause-resume)·사이클 2(run-splits-audio) QA에서 두 차례 더 이월 전달했으나 이번에도 20분 이상 실행 기회가 없어 확인 안 함(2026-07-17, 다음 기회로 재이월) / *trigger:* 20~30분 이상의 실제 러닝 기회가 생기면 체감 재확인. `open`
- [x] **같은 경로 왕복 2회 실행 — DEBUG 덤프 원시 데이터 대조 검증** — *where:* 사이클 2 킥오프 전 사용자 요청으로 실행한 추가 검증(2026-07-14, 약 0.99km 경로를 반대 방향으로 2회 실행) / *now:* 두 실행의 DEBUG 샘플 덤프(각 172~173개 샘플)를 직접 재계산해 화면 표시값과 대조 — 거리(986.3m/994.5m vs 표시 0.99km 양쪽), 평균 페이스(12'28.4"/12'53.3" vs 표시 12'28"/12'54"), 고도 상승(10.26m/17.85m vs 표시 10m/18m) 전부 오차 없이 일치. 정확도 필터(hAcc=1414m 샘플 정상 rejected)와 고도 필터(vAcc=16으로 임계값 초과한 altitude=56.2m 이상치가 고도 계산에서 정상 제외)도 실전 데이터로 검증됨. 왕복 거리 재현성은 약 0.9% 오차. 버그 없음 — `RunTrack`/`RunSession` 계산 로직이 실기기 데이터에서 설계대로 동작함을 확인. `done`

## MVP14 run-pause-resume (2026-07-16) 논의

- [ ] **일시정지 구간 지도 선 — 다르게 표시(점선/옅은 색)** — *where:* `RunPageViewModel.displayedCoordinates`(`session.track.samples`를 그대로 매핑) + `RunPage.swift`의 `MapPolyline(coordinates:)` 단일 선 렌더링 / *now:* 일시정지 중 샘플은 아예 무시되지만(`RunSession.ingest`), 재개 직후 첫 샘플은 `markGap()`으로 거리 계산에서만 제외되고 좌표 자체는 `track.samples`에 그대로 붙는다 — 그 결과 지도 폴리라인은 일시정지 직전 지점과 재개 직후 지점을 직선으로 그대로 이어 그린다(거리·시간·저장 데이터에는 그 구간이 전혀 포함되지 않음 — 시각적 표현만의 문제). 완전히 끊는 방식(구간별 `MapPolyline` 분리)도 검토했으나, 끊긴 자리가 GPS 신호 유실처럼 오해될 수 있어 기각(2026-07-16 논의) — 스트라바 등 대다수 러닝 앱도 일시정지 중 이동은 직선으로 잇는 것이 표준 동작이라 지금은 그대로 둠(A) / *desired:* 실사용 중 "지도 선이 이상하게 이어진다"는 체감 불편이 실제로 나오면, 그 구간만 점선/반투명 등으로 구분 표시(C)하는 개선 검토. `open`

## MVP14 run-splits-audio (2026-07-17) 실기기 QA 피드백

- [ ] **연속 발화(일시정지·재개·km 경계가 짧은 간격으로 겹침) — 부분 확인만 됨** — *where:* 체크리스트 시나리오 6, `SpeechVoiceAnnouncer`의 `pendingCount` 기반 오디오 세션 유지 로직 / *now:* 사용자가 실기기에서 일시정지→재개→km 경계를 짧은 간격으로 몰아서 테스트, "어느 정도 되는 것 같다"로 확인했으나 음악 볼륨이 안 튀는지·발화 순서가 확실히 안 겹치는지까지 엄밀하게 재현하며 확인하지는 못함(타이밍 맞추기 어려움). 코드 리뷰에서 `pendingCount` 큐 관리 로직 자체는 이미 검증됨(활성화 실패 시 카운터 미증가 등 엣지케이스 포함) / *desired:* 실사용 중 소리가 겹치거나 끊기는 문제가 실제로 체감되면 그때 원인 조사. 낮은 위험(AVSpeechSynthesizer 자체 큐가 있어 최악의 경우도 순서만 밀릴 뿐 크래시 없음). `open`

## MVP15 킥오프 논의 (2026-07-17)

- [x] **러닝 탭 UI 구조 개편 (MVP16 후보 씨앗)** — *what:* 러닝 탭 전반의 표현·구조 재검토 — 대기 화면 지도 제거/대체 검토, 탭·시트 형태 변경, NRC(나이키런)식 거리/시간 표현 문법 참고(트래킹·요약·기록 상세, Trace 디자인 토큰 위에서). *why deferred:* 사용자 구상이 아직 안 익음(2026-07-17 킥오프에서 명시적 이연) — MVP15 실사용 중 아이디어를 이 항목에 계속 쌓고, MVP16 킥오프 때 MVP12 방식(design-direction 문서 전용 사이클)으로 시작. *update(2026-07-19):* 방향 스펙 `docs/superpowers/specs/2026-07-18-run-ui-restructure-direction.md` 작성 완료(항목 1 탭/시트/페이지 구조 + 항목 2 그리기 제스처) + 사전 리뷰 보완점 반영 — 킥오프 재료 준비됨. *resolved(2026-07-19):* MVP16 킥오프에서 마일스톤 4개(ui-direction/tab-restructure/run-fullscreen/draw-gesture)로 편입 확정. 킥오프 스펙: `docs/superpowers/specs/2026-07-19-mvp16-ui-restructure-kickoff-design.md`. `planned`

## MVP14 run-goal (2026-07-17) QA 준비 중 발견

- [ ] **GPS 거리 이상치(비정상 점프) 방어 로직 없음** — *where:* `RunSession.ingest(_:sessionStart:)`(정확도만 검사, `maxHorizontalAccuracyMeters = 30`) + `RunTrack.append`(직전 샘플과의 하버사인 거리를 조건 없이 그대로 누적) / *now:* run-goal 실기기 QA를 GPX 파일로 준비하던 중 발견 — Xcode의 Simulate Location이 GPX 파일 끝에 도달하면 자동으로 처음 웨이포인트로 되돌아가 반복 재생하는데(Xcode 자체 동작이라 앱에서 제어 불가), 이때 발생하는 "순간이동" 점프가 정확도 값은 정상이라 필터를 그대로 통과해 총 거리에 그대로 합산됨(예: 6km 지점에서 되감겨 재생을 계속 두면 11km처럼 부풀려짐). 연속 샘플 간 거리/속도를 검사하는 로직이 코드에 전혀 없음을 직접 확인(2026-07-17). 실제 GPS 사용에서도 이론상 같은 취약점이지만(터널 통과 직후 등 정확도는 정상인데 위치만 튀는 드문 경우), 지금까지의 모든 실기기 QA(MVP13, run-splits-audio, run-pause-resume)에서 이런 사례가 보고된 적은 없음 — 지금은 GPX 테스트 도구가 드러낸 이론적 결함이지 실사용 버그로 확인된 건 아님. run-goal QA는 GPX 재생이 끝나는 시점에 맞춰 종료 버튼을 눌러 이 문제를 피해가는 것으로 진행(체크리스트에 안내 추가) / *desired:* 미정 — 임계값(얼마나 빠른 이동을 "비정상"으로 볼지) 설계가 까다롭고 근거 없이 만들면 정상 기록을 잘못 잘라내는 반대 방향 버그가 생길 수 있어, 지금 당장 구현하지 않기로 결정(2026-07-17, 사용자 판단). *trigger:* 실제 기기(GPX 아닌 진짜 GPS)로 뛰는 중 거리가 비정상적으로 튀는 사례가 실사용에서 확인되면 그때 임계값·필터 설계 착수. `open`

## MVP15 run-waypoints (2026-07-19) 실기기 QA 피드백

- [x] **포인트 구간을 지도 위에 경로(폴리라인)로 표시** — *what:* 기록 상세 지도에서 지금은 번호 마커만 찍히는데, 코스 탐색 때처럼 포인트 구간 자체를 지도 위에 선으로 그려서 지도만 보고도 구간 구성을 빠르게 파악할 수 있게 해달라는 실사용 QA 피드백(2026-07-18) / *where:* `RunPage+HistoryComponent.swift`의 `RunRecordDetailView` 지도(현재 `ForEach(... id: \.offset)`로 번호 마커만 렌더링) / *why deferred:* run-waypoints 사이클이 이미 리뷰 완료·병합 대기 상태라 지금 끼워넣으면 사이클이 커짐. 코스 탐색에서 "구간별 색칠 vs 단일색+화살표"를 놓고 별도로 논의했던 것과 같은 급의 UI 설계 결정이 필요해 별도 마일스톤으로 브레인스토밍 필요(2026-07-19 판단, 사용자 동의). *resolved(2026-07-21):* run-fullscreen Task 5에서 구현 완료 — 샘플 스트림을 포인트 타임스탬프로 자르는 `RunPathSegmentsCalculator`(Domain 순수 함수)가 지도 구간과 구간 표에 같은 1기반 번호로 `SegmentPalette` 색을 공유시킨다. 실기기 QA 통과(2026-07-21). 킥오프 스펙: `docs/superpowers/specs/2026-07-19-mvp16-ui-restructure-kickoff-design.md`. `done`

## MVP16 tab-restructure (2026-07-19) 풀시트-topBar 완전 밀착 보류

- [x] **풀 디텐트에서 topBar 완전 무틈 커버 (장식 레이어 방식)** — *what:* sheetTopMargin을 11pt로 낮춰도 ~3pt 미세한 틈이 남는다(측정 기반 안전선이라 더 못 줄임). 완전히 틈 없이 덮으려면 `maxSheetHeight` 계산(측정값 기반, 다이내믹 아일랜드 침범 버그 이력 있음)과 무관한 순수 장식용 커버 레이어를 추가하는 방법(옵션 C)이 있으나, 이 레이어 자체가 "안전영역 경계에 가깝게 커지는 새 형제 뷰"가 되어 topBar의 암묵적 안전영역 배치를 흔들 위험이 있어 검증 없이는 채택 보류(2026-07-19, 사용자 판단 — 지금은 A안 3pt 틈으로 진행). *trigger:* 실사용 중 3pt 틈이 실제로 거슬린다는 피드백이 나오면, 장식 레이어를 추가하고 topBar 위치가 흔들리지 않는지 실측 검증부터 한 뒤 채택. *해결(2026-07-21):* **트리거 충족** — 실기기 QA에서 사용자가 남은 띠를 지적("이것까지 다 덮히도록은 할 수 없나, 대신 다이내믹 아일랜드는 덮지 않도록"). **장식 레이어(옵션 C)는 필요 없었다.** 같은 세션에서 이중 차감 회귀를 고치면서 `maxSheetHeight`가 안전영역 측정값을 아예 안 쓰게 됐고(`- topSafeAreaInset` 제거), 그 결과 11pt 여백의 존재 이유였던 되먹임 오차가 시트 높이에 닿을 경로 자체가 사라졌다. 그래서 `sheetTopMargin`을 11 → **0**으로 낮추는 것만으로 해결 — `pageHeight`가 정의상 안전영역 제외 높이라 여백 0이면 시트가 안전영역 경계, 즉 다이내믹 아일랜드 **바로 아래**에서 구조적으로 멈춘다(요구 조건이 보장됨). *검증:* 풀 디텐트 고정 빌드에서 `pageHeight=722.0`이 접힘/풀 양쪽 동일, `safeAreaInsets.top`도 풀에서 62.0 유지 — 예전의 "시트가 커지면 안전영역이 줄어드는" 현상 미재현. 여백 0 스크린샷에서 지도 띠 소멸 + 다이내믹 아일랜드 노출 유지 확인. 참고로 4pt 후보도 만들어 비교했으나 육안 차이가 없어 0으로 확정(사용자 요청이 "완전히 덮기"). *주의:* 이 상수에 붙어 있던 "11pt 이하로 절대 낮추지 말 것" 경고 주석은 근거와 함께 교체했다 — 되돌리기 전에 그 주석부터 읽을 것. **실기기 확인 완료(2026-07-21, 사용자 — 여백 0에서 다이내믹 아일랜드 미침범, 정상 동작).** `done`
- [ ] **시트 콘텐츠 영역에서도 드래그로 축소(지도 앱 스타일)** — *what:* 지금은 시트를 접는 드래그 제스처가 그래버·헤더 영역에만 걸려 있어(`sheetDragGesture`, `CoursePlannerPage+BottomSheetComponent.swift`), medium/full 상태에서 구간 리스트 위를 드래그해도 시트가 안 줄어든다. 네이버/애플 지도 앱처럼 "리스트가 맨 위로 스크롤된 상태에서 더 아래로 당기면 시트가 축소되는" 동작을 원함(2026-07-19 실기기 피드백). *why deferred:* 리스트가 `ScrollView`라 리스트 자신의 팬 제스처와 시트 드래그 제스처가 충돌한다(Task 3에서 이미 리스트 안 스와이프가 씹히는 것을 확인함 — `ScrollView`가 시작 지점 터치를 그대로 흡수). 스크롤 위치·제스처 상태를 함께 조율하는 설계가 필요해 즉흥 구현 대신 별도 세션에서 UX 설계부터 다시 하기로 함(2026-07-19, 사용자 판단 — "이후에 다시 생각을 하고 나서 UX설계 하는 방식으로"). *trigger:* 다음 세션에서 유저 액션 플로우를 구체화한 뒤 브레인스토밍/플랜 작성으로 착수. `open`
- [x] **가로모드에서 코스 탭 시트를 펼치면 레이아웃이 무너짐 — 원버그 수정 후 파생 회귀, 설계 재검토로 보류** — *what:* 실기기 QA 중 발견(2026-07-20) — 가로에서 시트를 medium/full로 올리면 탭바가 화면 아래로 밀려나고 시트가 위로 뚫리는 원버그. *원인·수정:* `docs/superpowers/plans/2026-07-20-landscape-sheet-overflow.md`의 3중 방어(RootView 구조 클램프 → 시트 예산 pageHeight min-클램프 → ratchet size class별 분리)로 수정, 실기기 확인 완료(사용자 확인 — 원버그 재현 안 됨). *파생 회귀 3건(같은 수정에서 발생, 실기기 QA 2026-07-20):* ① 가로 collapsed→medium 전환 시 topBar/FAB가 화면 위로 밀림 — 크롬 VStack에 `.frame(height: pageHeight, alignment: .top)` 추가로 수정, **실기기 확인 완료.** ② 세로 풀시트에서 topBar가 더 이상 살짝 덮이지 않음(원래 `e872c9a`가 의도한 "~3pt 거의 안 보이는 틈"이 아니라 topBar 전체가 뚜렷하게 보임) — 원인 미확인. 회귀인지, 예전에 ①과 같은 종류의 `.center` 오버플로 버그가 topBar를 밀어올려 우연히 틈이 좁아 보이던 게 이번에 사라지며 원래 있던 틈이 드러난 것인지 구분 안 됨. ③ 다크모드 가로에서 탭바/시트 옆에 검은 여백 — `bottomSheet`를 ZStack 형제에서 `.overlay`로 분리하고 `CoursePlannerPage` 루트에 `.ignoresSafeArea(edges: .horizontal)`을 추가해봤으나, **시뮬레이터 픽셀 샘플링에서는 좌우 끝까지 닿는 것으로 확인됐음에도 실기기 재확인 결과 여전히 재현됨** — 원인 재조사 필요(시뮬레이터·실기기 간 ignoresSafeArea 처리 차이 의심, 미검증). *설계 질문(2026-07-20, 사용자 제기):* ②③을 쫓다 보니 "시트/탭바를 가로에서 화면 끝까지 늘린다"는 접근 자체가 다이내믹 아일랜드 겹침, FAB(플로팅 버튼) 배치 등 새 UX 질문을 만들어낸다는 게 드러남 — 원래 이 플랜의 YAGNI 경계("가로 전용 레이아웃 최적화는 범위 밖")가 맞았던 셈. *why deferred:* 사용자 판단(2026-07-20) — 패치를 더 쌓기보다 시트 구조 자체를 다시 설계할지부터 정해야 함. 이 마일스톤이 이미 많이 밀려 다른 밀린 작업들을 먼저 진행하기로 함 — 다음 세션(다른 모델과 브레인스토밍 가능)에서 재개. *trigger:* 시트 폭/배치에 대한 설계 방향이 정해지면 그에 맞춰 ②③ 재작업. *상세:* `docs/superpowers/plans/2026-07-20-landscape-sheet-overflow.md` 끝 "세션 마무리 메모", `docs/qa/2026-07-20-landscape-sheet-device-checklist.md` 시나리오 5·6. *branch 상태 정정(2026-07-21):* 세션 마무리 메모와 이 항목은 원래 `feature/mvp16-landscape-sheet-overflow`를 "미병합, 유지"로 적어두었으나, **실제로는 그 브랜치의 커밋들이 전부 `main`에 병합됐고 브랜치는 삭제된 상태다**(커밋 `631ed10`·`4772313`·`bb4a37b`·`a224185`·`eed162e`·`93b2622`·`2f79caa`·`22c3b23` — 시도했다가 실패로 판명된 overlay 분리·`ignoresSafeArea` 추가 `93b2622`까지 포함). 즉 **위 파생 회귀 ②③은 지금 `main`에 살아 있다.** 재작업 시 브랜치를 되살리려 하지 말고 `main`에서 새로 판다. *스코프 결정(2026-07-21, 브레인스토밍):* 이 항목은 MVP16에 묶어두지 않고 일반 백로그로 돌린다 — 설계 착수 여부가 다음 MVP가 이 화면을 다시 건드리는지에 달려 있어서, 고립된 상태로 지금 설계를 확정하면 다음 MVP 방향과 안 맞을 위험이 있다는 판단(사용자 확인). 새 마일스톤 착수 시 백로그를 훑는 기존 워크플로로 자연스럽게 재검토된다 — 별도 스펙 문서는 작성하지 않음(백로그 항목 자체가 콜드 픽업에 충분하다고 판단). *스코프 종결(2026-07-21):* **아이폰 세로 전용 고정 결정으로 이 항목의 가로 관련 부분은 전부 무효화됐다** — 원버그(가로 시트 오버플로)도, 파생 회귀 ③(다크모드 가로 검은 여백)도, 보류했던 "시트 폭/배치 재설계"도 가로모드 자체가 없어져 고칠 문제가 사라졌다. 결정과 근거·되돌리는 트리거는 `docs/agent-rules/project-decisions.md`. 단 **파생 회귀 ②는 세로모드 버그라 살아남으며, 아래 별도 항목으로 분리**했다. `done`(가로 부분 무효화)

- [x] **세로 풀시트에서 topBar가 안 덮임 — 원인 미확인** — *what:* 세로에서 시트를 풀 디텐트로 올리면 원래 의도(`e872c9a`)는 "시트가 topBar를 살짝 덮어 ~3pt만 보임"인데, 지금은 topBar가 통째로 뚜렷하게 보인다. 위 가로모드 항목의 파생 회귀 ②였으나 가로 잠금과 무관하게 남아 별도 항목으로 분리(2026-07-21). *where:* `CoursePlannerPage+BottomSheetComponent.swift`, `SafeAreaInsetLatch.swift`, `CoursePlannerPage.swift` / *now:* **지금 `main`에 있음**(커밋 `631ed10`~`22c3b23` 병합됨). 순수 시각 문제로 기능 영향은 없다. 원인이 회귀인지, 아니면 예전에 `.center` 오버플로 버그가 topBar를 밀어올려 우연히 틈이 좁아 보이던 게 이번 수정으로 사라지며 **원래 있던 틈이 드러난 것**인지 구분이 안 된 상태 — 후자라면 이 항목은 아래 "풀 디텐트 무틈 커버" 항목과 같은 문제다. *주의:* 이 영역은 **원인 모른 채 건드리면 악화된 이력**이 있다 — overlay 분리 + `ignoresSafeArea` 시도가 시뮬레이터 픽셀 샘플링은 통과했는데 실기기에서 실패했고(커밋 `93b2622`), 그 실패 코드가 지금도 `main`에 남아 있다. 눈감고 고치지 말고 원인부터 확정할 것. *다음 단계:* `superpowers:systematic-debugging`으로 원인 규명 → 그 결과에 따라 즉시 수정할지, 시트를 다시 만질 다음 MVP에 편입할지 결정. 가로 잠금으로 죽은 코드가 된 `SafeAreaInsetLatch`의 size class 분기와 `TraceTabBar.isCompactHeight` 정리도 **이 원인 규명이 끝난 뒤**에 한다(원인 후보라 먼저 지우면 증거 소멸). *해결(2026-07-21):* **회귀 확정 — 사용자 기억("이전엔 됐는데 시트·탭 수정하다 달라졌다")이 맞았다.** 원인은 커밋 `4772313`에서 시트 예산 앵커를 `mapHeight`(상단 안전영역 **포함**)에서 `pageHeight`(안전영역 **제외**)로 바꾸면서, `mapHeight` 시절에만 옳았던 `- topSafeAreaInset` 항을 그대로 남긴 것 — 안전영역을 두 번 빼고 있었다. 임시 계측 실측(iPhone 17 Pro 시뮬레이터): `pageHeight=722`, `safeAreaInsets.top=62`, `mapHeight=784(=722+62)` → 잘못된 예산 `722-62-11=649`, 옳은 예산 `784-62-11=711=722-11`. **차이 정확히 62pt** = 드러난 topBar 띠. *수정:* `- topSafeAreaInset` 항 제거(앵커는 `pageHeight` 유지 — `mapHeight`는 실측에서 784↔812로 흔들려 되돌리면 안 된다). 계산은 뷰에서 `SheetHeightBudget`(순수 enum, `FabLayoutPolicy` 관례)으로 분리하고 테스트로 못박았다 — 이 계산은 경고 하나 없이 조용히 틀리는 종류라서. *검증:* 초기 디텐트를 임시로 `.full`로 고정한 빌드에서 시트가 topBar를 다시 덮는 것을 스크린샷으로 확인(시트 상단 ≈ 안전영역 62 + 여백 11), 전체 테스트 350개 통과. 시트 그래버가 접근성 노드가 아니라 드래그 합성이 안 되므로 실제 드래그로 풀 디텐트에 도달하는 경로는 실기기 QA로 넘겼고, **실기기 확인 완료(2026-07-21, 사용자 — 손으로 끌어올렸을 때 topBar가 정상적으로 덮임).** `done`

- [ ] **가로모드 재도입 재검토 — 트리거 대기** — *what:* 2026-07-21에 아이폰 세로 전용으로 고정했다(근거는 `docs/agent-rules/project-decisions.md`). 원래 가로를 지원하려던 이유는 "지도에 코스를 그릴 때 화면이 넓으면 편할 것"이라는 가설이었고, MVP16 `draw-gesture`가 그리기 모드에서도 한 손가락 지도 이동을 항상 살려놨기 때문에 그 답답함이 이미 해소됐을 것이라는 **추정** 위에서 잠근 것이다. *trigger:* 새 한 손가락 팬 방식으로 실제 코스를 그려봤는데도 화면이 좁아 답답하다는 게 실사용에서 확인되면 → 가로를 되살린다. 단 예전처럼 "기본값으로 켜두고 깨지면 패치"가 아니라, 시트 폭·탭바·FAB 배치·다이내믹 아일랜드 겹침까지 **의도적으로 설계하는 별도 마일스톤**으로 착수한다. 되돌리는 비용 자체는 빌드 설정 2줄로 거의 0. `open`

## MVP16 run-fullscreen (2026-07-21) 실기기 QA 피드백

- [ ] **종료 전 일시정지 요구가 실익이 있는지 재검토 필요** — *what:* run-fullscreen에서 "달리는 중엔 종료 버튼 자체가 안 보이고, 일시정지를 먼저 눌러야 종료 버튼이 나타난다"로 바꿨다(ui-direction §3 확정, Task 3). QA 체크리스트 시나리오 2-4에 대해 사용자가 실제로 뛰어보기 전에 미리 든 생각(2026-07-21): 종료 버튼은 원래도 즉시 종료가 아니라 몇 초간 길게 눌러야 종료되는 홀드 방식(MVP15 run-detail-polish)이라, 이 홀드 자체가 "종료 의사를 계속 유지해야 함"을 보장하므로 실수 방지 목적이라면 이미 충분할 수 있고, 일시정지-먼저 요구가 추가로 필요한지 의문이 든다는 의견. *why deferred:* 실제 실기기 러닝으로 검증 전 단계의 사전 의견이라, 직접 뛰어보고 답답함을 느끼는지 확인한 뒤 판단하기로 함 — 지금 코드를 바꾸지 않는다(ui-direction §3는 이미 한 번 사용자가 확정한 결정이라 되돌리려면 실사용 근거가 먼저 있어야 함). *trigger:* 실기기로 실제 러닝 QA를 마친 뒤에도 여전히 답답하다는 판단이 서면, 일시정지 요구를 없애고 홀드 종료만으로 충분한지 재설계 논의. `open`
