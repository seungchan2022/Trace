# MVP1 완료 회고 — 러닝 코스 계획

> 작성일: 2026-06-22
> 범위: 지도에서 코스를 계획하고 거리를 재는 핵심 경험 (iOS / SwiftUI / MapKit)
> 마일스톤: route-planner(2026-06-17) + marker-draw-snap(2026-06-20) + folder-restructure(2026-06-17)

## 무엇을 만들었나 (마일스톤별)

### 마일스톤 1 — route-planner (지도 화면 + 두 포인트 거리재기)
- 지도(`Map`) 화면에서 두 지점을 찍어 도보 경로와 거리를 표시.
- 아키텍처: 포트-어댑터 + MVVM(`@Observable`). 도메인(`CoursePlanningServiceProtocol`)과
  MapKit 어댑터(`MapKitCoursePlanningService`)를 분리해, 라우팅 제공자를 나중에 교체 가능하게 둠.
- TDD: ViewModel 상태 전이 테스트를 먼저 작성 → 도메인 → 어댑터 → UI 순. UI 테스트 자동화까지.

### 마일스톤 1.5 — folder-restructure (CoursePlanning 도메인 정렬)
- route-planner 코드를 `architecture.md`가 정한 `Domain/Infrastructure/Pages` 레이어 +
  `CoursePlanning` 네이밍으로 이동·rename. (`RoutePlanner/Routing` → `CoursePlanning`)
- 별도 spec 없이 plan만으로 진행한 구조 정리 작업.

### 마일스톤 2 — marker-draw-snap (그리기 → 스냅 + 마커)
- 현재 위치로 시작하는 지도에서 손으로 경로를 그리면, 그 궤적을 실제 도보 길에 스냅해 거리와 함께 표시.
- `DrawnPathSampler`(순수 함수 다운샘플) → `snappedRoute(through:)`가 인접 점마다
  MapKit `MKDirections .walking`을 호출해 이어붙임. CoreLocation으로 현재 위치 부트스트랩.
- 그리기 제스처·미리보기를 전용 오버레이 레이어로 분리.

## 핵심 의사결정과 "왜"

- **포트-어댑터로 라우팅 제공자 격리** — MapKit이 한국 도보 경로에서 한계가 있을 수 있어,
  나중에 `KoreaCoursePlanningService` 같은 어댑터로 교체할 여지를 인터페이스로 열어둠.
- **스냅 충실도 ↔ 호출 수 긴장을 스파이크로 실측** — MKDirections는 궤적 입력이 없어 구간을
  독립 최적화한다. 성기면 모양 무시, 촘촘하면 스로틀. 스파이크 결과 **약 100–150m 간격 스위트스폿**을
  찾아 샘플러 기본값으로 삼음.

## Keep / Problem / Surprise

- **Keep** — TDD로 ViewModel부터 세운 흐름, 포트-어댑터 경계, 구현 전 스파이크로 불확실성 실측.
- **Problem** — marker-draw-snap plan의 Task 체크박스를 작업 중 실시간 갱신하지 않아
  플랜↔워킹트리가 어긋남(이번 아카이빙에서 소급 노트로 정리). 앞으로 `dual-tool.md` 규율대로
  체크박스를 단계마다 갱신해야 함.
- **Surprise** — MKDirections 60초당 50요청 한계(`GEOErrorDomain -3`)가 편집마다 전체 재라우팅에서
  빠르게 터짐. 충실도 문제로만 보던 게 실제로는 **요청 수 제약**이 더 큰 벽이었음.

## 남은 기술부채 / 후속 (→ `docs/backlog.md`)

- **MKDirections 스로틀 완화** (다음 MVP 1순위) — 구간 캐싱 / 디바운스 / 맵매칭 제공자 검토.
- 실기기 피드백 5건 — 위치 시작 화면, 그리기 모드 표시 명확화, 그린 코스 출발/도착 핀,
  상태 잔상 정리(탭↔그리기 공존, *결정 필요*), 권한 거부 UX(*제품 결정*).
- 미결 결정: Persistence(`project-decisions.md` — `undecided`). 경로 저장 도입 시 정함.

## 다음 방향

- backlog에서 다음 마일스톤을 고르거나, "러닝 코스 계획"을 넘어서는 새 가치를 MVP2로 킥오프.
- 기술부채(스로틀)와 실기기 피드백은 기존 MVP1의 보완이므로, 새 MVP로 묶기보다 backlog 소비로 처리 가능.
