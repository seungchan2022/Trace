# drawing-precision 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 루프 경로 라우팅 오류(0.01 km 버그)를 수정하고 실기기 스로틀 에러 감지를 수정한다.

**Architecture:** `DrawnPathSampler`를 누적거리 기반 샘플링으로 교체 (직선거리 → 획 따라 이동한 누적거리). `MapKitCoursePlanningService`의 스로틀 에러 감지는 실기기 DEBUG 로그를 통해 실제 domain/code를 확인한 후 수정한다.

**Tech Stack:** Swift, XCTest, MapKit(MKDirections 에러)

## Global Constraints

- iOS 17.0+ 최소 지원
- `DrawnPathSampler.sample()`의 시그니처 변경 없음 — 기존 호출 코드(`CoursePlannerPageViewModel.incrementalRoute`)와 기존 테스트가 그대로 통과해야 함
- `minSpacingMeters` 기본값 120m 유지 (잠정 값 — 실기기 스로틀 테스트 후 조정 가능)
- `MapKitCoursePlanningService`는 `CoursePlanningServiceProtocol`만 변경 — 호출 측 코드 변경 없음
- TDD: 테스트를 먼저 작성해 실패를 확인한 뒤 구현

---

## 파일 구조

| 역할 | 파일 | 변경 |
|------|------|------|
| 샘플러 로직 | `Trace/Domain/CoursePlanning/DrawnPathSampler.swift` | 수정 |
| 샘플러 테스트 | `TraceTests/DrawnPathSamplerTests.swift` | 수정 (테스트 추가) |
| 스로틀 감지 | `Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift` | 수정 |

---

## Task 1: DrawnPathSampler 루프 버그 수정 (TDD)

**Files:**
- Modify: `TraceTests/DrawnPathSamplerTests.swift`
- Modify: `Trace/Domain/CoursePlanning/DrawnPathSampler.swift`

**Interfaces:**
- `DrawnPathSampler.sample(_ raw: [CourseCoordinate], minSpacingMeters: Double = 120) -> [CourseCoordinate]` — 시그니처 불변, 동작만 변경

**핵심 동작 변경:**
- 기존: `last.distanceMeters(to: point) >= minSpacingMeters` (마지막 샘플 포인트로부터의 직선거리)
- 수정: 원본 획을 따라 이동한 누적거리가 `minSpacingMeters` 이상일 때 포인트 보존

- [ ] **Step 1: 루프 버그 재현 테스트 작성**

`TraceTests/DrawnPathSamplerTests.swift` 에 아래 두 테스트를 추가:

```swift
func testLoopStrokeNotCollapsedToTwoPoints() {
    // 반지름 ~55m 원 (둘레 ≈ 346m) — 30도 간격 12포인트
    // 누적거리 기반이면 ≥3개 포인트가 나와야 함
    // 기존 구현(직선거리)에서는 원의 지름(~110m) < 120m이므로 [시작, 끝] 2개만 나옴
    let loop = makeCircleCoordinates(
        center: CourseCoordinate(latitude: 37.5, longitude: 127.0),
        radiusLatOffset: 0.0005,
        stepDegrees: 30
    )
    let result = DrawnPathSampler.sample(loop, minSpacingMeters: 120)
    XCTAssertGreaterThan(result.count, 2,
        "루프 획은 시작/끝 2개로 축소되어서는 안 됩니다. 실제 count: \(result.count)")
    XCTAssertEqual(result.first, loop.first, "시작점은 항상 보존")
    XCTAssertEqual(result.last, loop.last, "끝점은 항상 보존")
}

func testCumulativeDistancePreservesStrokeOrder() {
    let loop = makeCircleCoordinates(
        center: CourseCoordinate(latitude: 37.5, longitude: 127.0),
        radiusLatOffset: 0.0005,
        stepDegrees: 30
    )
    let result = DrawnPathSampler.sample(loop, minSpacingMeters: 120)
    // 결과 포인트들이 원본 배열에서 단조증가 인덱스로 등장해야 함
    var lastIndex = -1
    for point in result {
        if let idx = loop.firstIndex(of: point) {
            XCTAssertGreaterThan(idx, lastIndex,
                "샘플 포인트가 원본 획의 순서를 따라야 합니다")
            lastIndex = idx
        }
    }
}

// MARK: - Helpers (파일 하단에 추가)

private func makeCircleCoordinates(
    center: CourseCoordinate,
    radiusLatOffset: Double,
    stepDegrees: Double
) -> [CourseCoordinate] {
    // longitude 보정: 위도에 따라 경도 1도의 실제 거리가 줄어드므로 보정
    let lonScale = cos(center.latitude * .pi / 180)
    return stride(from: 0.0, to: 360.0, by: stepDegrees).map { angle in
        let rad = angle * .pi / 180
        return CourseCoordinate(
            latitude: center.latitude + radiusLatOffset * cos(rad),
            longitude: center.longitude + (radiusLatOffset / lonScale) * sin(rad)
        )
    }
}
```

- [ ] **Step 2: 새 테스트가 실패하는지 확인**

Xcode에서 `testLoopStrokeNotCollapsedToTwoPoints`만 실행:

```
Xcode → Test Navigator → DrawnPathSamplerTests → testLoopStrokeNotCollapsedToTwoPoints → Run
```
Expected: **FAIL** — "루프 획은 시작/끝 2개로 축소되어서는 안 됩니다. 실제 count: 2"

- [ ] **Step 3: DrawnPathSampler 누적거리 기반으로 교체**

`Trace/Domain/CoursePlanning/DrawnPathSampler.swift` 전체를 아래로 교체:

