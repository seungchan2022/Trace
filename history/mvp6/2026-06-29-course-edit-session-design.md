# CourseEditSession 설계 — 탭↔그리기 통합 및 undo/clear 통합

작성일: 2026-06-29
MVP: MVP6

---

## 배경 및 문제

현재 `CoursePlannerPageViewModel`은 두 가지 책임을 동시에 가진다:

1. **UI 상태 조율** — 모드 전환, 로딩, 에러
2. **경로 편집 상태 관리** — `history`, `accumulatedCoordinates`, `strokeEntries`, `preDrawTapState` 등

"경로를 쌓고, 되돌리고, 방향을 판단하는 주체"라는 도메인 개념이 정의되지 않아 기능이 추가될 때마다 ViewModel에 상태가 누적됐다.

결과로 발생한 문제:
- 탭 세그먼트가 history에 즉시 쌓이지 않아 탭 연속 이어붙이기 불가
- 그리기 → 탭 전환 후 기존 경로 끝점과 연결되지 않음
- undo/clear가 그리기 모드 전용으로만 동작

---

## 설계 원칙

탭과 그리기는 **경로 세그먼트를 만드는 입력 방법**이 다를 뿐, 결과물(`CourseSegment`)은 동일하다. 두 모드는 같은 세그먼트 스택을 공유하고, undo/clear는 모드 무관하게 동작해야 한다.

---

## 아키텍처 구조

```
Domain/CoursePlanning/
  Entity/   PlannedCourse, CourseSegment          (변경 없음)
  Protocol/ CoursePlanningServiceProtocol          (변경 없음)

Application/CoursePlanning/           ← 신규 레이어
  CourseEditSession                   ← 핵심 신규 타입

Infrastructure/CoursePlanning/        (변경 없음)

Pages/CoursePlannerPage/
  CoursePlannerPageViewModel          (대폭 단순화)
```

`Application` 폴더는 현재 project-decisions.md의 "나중에 Swift Package로 분리 가능하게 구조화" 방향과 일치한다.

---

## CourseEditSession

**위치:** `Trace/Application/CoursePlanning/CourseEditSession.swift`

`CourseEditSession`은 Application 레이어 오케스트레이터다. 방향 판단, gap 라우팅, 세그먼트 병합을 내부에서 처리하고, 호출자(ViewModel)에게는 단순한 "이 새 구간을 붙여라"는 인터페이스만 노출한다.

```swift
@Observable
final class CourseEditSession {
    private(set) var segments: [CourseSegment] = []

    var course: PlannedCourse? {
        segments.isEmpty ? nil : PlannedCourse(segments: segments)
    }

    // 핵심 메서드: 방향 판단 + gap 라우팅 + 세그먼트 병합을 모두 처리
    // 1 attach 호출 = 1 segment 추가 = 1 undo로 되돌릴 수 있는 단위
    func attach(
        _ newSegment: CourseSegment,
        using service: CoursePlanningServiceProtocol
    ) async throws {
        guard let existing = course else {
            segments.append(newSegment)
            return
        }

        // 1. 방향 판단: 새 세그먼트를 기존 경로 어느 끝에, 어느 방향으로 붙일지 결정
        let newCoords = newSegment.coordinates
        let existingStart = existing.coordinates.first!
        let existingEnd = existing.coordinates.last!

        let orientation = resolveOrientation(
            newStart: newCoords.first!,
            newEnd: newCoords.last!,
            existingStart: existingStart,
            existingEnd: existingEnd
        )

        // 2. 필요 시 reverse
        let orientedSegment = orientation.needsReverse ? newSegment.reversed() : newSegment
        let orientedCoords = orientedSegment.coordinates

        // 3. gap 라우팅: 기존 경로 끝점과 새 세그먼트 시작 사이 연결
        let attachPoint = orientation.attachesToEnd ? existingEnd : existingStart
        let gapStart = orientation.attachesToEnd ? attachPoint : orientedCoords.last!
        let gapEnd = orientation.attachesToEnd ? orientedCoords.first! : attachPoint

        var combinedCoords = orientedCoords
        var combinedDistance = orientedSegment.distanceMeters

        if needsGap(from: gapStart, to: gapEnd) {
            let gapSegment = try await service.planCourse(from: gapStart, to: gapEnd)
            combinedCoords = orientation.attachesToEnd
                ? gapSegment.coordinates + combinedCoords
                : combinedCoords + gapSegment.coordinates
            combinedDistance += gapSegment.distanceMeters
        }

        // 4. gap + 새 세그먼트를 하나의 세그먼트로 병합 후 append/prepend
        let merged = CourseSegment.tapped(coordinates: combinedCoords, distanceMeters: combinedDistance)
        if orientation.attachesToEnd {
            segments.append(merged)
        } else {
            segments.insert(merged, at: 0)
        }
    }

    func undo() {
        guard !segments.isEmpty else { return }
        segments.removeLast()
    }

    func clear() {
        segments = []
    }
}
```

