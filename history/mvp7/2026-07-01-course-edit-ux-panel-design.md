# 코스 편집 UX 개선 — 탭 자동 연결 + 구간 시각화 + 실시간 패널

날짜: 2026-07-01
상태: 완료(소급 확인) — A/A-2/B/E 구현 커밋 완료, C/D 버그도 같은 브랜치에서 함께 수정(`09b0ad8`, `1f1e71c`, `0bb2b82`). 상세: `history/mvp7/260701_mvp7_completion_retro.md`

## 배경

MVP6 이후 실사용 피드백 5건을 수집했다. 이 중 3건(A, B, E)은 설계 판단이 필요한 UX 개선이고,
2건(C, D)은 원인 규명이 필요한 버그로 별도 처리한다. 다섯 건 모두 하나의 MVP로 묶는다.

- **A. 탭 자동 연결** — 두 번째 탭부터는 기존 경로 끝에서 자동 연장
- **B. 지도 위 구간 색상 + 거리 라벨** — 세그먼트마다 다른 색 + 거리 표시
- **E. 실시간 구간 현황 패널** — 지도 우측 상단, 접힘/펼침 오버레이
- **C. 짧은 거리 도착 마커 미표시** — 원인 규명 필요, `systematic-debugging`으로 별도 처리
- **D. 내 위치 이동 버튼 오작동/지연** — 원인 규명 필요, `systematic-debugging`으로 별도 처리

이 문서는 A, B, E의 설계만 다룬다. C, D는 디버깅 세션에서 원인 규명 후 별도 기록한다.

## A. 탭 자동 연결

### 현재 동작

`CoursePlannerPageViewModel.handleMapTap`(현재 `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift`)은
항상 2탭 구조다: 첫 탭은 `pendingTapStart`에 좌표를 저장하고 대기, 두 번째 탭에서 두 좌표 사이 route를 계산해
`CourseEditSession.attach`로 전달한다. `attach`는 기존 코스의 4개 끝점 조합(출발/도착 × 신규 시작/끝) 중
최단 거리를 골라 어느 방향에 붙일지, reverse가 필요한지 자동 판단한다.

### 변경

- **기존 코스에 세그먼트가 하나도 없을 때(최초)**: 현재 동작 그대로 유지 — 2탭(출발→도착) 필요.
- **기존 코스에 세그먼트가 하나 이상 있을 때**: 탭 좌표 1개만으로 즉시 route 계산.
  - 시작점은 기존 코스의 출발/도착 끝점 중 탭 좌표와 더 가까운 쪽으로 자동 결정.
  - 계산된 route는 기존과 동일하게 `CourseEditSession.attach`로 전달 (4방향 판단 로직 재사용 — attach는
    이미 완성된 두 끝점짜리 세그먼트를 받으므로 변경 불필요).
  - `pendingTapStart`를 통한 대기 상태·"연결점" pin 라벨은 최초 2탭 흐름에만 남긴다. 자동 연결 탭에는
    중간 대기 상태 없이 탭 → route 계산(짧은 로딩) → 세그먼트 반영으로 즉시 처리된다.

### 에러 처리

라우팅 실패·스로틀 등은 기존 에러 처리 경로(`.throttled` 감지 및 사용자 안내 메시지)를 그대로 재사용한다.
자동 연결 탭에서 route 계산이 실패해도 `pendingTapStart` 같은 중간 상태가 없으므로 롤백할 게 없다 — 단순히
세그먼트가 추가되지 않고 에러 메시지만 표시한다.

## A-2. 그리기 모드도 스트로크 단위로 세그먼트화 (B/E 전제조건)

### 현재 동작