```swift
import Foundation

enum DrawnPathSampler {
    static func sample(_ raw: [CourseCoordinate], minSpacingMeters: Double = 120) -> [CourseCoordinate] {
        guard let first = raw.first else { return [] }
        var result = [first]
        var accumulated = 0.0
        var prev = first
        for point in raw.dropFirst() {
            accumulated += prev.distanceMeters(to: point)
            if accumulated >= minSpacingMeters {
                result.append(point)
                accumulated = 0.0
            }
            prev = point
        }
        if let last = raw.last, last != result.last {
            result.append(last)
        }
        return result
    }
}
```

- [ ] **Step 4: 전체 DrawnPathSampler 테스트 실행**

```
Xcode → Test Navigator → DrawnPathSamplerTests → Run All
```
Expected: **모든 테스트 통과** (기존 4개 + 신규 2개 = 6개)

기존 테스트와 신규 테스트의 예상 결과:
- `testEmptyReturnsEmpty` → PASS
- `testSinglePointPreserved` → PASS
- `testEndpointsAlwaysPreservedEvenIfClose` → PASS
- `testDownsamplesByMinSpacing` → PASS (직선 획에서 기존과 동일 동작)
- `testLoopStrokeNotCollapsedToTwoPoints` → PASS (신규)
- `testCumulativeDistancePreservesStrokeOrder` → PASS (신규)

- [ ] **Step 5: 커밋**

```bash
git add TraceTests/DrawnPathSamplerTests.swift \
        Trace/Domain/CoursePlanning/DrawnPathSampler.swift
git commit -m "fix(drawing-precision): DrawnPathSampler 누적거리 기반으로 교체 — 루프 경로 0.01km 버그 수정"
```

---

## Task 2: 스로틀 에러 감지 실기기 디버그 및 수정

**Files:**
- Modify: `Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift`

**배경:** 현재 코드는 `GEOErrorDomain Code=-3`, `MKErrorDomain Code=3`, `MKError.loadingThrottled`를 감지한다. 실기기에서는 이 중 어느 것도 매칭되지 않아 스로틀 에러 메시지가 표시되지 않는다. 실기기에서 실제 에러를 확인해 감지 로직을 수정해야 한다.

> **주의:** 이 태스크는 **실기기(iPhone)**가 필요하다. 시뮬레이터에서는 MKDirections 스로틀이 발생하지 않는다.

- [ ] **Step 1: 로깅 개선 — 스로틀 에러 패스스루 확인**

`Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift` 의 `catch` 블록을 확인한다. 아래 `#if DEBUG` 로그가 이미 존재하는지 확인:

```swift
#if DEBUG
print("[MapKitCoursePlanning] Unhandled error: domain=\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
#endif
```

없으면 `throw CoursePlanningError.requestFailed` 바로 위에 추가.

- [ ] **Step 2: 실기기 DEBUG 빌드로 배포**

```
Xcode → 실기기 연결 → Scheme: Trace → Run (⌘R)
```

- [ ] **Step 3: 스로틀 유도 — 빠른 연속 그리기**

앱 실행 후:
1. 그리기 모드 진입
2. 지도 위에 짧은 획을 1~2초 간격으로 10회 이상 반복 (Undo 없이 계속 추가)
3. Xcode Console 창 열어두기

Expected: Xcode Console에 아래 형식의 로그 출력:
```
[MapKitCoursePlanning] Unhandled error: domain=<실제도메인> code=<실제코드> <에러메시지>
```

- [ ] **Step 4: 실제 domain/code로 isThrottled 조건 업데이트**

Step 3에서 확인한 domain과 code를 `MapKitCoursePlanningService.swift` 의 `isThrottled` 조건에 추가:

```swift
// 기존 코드 (수정 전):
let isThrottled =
    (nsError.domain == "GEOErrorDomain" && nsError.code == -3) ||
    (nsError.domain == "MKErrorDomain" && nsError.code == 3) ||
    (nsError.domain == MKError.errorDomain && nsError.code == MKError.loadingThrottled.rawValue)

// 수정 후 예시 (실제 로그에서 확인한 값으로 교체):
// 예) 로그에 domain="GEOErrorDomain" code=4 가 나왔다면:
let isThrottled =
    (nsError.domain == "GEOErrorDomain" && nsError.code == -3) ||
    (nsError.domain == "GEOErrorDomain" && nsError.code == 4) ||  // ← 실제 확인값
    (nsError.domain == "MKErrorDomain" && nsError.code == 3) ||
    (nsError.domain == MKError.errorDomain && nsError.code == MKError.loadingThrottled.rawValue)
```

> 로그에 domain/code가 나타나지 않은 경우: 스로틀이 아닌 다른 에러(routeNotFound 등)일 수 있다. 더 많은 획을 추가하거나 연속 그리기 간격을 줄여 재시도.

- [ ] **Step 5: 실기기 재배포 — 스로틀 에러 메시지 표시 확인**

수정 후 다시 실기기에 배포하고 Step 3의 빠른 연속 그리기 반복.

Expected: 상태 패널에 "요청이 많아 잠시 후 다시 시도해주세요" 메시지 표시.

- [ ] **Step 6: 빌드 + 전체 테스트 확인**

```
Xcode → Product → Test (⌘U)
```
Expected: TraceTests 전체 통과.

- [ ] **Step 7: 커밋**

실제로 확인된 domain/code를 커밋 메시지에 기록:

```bash
git add Trace/Infrastructure/CoursePlanning/MapKit/MapKitCoursePlanningService.swift
git commit -m "fix(drawing-precision): 스로틀 에러 감지 수정 — 실기기 확인 domain/code 추가"
```
