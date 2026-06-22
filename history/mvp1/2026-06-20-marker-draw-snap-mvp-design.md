# 마커 그리기 + 스냅 슬라이스 설계 (MapKit)

작성일: 2026-06-20
상태: 설계 (사용자 리뷰 대기)

## 용어 (고정)

- **포인트(point)**: 사용자가 지도에서 탭해 찍는 개별 지점(출발/도착 등).
- **마커(marker)**: 지도 위에 손으로 그리는 경로 흔적(실제로 달린 듯한 자취 선).

## 배경 / 결정 맥락

- 제품 방향: 달리기 전에 코스를 계획한다. 현재 MVP는 `포인트` 2개 → 도보 경로 + 총거리.
- 지도/라우팅 시퀀싱 결정은 `docs/agent-rules/project-decisions.md` 참고: **기능 먼저, 지도 SDK는 뷰에 가둠, 제공자 교체는 측정된 트리거 시.** 한국에서 MapKit 도보 경로는 동작함(2026-06-20 실측).
- 리서치 결론(이 세션): 한국 보행 "맵매칭 전용 API"는 사실상 없음. Naver=보행 미지원, Kakao=URL Scheme만, Mapbox=한국 제외, Tmap=보행 REST 있으나 24h 저장 제한+유료, Valhalla/OSM=가능하나 자체 서버 운영 필요. 따라서 **B(낙서 스냅)는 어느 제공자든 "샘플링 → 구간 도보 라우팅 이어붙이기"로 구현**되고, 그 로직은 제공자 무관하게 재사용됨. 그래서 MapKit으로 먼저 만든다.

## 이 슬라이스의 범위 (a + b + g)

1. **(a) 현재 위치로 줌인된 시작 지도** — 앱/페이지 진입 시 현재 위치로 카메라를 맞추고 적당히 확대. 위치 권한 요청 포함.
2. **(b) 마커 그리기 + 스냅 + 거리** — "그리기 모드"에서 드래그로 마커를 그림 → 그린 좌표를 듬성듬성 샘플링 → 인접 샘플끼리 도보 경로로 이어붙여 실제 길에 스냅 → 폴리라인 + 총거리 표시.
3. **(g) 초기화 / 되돌리기** — 전체 지움(초기화), 마지막 그리기 구간 취소(되돌리기) 후 재계산.

### 범위 밖 (다음 슬라이스)

코스 저장(persistence), 예상 시간·페이스, 장소 검색, 탭 경유지(그리기로 흡수), 제공자 교체(Tmap/Valhalla). 기존 두-탭 `포인트` 자동경로 흐름은 **건드리지 않고 유지**한다(기존 테스트 보존).

## 상호작용 모델

- **그리기 모드 토글 버튼**으로 pan(지도 이동)과 draw(그리기)를 분리한다.
  - 일반 모드: 드래그 = 지도 이동(기본 Map 동작). 기존 탭-포인트도 동작.
  - 그리기 모드: 드래그 = 마커 그림(지도 고정). 한 번의 드래그(누름→뗌) = 한 **구간(stroke)**.
- 마커는 여러 구간을 이어 그릴 수 있다. 스냅된 경로는 누적된 모든 구간의 좌표로 계산한다.
- 마커가 정의하는 경로의 **첫 좌표 = 출발, 마지막 좌표 = 도착**. (현재 위치는 카메라 초기화에만 사용; 출발을 강제하지 않음.)

## 아키텍처 (기존 포트-어댑터 / MVVM / @Observable 준수)

MapKit/CoreLocation 타입은 계속 **뷰·인프라 레이어에만** 가둔다. ViewModel/Domain은 도메인 타입만 다룬다.

### Domain
- `LocationServiceProtocol` (신규, `Trace/Domain/Location/Protocol`)
  - `func currentLocation() async throws -> CourseCoordinate`
  - 인증 상태 처리 포함. 오류 타입 `LocationError`(거부/불가).