`CoursePlannerPageViewModel`은 그리기 모드에서 스트로크가 끝날 때마다(`appendStroke` → `incrementalRoute`)
`StrokeDirectionResolver`로 방향(append/prepend/reverse)을 직접 판단해 `accumulatedCoordinates` 버퍼 하나에
계속 누적하고, 그리기 모드를 **종료할 때**(`toggleDrawingMode`의 `.draw` 케이스) 누적된 전체를 `CourseSegment.drawn`
세그먼트 **하나**로 `session.attach`한다. 즉 스트로크를 몇 번 나눠 그리든 `session.segments`에는 항상 1개로 합쳐진다.
`drawnStrokes`/`strokeEntries`는 undo 시 누적 버퍼를 처음부터 다시 계산하기 위한 보조 상태다.

### 변경

- 스트로크 하나가 끝나면(`appendStroke`) 그 스트로크만 route 계산해 `CourseSegment.drawn` 세그먼트로 만들고
  탭 모드(A)와 동일하게 즉시 `session.attach()`한다. `attach`가 이미 4방향 거리 비교로 방향·반전·gap 연결을
  자동 판단하므로, 스트로크 전용 `StrokeDirectionResolver` 호출과 `accumulatedCoordinates`/`accumulatedDistance`
  누적 버퍼가 더 이상 필요 없다.
- `drawnStrokes`/`strokeEntries`도 제거한다. 그리기 모드의 undo는 탭 모드와 동일하게 `session.undo()` 하나로
  통일한다 (`undoLastStroke()`를 `undo()`로 이름 정리하거나 tap/draw 분기를 제거).
- `toggleDrawingMode()`의 `.draw` 종료 처리는 draw 모드 전용 상태 초기화만 남고, attach 로직은 사라진다
  (이미 스트로크마다 attach됐으므로).
- ViewModel의 `course` computed property(현재 draw 모드에서 `accumulatedCoordinates`를 얹어 보여주는 분기)는
  더 이상 필요 없다 — 스트로크마다 `session.course`가 바로 갱신되므로 항상 `session.course`를 반환하면 된다.
- `DrawnPathSampler`는 스트로크 단순화 용도로 계속 사용한다. `StrokeDirectionResolver`는 더 이상 참조되지
  않으면 파일까지 제거한다 (다른 사용처 없는지 확인 필요).

### 영향받는 기존 테스트

`TraceTests/CoursePlannerViewModelTests.swift`의 그리기 모드 관련 테스트(다중 스트로크 누적, undo 재계산 등)는
새 동작(스트로크마다 attach)에 맞게 다시 작성해야 한다.

## B. 지도 위 구간 색상 + 거리 라벨

### 현재 동작

`MapViewRepresentable`(`Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`)은
`overlayCoordinates`(모든 세그먼트를 평탄화한 좌표 배열)를 단일 `MKPolyline`으로만 그린다
(`strokeColor = .systemBlue`, `lineWidth = 6`, `updateUIView`는 count+첫/끝 좌표 비교로 불필요한 재생성만 막는다).
세그먼트 단위 구분은 렌더링 레이어에 없다.

### 변경

- `CourseEditSession.segments`(`[CourseSegment]`, A-2 변경 후에는 탭/그리기 모두 "1 동작 = 1 세그먼트"로 통일됨)를
  순회해 세그먼트마다 별도 `MKPolyline` overlay를 생성한다. 색상을 오버레이별로 구분해 그리려면 현재
  `rendererFor`가 하드코딩한 `.systemBlue` 대신, 오버레이가 자기 색상 인덱스를 들고 있어야 한다 — `MKPolyline`을
  서브클래싱(`SegmentPolyline`에 `segmentIndex: Int` 추가)해서 해결한다.
- `updateUIView`의 오버레이 갱신 로직도 "단일 polyline 존재 여부"가 아니라 "세그먼트 배열과 현재 오버레이 배열을
  세그먼트 개수/좌표로 비교"하는 방식으로 바꿔야 한다. 카메라 이동마다 `updateUIView`가 호출되므로, 세그먼트가
  실제로 안 바뀌었으면 오버레이를 다시 그리지 않아야 깜빡임이 없다.