**핵심 설계 결정:**
- gap 세그먼트와 새 세그먼트를 **하나의 merged 세그먼트**로 병합해서 저장
  → 1 attach = 1 segment entry = undo 한 번에 완전히 제거됨 (dangling gap 없음)
- 방향 판단(`resolveOrientation`)과 gap 필요 여부(`needsGap`)는 CourseEditSession 내부 헬퍼
  → StrokeDirectionResolver와 동일한 4쌍 비교 원리, Application 레이어 내 재구현

---

## ViewModel 변경

### 제거되는 상태

| 제거 항목 | 이유 |
|---|---|
| `history: [CourseSegment]` | `session.segments`로 대체 |
| `preDrawTapState` | 모드 전환 봉인 로직 삭제 |
| `startCoordinate` | `pendingTapStart`로 대체 |
| `destinationCoordinate` | 두 번째 탭 처리 시 로컬 변수로 |
| `accumulatedCoordinates` | 그리기 모드 전용 임시 상태로 유지 (그리기 진입 시 빈 배열로 초기화, 스트로크마다 누적, 종료 시 session.attach에 전달 후 초기화) |
| `accumulatedDistance` | 동일 |

### 추가되는 상태

```swift
let session = CourseEditSession()
private var pendingTapStart: CourseCoordinate?
```

### 유지되는 상태

- `interactionMode`, `isLoading`, `errorMessage`, `initialCameraCoordinate` — UI 상태
- `drawnStrokes`, `strokeEntries` — 그리기 모드 내 증분 undo를 위한 임시 상태

### course 노출

```swift
var course: PlannedCourse? { session.course }
```

View는 ViewModel의 `course`를 통해서만 접근한다. `session`은 ViewModel 내부에 캡슐화된다.

---

## 탭 모드 새 흐름

```
탭 1:
  pendingTapStart = coordinate

탭 2:
  start = pendingTapStart
  pendingTapStart = nil
  route(start → coordinate) → segment (.tapped)
  try await session.attach(segment, using: planningService)
  // 방향 판단 + gap 라우팅 + 병합을 session 내부에서 처리
  // 결과: session.segments에 1개 추가, undo 1번으로 완전 제거 가능
```

방향 판단과 gap 라우팅 책임이 ViewModel에서 `CourseEditSession.attach`로 이동했다. ViewModel은 탭 좌표를 받아 라우팅만 하고 session에 결과를 전달한다.

---

## 그리기 모드 변경

### 진입 시

```swift
// 새 스트로크만 누적 — 기존 경로 씨드로 초기화하지 않음
accumulatedCoordinates = []
accumulatedDistance = 0
```

`incrementalRoute` 내부의 `StrokeDirectionResolver`는 `session.course?.coordinates`를 기존 경로 기준으로 참조한다. 누적 좌표는 새로 그린 것만 쌓이고, 종료 시 `session.attach`가 기존 경로와의 방향·gap 판단을 수행한다.

### 종료 시 (실제로 그린 내용이 있을 때)

