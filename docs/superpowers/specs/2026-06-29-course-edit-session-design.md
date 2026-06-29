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

```swift
@Observable
final class CourseEditSession {
    private(set) var segments: [CourseSegment] = []

    var course: PlannedCourse? {
        segments.isEmpty ? nil : PlannedCourse(segments: segments)
    }

    func append(_ segment: CourseSegment) {
        segments.append(segment)
    }

    func prepend(_ segment: CourseSegment) {
        segments.insert(segment, at: 0)
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

`CourseEditSession`은 순수 상태 저장소다. 방향 판단과 gap 라우팅은 ViewModel이 처리하고, session에는 이미 결정된 세그먼트만 전달한다.

---

## ViewModel 변경

### 제거되는 상태

| 제거 항목 | 이유 |
|---|---|
| `history: [CourseSegment]` | `session.segments`로 대체 |
| `preDrawTapState` | 모드 전환 봉인 로직 삭제 |
| `startCoordinate` | `pendingTapStart`로 대체 |
| `destinationCoordinate` | 두 번째 탭 처리 시 로컬 변수로 |
| `accumulatedCoordinates` | 그리기 모드 전용 임시 상태로 유지 (여러 async 호출에 걸쳐 유지되어야 하므로 인스턴스 프로퍼티 유지, 그리기 모드 종료 시 초기화) |
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
  route(start → coordinate) → segment
  방향 감지: segment를 session 끝점/시작점과 비교
  필요 시 gap 세그먼트 라우팅 후 session.append(gap)
  session.append(segment) 또는 session.prepend(segment)
```

### 방향 감지 (탭 세그먼트)

`StrokeDirectionResolver`와 동일한 원리를 탭 세그먼트에 적용한다.

- `session.course`가 없으면 그냥 append
- 있으면 새 세그먼트의 시작·끝과 기존 경로 끝점(end) 거리 비교:
  - 새 세그먼트 시작이 end에 가까우면 → forward append
  - 새 세그먼트 끝이 end에 가까우면 → reverse 후 forward append
  - 새 세그먼트 시작이 start에 가까우면 → prepend
  - 새 세그먼트 끝이 start에 가까우면 → reverse 후 prepend

### Gap 자동 연결

방향 결정 후, 기존 경로 끝점과 새 세그먼트 시작 사이에 거리가 있으면 연결 구간을 라우팅해 먼저 append한다. 그리기 모드의 connection 로직과 동일.

---

## 그리기 모드 변경

### 진입 시

```swift
// 기존 history 씨드 대신 session에서 읽음
accumulatedCoordinates = session.course?.coordinates ?? []
accumulatedDistance = session.course?.distanceMeters ?? 0
```

`StrokeDirectionResolver`에 전달하는 `existingCourseStart`/`existingCourseEnd`는 `session.course?.coordinates.first/last`에서 가져온다.

### 종료 시 (실제로 그린 내용이 있을 때)

```swift
// session에 있는 기존 좌표 수를 기준으로 새로 그린 부분만 추출
let seedCount = session.course?.coordinates.count ?? 0
let newCoords = Array(accumulatedCoordinates.dropFirst(seedCount))
let newDistance = accumulatedDistance - (session.course?.distanceMeters ?? 0)
session.append(.drawn(coordinates: newCoords, distanceMeters: newDistance))
```

### 모드 전환 단순화

```swift
func toggleDrawingMode() {
    switch interactionMode {
    case .tap:
        pendingTapStart = nil        // 대기 중 탭 포인트만 버림
        accumulatedCoordinates = session.course?.coordinates ?? []
        accumulatedDistance = session.course?.distanceMeters ?? 0
        interactionMode = .draw

    case .draw:
        if !drawnStrokes.isEmpty {
            let seedCount = session.course?.coordinates.count ?? 0
            let newCoords = Array(accumulatedCoordinates.dropFirst(seedCount))
            let newDistance = accumulatedDistance - (session.course?.distanceMeters ?? 0)
            if !newCoords.isEmpty {
                session.append(.drawn(coordinates: newCoords, distanceMeters: newDistance))
            }
        }
        drawnStrokes = []
        strokeEntries = []
        accumulatedCoordinates = []
        accumulatedDistance = 0
        interactionMode = .tap
    }
}
```

`preDrawTapState` 복원 로직이 완전히 사라진다.

---

## Undo / Clear 통합

### Undo

| 상황 | 동작 |
|---|---|
| 탭 모드 | `session.undo()` — 마지막 탭 세그먼트 제거 |
| 그리기 모드, 스트로크 있음 | 기존 `strokeEntries` 기반 재계산 (변경 없음) |
| 그리기 모드, 스트로크 없음 | `session.undo()` — 진입 전 마지막 세그먼트 제거 |

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

---

## 파일 목록

| 파일 | 변경 |
|---|---|
| `Application/CoursePlanning/CourseEditSession.swift` | 신규 |
| `Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift` | 대폭 단순화 |
| 기타 Domain/Infrastructure/View 파일 | 변경 없음 |
