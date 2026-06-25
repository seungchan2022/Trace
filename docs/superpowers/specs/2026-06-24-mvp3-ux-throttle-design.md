# MVP3 — UX 개선 + 스로틀 강화

> MVP2 실기기 피드백 반영: 카메라 초기화, 그리기 UX, 스로틀 근본 완화.

## 범위

| # | 항목 | 마일스톤 후보 |
|---|------|---------------|
| 1 | 앱 시작 시 카메라 점프 제거 | camera-restore |
| 2 | 비연속 구간 그리기 시 이상한 결과 | drawing-direction |
| 3 | 그리기 중 지도 이동 UX | drawing-pan |
| 4 | 스로틀 한계 측정 + 모니터링 | throttle-hardening |
| 5 | MKDirections 스로틀 완화 | throttle-hardening |

항목 4, 5는 밀접하게 연결되므로 하나의 마일스톤(`throttle-hardening`)으로 묶는다.

---

## 1. 카메라 점프 제거

### 문제

앱 시작 시 `.automatic`(전체 지도)이 먼저 보인 뒤, async 위치 완료 후 500m 줌인으로 점프한다.

### 설계

- `CameraStateStore` 추가 — UserDefaults 래퍼로 마지막 카메라 영역(위도, 경도, 줌 span)을 저장/읽기.
- `DependencyContainer`에 등록, ViewModel에서 주입받아 사용.
- 앱 시작 시 흐름:
  1. 저장된 카메라 영역이 있으면 → 즉시 `cameraPosition` 설정 (점프 없음). 복원 후 그 위치에 그대로 머문다 (현재 위치로 자동 이동하지 않음).
  2. 없으면(첫 실행) → 서울시청 폴백 좌표로 설정, `bootstrapLocation()` 완료 후 현재 위치로 애니메이션 이동.
- 현재 위치로 이동하고 싶으면 기존 "내 위치" 버튼을 사용한다.
- 저장 시점: `scenePhase`가 `.background`로 전환될 때 1번 저장.
- 서울시청 폴백은 첫 실행 + 위치 권한 거부일 때만 발생.

### 영향 범위

- 새 파일: `CameraStateStore` (Infrastructure 또는 App 레이어)
- 수정: `CoursePlannerPage` (초기 카메라 설정 + scenePhase 감지), `CoursePlannerPageViewModel` (bootstrapLocation 흐름), `DependencyContainer`

---

## 2. 비연속 구간 그리기 — 자동 방향 감지

### 문제

기존 경로의 끝이 아닌 곳에서 새로 그리면 `flatMap`이 모든 스트로크를 순서대로 이어붙여 의도하지 않은 구간이 생긴다.

### 설계

- 새 스트로크의 양 끝점(시작/끝)과 기존 경로의 양 끝점(첫 좌표/끝 좌표), 총 4쌍의 거리를 비교해 **가장 가까운 쌍**을 찾는다.
  - 가장 가까운 쌍이 기존 끝 좌표 쪽이면 → 뒤에 append.
  - 가장 가까운 쌍이 기존 첫 좌표 쪽이면 → 앞에 prepend.
  - 필요 시 스트로크를 뒤집어(reverse) 경로가 자연스러운 방향으로 연결되도록 한다.
  - 기존 경로가 없으면(첫 스트로크) → 그냥 추가.
- 임계값 없이 항상 가까운 쪽에 연결. 거리와 무관하게 라우팅으로 이어붙인다.
- 되돌리기: 각 스트로크에 방향 정보(append/prepend)를 기록. 되돌리기 시 가장 최근 스트로크의 방향에 따라 뒤에서 또는 앞에서 해당 구간을 잘라낸다.
- 증분 계산(4번)과 연동: prepend든 append든 새 연결 구간만 라우팅 요청.

### 주의

실기기에서 실제 그리기 패턴을 확인한 뒤 조정이 필요할 수 있음 (MVP4 피드백 후보).

### 영향 범위

- 수정: `CoursePlannerPageViewModel` (스트로크 관리 로직, 되돌리기 로직)

---

## 3. 그리기 중 지도 이동 — 2손가락 패닝

### 문제

