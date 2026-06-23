# MVP2 — UX 개선 + 스로틀 완화

> MVP1(러닝 코스 계획) 실기기 피드백을 반영하는 품질 개선 MVP.
> 마일스톤 2개: UI 개선 → 스로틀 완화.

## 배경

MVP1에서 탭/그리기 두 가지 코스 계획 방식이 만들어졌으나, 실기기 사용 시 다음 문제가 확인됨:

- 탭과 그리기 결과가 동시에 남아 혼란
- 진입 시 줌이 넓고 현재 위치 표시 없음
- 그리기 모드 활성 여부가 불명확
- 그린 경로에 출발/도착 핀 없음
- 위치 권한 거부 시 안내 없음
- 그리기 편집마다 전체 재라우팅으로 MKDirections 스로틀 발생

## 마일스톤 1 — UX 개선

### 1-1. 단일 모드 전환 + 상태 잔상 정리

- ViewModel에 `enum InteractionMode { case tap, draw }` 도입. 기본값 `.tap`.
- **탭 → 그리기 전환**: `startCoordinate`, `destinationCoordinate`, 탭으로 만든 `course`를 nil로 초기화.
- **그리기 → 탭 전환**: `drawnStrokes` 비우고, 그리기로 만든 `course`를 nil로 초기화.
- **`clear()` 버튼**: 현재 모드와 관계없이 모든 상태 초기화 (탭 좌표 + 그리기 스트로크 + course + error). 양쪽 모드에서 데이터가 있을 때 활성화.
- statusPanel 안내 텍스트를 모드에 따라 분기: 탭 모드 "지도에서 출발지를 선택하세요", 그리기 모드 "경로를 그려주세요".

### 1-2. 위치 시작 화면

- 초기 카메라 줌: 1000m → **100m**.
- Map 안에 `UserAnnotation()` 추가 — 현재 위치를 파란 점으로 표시.
- 지도 위 "내 위치로" 버튼(`location.fill` 아이콘) 배치. 누르면 `locationService.currentLocation()`을 호출해 카메라를 현재 위치 중심 100m 영역으로 이동.

### 1-3. 권한 거부 알럿

- `bootstrapLocation()`에서 `LocationError.denied` 발생 시 ViewModel에 `showLocationDeniedAlert = true` 플래그 설정.
- View에서 `.alert()`로 표시: "위치 권한이 필요합니다" + "설정으로 이동" / "닫기".
- "설정으로 이동" → `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`.
- 알럿 닫으면 서울시청 폴백 좌표로 지도 사용 가능 (기존 동작 유지).
- 최초 실행 시 시스템 권한 팝업에서 거부해도 동일하게 커스텀 알럿이 바로 표시됨 — 의도된 동작.

### 1-4. 그리기 모드 표시 명확화

- 버튼 라벨과 별도로 **모드 상태 인디케이터**를 분리.
- 그리기 모드 ON: 상단 컨트롤 배경을 강조색 틴트로 변경 + "그리기 중" 상태 텍스트 표시. 버튼 아이콘 `pencil.tip`.
- 그리기 모드 OFF: 기본 배경 복귀. 버튼은 `pencil.tip` + "그리기".
- 핵심: 버튼은 "전환 동작"을 나타내고, 현재 모드는 배경색+상태 텍스트로 보여줌.

### 1-5. 그린 코스 출발/도착 핀

- 코스가 존재하면 경로의 첫 좌표에 출발 마커(초록, `figure.run`), 마지막 좌표에 도착 마커(빨강, `flag.checkered`) 표시.
- 탭 모드와 그리기 모드에서 동일한 마커 스타일 사용 — 모드에 관계없이 course의 시작/끝에 핀을 보이게 통합.
- 탭 모드에서는 기존처럼 `startCoordinate`/`destinationCoordinate` 기반 마커를 유지 (경로 계산 전에도 핀이 보여야 하므로). 그리기 모드에서는 course의 첫/끝 좌표 기반으로 핀 표시.

## 마일스톤 2 — 스로틀 완화

### 2-1. 구간 라우팅 캐시

- 캐시는 `MapKitCoursePlanningService`(구체 어댑터)의 `route()` 레벨에 둔다. 프로토콜 extension은 저장 프로퍼티를 가질 수 없으므로, 캐시는 인프라 계층의 구체 타입이 소유.
- `route()` 호출 시 캐시 딕셔너리를 먼저 조회, 히트하면 API 호출 없이 반환. 미스하면 API 호출 후 결과 저장.
- `snappedRoute(through:)`는 프로토콜 extension의 기존 구현 그대로 유지 — 내부에서 `route()`를 구간별로 호출하므로 캐시 혜택을 자동으로 받음.
- 캐시 키: 출발·도착 좌표 쌍 (좌표를 소수점 5자리로 라운딩해 부동소수점 불일치 방지).
- `DependencyContainer`에서 `MapKitCoursePlanningService`는 단일 인스턴스로 생성되므로 캐시가 세션 동안 유지됨.
- 캐시는 별도 초기화 없이 유지 — 좌표 키 기반이라 항목이 작고, ViewModel의 `clear()`와 무관하게 재사용 가능.

### 2-2. 디바운스

- 스트로크 완료 후 300ms 딜레이를 두고, 그 사이 새 스트로크가 없을 때만 라우팅 실행.
- 기존 `recomputeGeneration` 패턴과 결합: 딜레이 후 generation이 변했으면 스킵.
- Swift `Task.sleep(nanoseconds:)` + generation 비교로 구현.

## 영향 범위

- **변경 파일**: `CoursePlannerPageViewModel.swift`, `CoursePlannerPage.swift`, `CoursePlannerPage+ControlsComponent.swift`, `MapKitCoursePlanningService.swift` (캐시 로직)
- **새 파일**: 없음 (기존 파일 내 변경으로 처리)
- **삭제 파일**: 없음
- **테스트**: ViewModel 단위 테스트로 모드 전환 시 상태 초기화, 캐시 적중/미스, 디바운스 동작 검증

## 범위 밖

- MapKit → 다른 제공자(Naver/Kakao/Tmap) 교체
- 코스 저장/불러오기
- GPS 트래킹 (실제 러닝 기록)
- 사용자 인증/백엔드