- 색상은 순환 팔레트(파랑→초록→주황→...)를 세그먼트 순서에 따라 배정한다. 탭/그리기 타입 구분은 색상에
  반영하지 않는다. 색상 매핑은 View와 Map 양쪽이 공유하는 순수 함수(`segmentColor(at index: Int) -> UIColor`)로 만든다.
- 각 세그먼트의 중점 좌표에 거리 라벨 annotation("120m" 등)을 추가한다.
- attach로 생긴 gap-연결 구간(예: 기존 끝점과 새 세그먼트 시작점 사이 20m 이상 벌어져 자동 라우팅되는 부분,
  `CourseEditSession.attach` 42/49번 줄)은 별도 세그먼트로 분리하지 않고 해당 세그먼트 색상에 포함된다.
- 세그먼트 추가(attach)·undo(`removeLast`)·clear 시 오버레이 배열을 세그먼트 배열과 동기화해 다시 그린다.

## E. 실시간 구간 현황 패널

### 배치 및 상태

- 지도 우측 상단에 오버레이로 배치. 접힘/펼침 토글 가능.
- **접힘**: 총 거리만 작게 표시 (예: "2.3km").
- **펼침**: 세그먼트별 리스트 — 순번, 색상 스와치(B의 팔레트와 동일 색), 구간 거리, 누적 거리.
- `CourseEditSession.segments`가 바뀔 때마다(탭/그리기/undo/clear) 실시간 갱신된다.

### 지도 연동

- ViewModel에 `selectedSegmentIndex: Int?` 상태를 추가한다.
- 펼친 리스트에서 세그먼트 아이템을 탭하면 `selectedSegmentIndex`가 설정되고, 지도는 해당 세그먼트의
  overlay를 하이라이트(예: 강조 lineWidth 또는 채도 상승)하고 해당 구간이 보이도록 카메라를 이동한다.
- B의 세그먼트 색상 팔레트와 리스트의 색상 스와치는 동일한 소스(세그먼트 인덱스 → 색상 매핑)를 공유한다.

## 데이터/상태 흐름

- 새 도메인/Application 모델 변경 없음 — 기존 `CourseEditSession.segments`(`[CourseSegment]`)를 그대로 사용한다.
- ViewModel에서 `accumulatedCoordinates`/`accumulatedDistance`/`drawnStrokes`/`strokeEntries`를 제거하고
  `selectedSegmentIndex: Int?` 상태를 추가한다.
- `course` computed property는 tap/draw 분기 없이 항상 `session.course`를 반환하도록 단순화한다.
- 세그먼트 → 색상 매핑은 순서 기반 순수 함수로 구현해 View(패널)와 Map 양쪽에서 동일하게 참조한다.

## 테스트

- ViewModel: 탭 로직 유닛 테스트 — 최초 2탭 흐름(코스 없음), 이후 1탭 자동 연결(가까운 끝점 선택 포함), route 실패 시 세그먼트 미반영.
- ViewModel: 그리기 모드 유닛 테스트 — 스트로크 1회 = 세그먼트 1개 attach, 여러 스트로크 시 세그먼트 개수 누적,
  undo 시 `session.undo()`로 마지막 세그먼트만 제거되는지 확인. 기존 `CoursePlannerViewModelTests.swift`의
  다중 스트로크 누적/undo 재계산 테스트를 새 동작에 맞게 다시 작성.
- 세그먼트 → 색상 매핑 함수 유닛 테스트 — 인덱스에 따른 순환 배정 확인.
- (가능하면) 패널 접힘/펼침 상태 및 아이템 탭 시 `selectedSegmentIndex` 갱신 유닛 테스트.
- 실기기 QA: 자동 연결 탭 체감, 구간 라벨 가독성, 패널 오버레이가 지도 조작을 가리지 않는지 확인.

## 범위 밖 (별도 처리)

- **C. 짧은 거리 도착 마커 미표시** — `systematic-debugging`으로 원인 규명 후 별도 커밋.
- **D. 내 위치 이동 버튼 오작동/지연** — `systematic-debugging`으로 원인 규명 후 별도 커밋.