```swift
// accumulatedCoordinates 전체가 새 drawn 세그먼트
// (그리기 진입 시 session 씨드로 초기화했으므로 전체가 증분)
// 방향 판단 + gap 연결은 session.attach가 처리
let newSegment = CourseSegment.drawn(
    coordinates: accumulatedCoordinates,
    distanceMeters: accumulatedDistance
)
try await session.attach(newSegment, using: planningService)
```

**수정 이유:** 기존의 `dropFirst(seedCount)` 방식은 prepend 케이스에서 새 좌표가 앞에 붙어 seed가 앞에 없게 되므로 슬라이싱이 틀림. `attach`를 통해 처리하면 방향 판단을 내부에서 정확히 수행한다.

그리기 진입 시 `accumulatedCoordinates`는 비어있는 상태로 시작(새 스트로크만 누적)하고, `StrokeDirectionResolver`가 session의 기존 경로를 기준으로 방향을 결정한다.

### 모드 전환 단순화

```swift
func toggleDrawingMode() async {
    switch interactionMode {
    case .tap:
        pendingTapStart = nil        // 대기 중 탭 포인트만 버림
        accumulatedCoordinates = []
        accumulatedDistance = 0
        interactionMode = .draw

    case .draw:
        if !accumulatedCoordinates.isEmpty {
            let newSegment = CourseSegment.drawn(
                coordinates: accumulatedCoordinates,
                distanceMeters: accumulatedDistance
            )
            try? await session.attach(newSegment, using: planningService)
        }
        drawnStrokes = []
        strokeEntries = []
        accumulatedCoordinates = []
        accumulatedDistance = 0
        interactionMode = .tap
    }
}
```

`preDrawTapState` 복원 로직이 완전히 사라진다. 그리기 진입 시 `accumulatedCoordinates`는 항상 빈 상태에서 시작하고, 기존 경로와의 연결은 `session.attach` 내부의 StrokeDirectionResolver가 처리한다.

---

## Undo / Clear 통합

### Undo

| 상황 | 동작 |
|---|---|
| 탭 모드 | `session.undo()` — 마지막 탭 세그먼트 제거 (gap이 병합돼 있으므로 gap도 함께 제거됨) |
| 그리기 모드, 스트로크 있음 | 기존 `strokeEntries` 기반 재계산 (변경 없음) |
| 그리기 모드, 스트로크 없음 | `session.undo()` — 진입 전 마지막 세그먼트 제거 |

**Undo 정확성 보장:** `session.attach`가 gap + 새 세그먼트를 하나의 merged 세그먼트로 저장하므로, `session.undo()` 한 번이 논리적으로 하나의 사용자 액션(탭 쌍 또는 drawn 스트로크 세션)을 완전히 제거한다. dangling gap 세그먼트가 남는 시나리오가 존재하지 않는다.

### Clear

```swift
func clear() {
    session.clear()
    pendingTapStart = nil
    drawnStrokes = []
    strokeEntries = []
    accumulatedCoordinates = []
    accumulatedDistance = 0
    errorMessage = nil
    isLoading = false
    recomputeGeneration += 1
}
```

---

## 제거되는 복잡도

- `preDrawTapState` 저장/복원 로직
- `toggleDrawingMode`의 탭 세션 봉인 로직 (`course.segments.dropFirst(history.count)`)
- `history = [.drawn(...)]` 단일 세그먼트 봉인
- `undoLastStroke`에서 `history` 직접 참조
- ViewModel 내 방향 판단 + gap 라우팅 중복 로직 (탭 경로, 그리기 경로 각각 따로 있던 것)
- `dropFirst(seedCount)` delta 추출 (prepend 케이스에서 깨지던 로직)

---

## 파일 목록

| 파일 | 변경 |
|---|---|
| `Application/CoursePlanning/CourseEditSession.swift` | 신규 |
| `Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift` | 대폭 단순화 |
| 기타 Domain/Infrastructure/View 파일 | 변경 없음 |