- `DrawnPathSampler` (신규 순수 함수, `Trace/Domain/CoursePlanning` 하위; MapKit 비의존, 단위 테스트 대상)
  - `static func sample(_ raw: [CourseCoordinate], minSpacingMeters: Double) -> [CourseCoordinate]`
  - 인접 점 간 최소 간격으로 다운샘플링하여 라우팅 호출 수를 제한(요청 폭주 방지). 시작/끝 좌표는 보존.
  - **기본 간격 ≈ 120m**(스파이크 실측 스위트스폿). 과도 분할 금지.
- `CoursePlanningServiceProtocol` 확장
  - 기존 `route(from:to:)` 유지.
  - 신규 `func snappedRoute(through points: [CourseCoordinate]) async throws -> PlannedCourse`.

### Infrastructure
- `CoreLocationService: LocationServiceProtocol` (`Trace/Infrastructure/Location/CoreLocation`)
- `MapKitCoursePlanningService`에 `snappedRoute(through:)` 구현
  - 입력 좌표를 인접 쌍으로 묶어 각 구간을 `MKDirections .walking`으로 계산, 폴리라인 이어붙이고 거리 합산.
  - 구간 실패 처리(아래 오류 처리 참고).

### Pages/CoursePlannerPage
- ViewModel(`@Observable`) 추가 상태/동작
  - `isDrawingMode: Bool`
  - `drawnStrokes: [[CourseCoordinate]]` (구간 누적)
  - `course: PlannedCourse?` (스냅 결과 — 기존 필드 재사용), `isLoading`, `errorMessage`
  - `initialCameraCoordinate: CourseCoordinate?` (현재 위치)
  - `bootstrapLocation() async` / `toggleDrawingMode()` / `appendStroke(_:) async`(샘플+스냅 호출) / `undoLastStroke() async` / `clear()`
- View
  - `Map`에 카메라 position 바인딩(초기 현재 위치 + 적당한 거리).
  - 그리기 모드 토글 버튼, 초기화·되돌리기 버튼.
  - 그리기 모드일 때 `DragGesture`로 화면 좌표 수집 → `MapProxy`로 좌표 변환 → 구간 버퍼.

## 데이터 흐름 (b)

1. 진입 → `bootstrapLocation()` → 카메라를 현재 위치로(실패 시 폴백, 아래 참고).
2. 그리기 모드 진입 → 드래그로 화면 점 수집 → 좌표 변환 → 현재 구간 버퍼.
3. 드래그 종료 → 구간을 `drawnStrokes`에 추가 → 전체 좌표 평탄화 → `DrawnPathSampler.sample(...)` → `snappedRoute(through:)` → `course` 갱신(폴리라인 + `distanceText`).
4. 되돌리기 → 마지막 구간 제거 → 재샘플·재스냅. 초기화 → 모든 상태 리셋.

## 오류 처리

- 위치 권한 거부/실패 → 크래시 없이 기본 영역(예: 서울 시청)으로 폴백 + 안내 메시지.
- 스냅 구간 실패(MKDirections 오류/스로틀) → 실패 구간을 **직선으로 몰래 메우지 않는다**(직선은 건물을 가로질러, 우리가 측정하려는 스냅 품질 신호를 오염시킴). 실패 구간은 **눈에 띄게 표시**(예: 점선/다른 색)하고, 실패가 임계치를 넘으면 `errorMessage`. (임계치는 스파이크/프로토타입 실측 후 조정.)
- 약관: 경로 형상은 영속 저장하지 않는다(이 슬라이스는 저장 자체가 범위 밖). 저장은 다음 슬라이스에서 `포인트`+`마커` 입력 기준으로 설계.

## 테스트 (TDD)

순수/뷰모델 단위 테스트:
- `DrawnPathSampler`: 최소 간격 다운샘플링, 시작/끝 보존, 빈/단일/짧은 입력, 간격 경계.
- ViewModel(가짜 `LocationService` + 가짜 `CoursePlanningService`):
  - bootstrap이 카메라를 현재 위치로 설정 / 권한 거부 시 폴백.
  - 그리기 모드 토글 상태 전이.
  - 구간 추가 → `snappedRoute` 호출 → `course`·`distanceText` 발행.
  - 되돌리기: 마지막 구간 제거 후 재스냅 / 초기화: 상태 리셋.
  - 스냅 실패 → `errorMessage` 설정, `course` 미갱신.
