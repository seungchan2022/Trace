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

- [ ] **앱 시작 시 카메라 점프 제거** — *where:* 앱 진입 / *now:* 전체 지도 → async 완료 후 줌인 점프 / *desired:* 마지막 카메라 영역을 UserDefaults에 저장·복원 + CLLocationManager 캐시 위치로 동기 초기화. 첫 실행은 폴백+애니메이션 이동. 상세: Apple Maps 등 프로덕션 앱 패턴 리서치 완료. `open`
- [ ] **비연속 구간 그리기 시 이상한 결과** — *where:* 그리기 모드 / *now:* 이미 그린 경로의 끝이 아닌 곳에서 새로 그리면 핀이 뒤섞임 / *desired:* 경로 끝에서만 연장하거나, 비연속 그리기 시 적절한 처리(구간별 독립 관리/연결점 감지 등). `open`
- [ ] **그리기 중 지도 이동 UX** *(기획 필요)* — *where:* 그리기 모드 / *now:* 지도를 이동하려면 탭 모드로 전환해야 하는데 전환 시 그리기 결과가 초기화됨 / *desired:* 그리기 중에도 지도 이동 가능 (2손가락 패닝, 잠금/해제 모드, 등). brainstorm 필요. `open`
- [ ] **스로틀 한계 측정 + 모니터링** — *where:* 빠른 연속 그리기 / *now:* 캐시+디바운스로 체감 개선됐으나 많은 수의 연속 드래그 시 여전히 에러 발생 / *desired:* route 호출 횟수 로깅으로 정확한 한계 측정, 에러 발생 시 사용자 안내 개선. MKDirections 근본 한계는 맵매칭 제공자 전환으로. `open`

## 기술부채

- [ ] **MKDirections 스로틀 완화** *(다음 MVP 1순위)* — *now:* 편집마다 전체 재라우팅 → 60초당 50요청 한계(`GEOErrorDomain Code=-3`) / *desired:* ① 라우팅한 구간 캐싱(새 구간만) ② 샘플 간격↑/디바운스 ③ 근본책: 맵매칭 제공자(Tmap/Valhalla, 1요청). `project-decisions.md`의 MapKit 교체 트리거와 연결. `open`
- [ ] **테스트 시뮬레이터 iOS 버전 전략** — *now:* iOS 18.5에서 `@Observable` malloc 크래시 발생해 iOS 26.5로 우회 중 / *desired:* 최소 지원 버전(iOS 17) 근처 런타임에서도 테스트. iOS 17 런타임 설치 또는 배포 전 멀티버전 테스트 전략 결정 필요. 상세: `docs/solutions/workflow-issues/ios18-observable-malloc-crash.md`. `open`
