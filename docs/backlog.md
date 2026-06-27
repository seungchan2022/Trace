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
- [ ] **테스트 시뮬레이터 iOS 버전 전략** — *now:* iOS 18.5에서 `@Observable` malloc 크래시 발생해 iOS 26.5로 우회 중 / *desired:* 최소 지원 버전(iOS 17) 근처 런타임에서도 테스트. iOS 17 런타임 설치 또는 배포 전 멀티버전 테스트 전략 결정 필요. 상세: `docs/solutions/workflow-issues/ios18-observable-malloc-crash.md`. `open`
- [x] **SwiftUI Map → MKMapView 교체** — MVP4에서 해결: MKMapView(UIViewRepresentable) 마이그레이션 완료, MKOverlay/MKAnnotation delegate 방식으로 전환. `done`

## MVP4 (2026-06-27) 실기기 피드백

- [ ] **핀치 줌 UX 개선** — *where:* 그리기 모드 / *now:* 커스텀 UIPinchGestureRecognizer로 구현했으나 내장 MKMapView 핀치보다 부자연스러움 / *desired:* 내장 MKMapView 핀치와 동등한 감도·가속도 구현 또는 대안 탐색. `open`
- [ ] **탭↔그리기 경로 이어붙이기** — *where:* CoursePlannerPage / *now:* 탭 모드(A→B 단일 경로)와 그리기 모드(스트로크 누적) 경로가 독립적. 모드 전환 시 경로 오버레이는 유지되지만 실제 이어붙이기는 안 됨 / *desired:* 탭으로 A→B 생성 후 그리기로 B→C 연장 (또는 반대 방향). course 데이터 모델을 세그먼트 배열로 확장하고 각 세그먼트를 append하는 방식으로 구조 변경 필요. `open`