그리기 모드에서 `interactionModes: []`로 지도 제스처를 완전 차단. 화면 밖 경로를 이어 그리려면 탭 모드로 전환해야 하고, 전환 시 그리기가 초기화된다.

### 설계

- 그리기 모드에서 `interactionModes`를 `.pan`, `.zoom`으로 변경.
- 1손가락 드래그 → Canvas 오버레이에서 그리기 (현재와 동일).
- 2손가락 드래그 → 지도 이동.
- 핀치 → 줌 인/아웃.
- Canvas의 `DragGesture`가 1손가락을 소비하고, 나머지 제스처는 Map으로 전달.

### 주의

지도 앱에서 2손가락 이동은 익숙하지 않은 패턴. 실기기 피드백 후 잠금/해제 토글 등 다른 방식으로 전환할 수 있음 (MVP4 피드백 후보).

### 영향 범위

- 수정: `CoursePlannerPage` (Map의 `interactionModes` 변경)

---

## 4. 스로틀 완화 — 증분 계산

### 문제

스트로크가 추가될 때마다 전체 포인트를 `flatMap` → `snappedRoute`로 N-1번 라우팅 요청. 스트로크가 늘어날수록 호출이 누적되어 60초당 50요청 한계에 도달한다.

### 설계

- ViewModel에 **누적 경로 결과**(좌표 배열 + 총 거리)를 보관.
- 각 스트로크별 메타데이터 기록: 방향(append/prepend), 추가된 좌표 수, 추가된 거리.
- 새 스트로크 추가 시:
  1. 방향 감지 (2번과 연동).
  2. 새 스트로크 내부의 샘플 포인트 간 구간을 라우팅 (도보 경로 스냅) + 기존 경로와의 연결 구간 1건.
     이전 스트로크 구간은 재호출하지 않음. 호출 수는 새 스트로크의 샘플 포인트 수에 비례.
  3. 샘플링은 전체 포인트가 아닌 **스트로크 단위**로 수행.
  4. 결과를 누적 경로에 이어붙이기.
- 되돌리기: 메타데이터를 참조해 해당 구간의 좌표/거리를 잘라내기. 전체 재계산 없음.
- 기존 `recomputeSnappedCourse`(전체 재계산)는 증분 방식으로 대체.
- 기존 `snappedRoute` 프로토콜 기본 구현은 유지하되, ViewModel 레벨에서 증분 호출로 전환.

### 영향 범위

- 수정: `CoursePlannerPageViewModel` (증분 계산 로직, 누적 결과 관리)
- `MapKitCoursePlanningService`의 pair 캐시는 그대로 유지 (증분에서도 개별 `route()` 호출은 캐시 혜택)

---

## 5. 스로틀 모니터링 — 에러 안내

### 문제

스로틀 에러(`GEOErrorDomain Code=-3`) 발생 시 일반 에러("경로를 계산할 수 없습니다")와 구분이 안 된다.

### 설계

- `CoursePlanningError`에 `.throttled` 케이스 추가.
- `MapKitCoursePlanningService`에서 `GEOErrorDomain Code=-3` 감지 시 `.throttled`로 변환.
- ViewModel에서 `.throttled` 수신 시 "요청이 많아 잠시 후 다시 시도해주세요" 메시지 표시.
- 기존 에러 메시지와 분리하여 사용자가 원인을 이해할 수 있도록 한다.

### 영향 범위

- 수정: `CoursePlanningError`, `MapKitCoursePlanningService`, `CoursePlannerPageViewModel`

---

## 마일스톤 구성 (실제 실행 결과 반영)

| 마일스톤 | 포함 항목 | 상태 |
|----------|-----------|------|
| `camera-restore` | 1 | ✅ 완료 |
| `stroke-pipeline` | 2, 4, 5 | ✅ 완료 (항목 2+4는 같은 파이프라인이라 통합) |
| `drawing-pan` | 3 | ❌ 보류 — SwiftUI Map 위 오버레이로 2손가락 제스처 전달 불가 (hit-test 소유권 문제), MKMapView 교체 필요 |

## 실기기 피드백 후 재검토 대상

- 비연속 구간 자동 방향 감지 — 실제 그리기 패턴과 맞는지
- 그리기 중 지도 이동 — MKMapView(UIViewRepresentable)로 교체 후 다음 MVP에서 구현