- 수동/시뮬레이터 검증(단위 불가): 실제 드래그 제스처, CoreLocation 권한, MapKit 어댑터 스냅 품질·속도(한국 실제 경로). **이 슬라이스의 1차 목표 = 한국에서 스냅 품질/속도가 쓸 만한지 실측.**

## 구현 순서: 먼저 스파이크 (Task 0)

production 코드(LocationService·Sampler·ViewModel·테스트)를 짓기 **전에**, 기능 (b)의 핵심 가정을 싸게 검증한다. 이미 단일 MKDirections는 한국에서 동작함을 실측했지만(`/tmp` 스크립트), (b)가 의존하는 건 **여러 구간 이어붙이기**라 별개의 미검증 가정이다.

- 스파이크: 서울의 일부러 **비직선**인 실제 도보 경로를 따라 ~10–15개 점을 찍고, 인접 점끼리 `MKDirections .walking`으로 이어붙여 관찰한다. 측정: ① 호출 수 ② 지연 ③ 스로틀 오류 발생 여부 ④ 이어붙인 폴리라인이 입력(그린 모양)과 닮는가.
- 통과하면 → 스펙대로 진행. 실패하면 → 샘플러 전략/그리기 UX를 바꾸거나 제공자(Valhalla `trace_route`)로 점프. **즉 스파이크 결과가 스펙을 재형성할 수 있으므로 1순위.**

### 스파이크 결과 (2026-06-20, 통과)

경복궁 앞 ㄷ자 우회(약 1.9km)를 간격별로 다운샘플해 체이닝한 실측:

| 간격 | 점/구간 | 시간 | 충실도(avg/max 우회비) | 실패 |
|---|---|---|---|---|
| 직선 A→B | 2 / 1 | 0.2s | 내 모양 무시(직선으로 질러감) | 0 |
| 250m(성김) | 9 / 8 | 0.8s | 1.18 / 1.65 (모양 재현) | 0 |
| **120m(중간)** | **17 / 16** | **1.1s** | **1.12 / 1.80 (가장 충실)** | **0** |
| 60m(촘촘) | 34 / 33 | 1.9s | 1.34 / 5.71 (들쭉날쭉) | **8** |

결론:
- **방식 유효** — 체이닝은 그린 모양을 따라가고 직선으로 질러가지 않음.
- **스위트스폿 존재 → 약 100–150m 간격**(약 1.9km당 ~16구간, ~1s, 충실, 실패 0).
- **과도 분할 금지** — 60m는 충실도가 오히려 나빠지고(짧은 간격이 블록을 우회→max 5.71), 스로틀 실패 발생.
- 실패는 **한 프로세스에서 ~50콜 누적**으로 몰아칠 때 발생("Directions are not available"). 실제 1회 그리기 = ~16콜이라 여유. 안전을 위해 구간 실패에 **가벼운 재시도/백오프**만 추가.

## 위험 / 측정 항목

- **충실도 ↔ 호출 수 긴장은 실측으로 해소됨.** MKDirections는 궤적/경유지 입력이 없어 각 구간을 독립 최적화한다. 성기면 모양 무시, 촘촘하면 스로틀. 스파이크 결과 **약 100–150m 간격에 스위트스폿 존재**(위 표). 이 범위를 벗어나지 않도록 샘플러 기본값을 잡는다.
- `MKDirections` 다중 구간 호출 시 **스로틀링/지연** — 한 스트로크 10–15점 = 재계산마다 10–15콜, 되돌리기·구간추가마다 재발화. 다운샘플 간격으로 통제하되 스파이크에서 한도 실측.
- 한국에서의 **스냅 품질** — 부족하면 그게 제공자 교체(Tmap/Valhalla) 검토의 측정된 트리거.
- **음성 결과의 정확한 의미**: 이어붙이기 품질이 나빠도 그것은 "MapKit 체이닝이 충분치 않다"만 증명할 뿐 **기능 자체가 불가능함을 뜻하지 않는다**. Valhalla `trace_route`는 그린 궤적 매칭 전용이라 훨씬 나을 수 있다. 약한 체이닝 프로토타입으로 기능 아이디어를 죽이지 말 것 — 제공자 질문만 발동.
