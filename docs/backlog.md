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
- [ ] **실시간 구간 패널 무한 확장** — *where:* 지도 우측 상단 구간 패널(펼침 상태) / *now:* 구간이 늘어날수록 목록 높이가 계속 커져서 화면을 덮을 수 있음 / *desired:* 최대 높이를 두고 그 이상은 스크롤. `open`
- [ ] **겹치는 경로 렌더링 방식** — *where:* 지도 위 구간 폴리라인 / *now:* 경로가 겹치면 최신 구간이 이전 구간을 그냥 덮어써서 아래 구간이 안 보임 / *desired:* 설계 논의 필요(오프셋, 스타일 구분 등) — brainstorm 대상. `open`

## MVP4 (2026-06-27) 실기기 피드백

- [ ] **핀치 줌 UX 개선** — *where:* 그리기 모드 / *now:* `isZoomEnabled = false` + 커스텀 `UIPinchGestureRecognizer`로 구현 / *desired:* `drawGR.maximumNumberOfTouches = 1`이므로 충돌 없이 `isZoomEnabled = true` 고정 + 커스텀 pinchGR 제거로 네이티브 핀치 복원 가능. `open`
- [x] **탭↔그리기 경로 이어붙이기** — MVP5에서 해결: CourseSegment 세그먼트 배열 모델 + history 기반 탭↔그리기 이어붙이기. `done`
