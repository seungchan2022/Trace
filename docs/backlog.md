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

- [ ] **강제종료 후 잠금화면 카드 정리 — 실기기 시각 확인 대기** — *where:* `RunActivityController.endOrphanedActivities()`(최종 브랜치 리뷰에서 발견된 고아 Live Activity 버그의 수정, `Activity<RunActivityAttributes>.activities` 스윕 + `.immediate` 종료) / *now:* 코드 구현 완료 + 리뷰어가 Apple 공식 API 사용법까지 확인해 승인(2026-07-14). 체크리스트 시나리오 10(강제종료→재실행→잠금화면 카드 사라짐 확인)을 사용자가 인지하지 못해 이번 QA 라운드에서는 손으로 확인 못함 / *desired:* 다음 실기기 QA 기회에 시나리오 10을 직접 수행해 카드가 실제로 사라지는지 확인. 실패해도 크래시·데이터손실 없는 낮은 위험(최악의 경우 카드가 예상보다 오래 남는 정도, iOS 자체 Live Activity 수명 상한도 있음). `open`
- [ ] **건물 밀집지에서 GPS 정확도 차이 — 환경상 미확인** — *where:* 체크리스트 시나리오 8 / *now:* 2026-07-14 QA 당시 주변에 높은 건물이 밀집한 곳이 없어 확인 못함(환경 의존 항목이라 버그 아님, 정확도 필터링 로직 자체는 단위 테스트로 이미 커버됨) / *trigger:* 건물 밀집 지역에서 실사용 기회가 생기면 확인. `open`
- [ ] **배터리 소모 체감 — 짧은 테스트로는 확인 안 됨** — *where:* 체크리스트 배터리 항목 / *now:* 2026-07-14 QA가 5분 정도의 짧은 테스트라 체감 가능한 배터리 소모가 관찰 안 됨(정상 — 최고 정확도 GPS + 화면 꺼져도 유지가 배터리를 쓰긴 하지만 다른 러닝 앱들도 동일한 방식) / *trigger:* 20~30분 이상의 실제 러닝 기회가 생기면 체감 재확인. `open`
- [x] **같은 경로 왕복 2회 실행 — DEBUG 덤프 원시 데이터 대조 검증** — *where:* 사이클 2 킥오프 전 사용자 요청으로 실행한 추가 검증(2026-07-14, 약 0.99km 경로를 반대 방향으로 2회 실행) / *now:* 두 실행의 DEBUG 샘플 덤프(각 172~173개 샘플)를 직접 재계산해 화면 표시값과 대조 — 거리(986.3m/994.5m vs 표시 0.99km 양쪽), 평균 페이스(12'28.4"/12'53.3" vs 표시 12'28"/12'54"), 고도 상승(10.26m/17.85m vs 표시 10m/18m) 전부 오차 없이 일치. 정확도 필터(hAcc=1414m 샘플 정상 rejected)와 고도 필터(vAcc=16으로 임계값 초과한 altitude=56.2m 이상치가 고도 계산에서 정상 제외)도 실전 데이터로 검증됨. 왕복 거리 재현성은 약 0.9% 오차. 버그 없음 — `RunTrack`/`RunSession` 계산 로직이 실기기 데이터에서 설계대로 동작함을 확인. `done`
