---
title: "bottomSheet 하위의 모든 accessibilityIdentifier가 자식 고유값 대신 부모(coursePlanner.segmentPanel)로 뭉개져 XCUITest 식별자 조회가 안 된다"
date: 2026-07-13
category: workflow-issues
module: CoursePlannerPage
problem_type: workflow_issue
component: testing_framework
severity: medium
applies_when:
  - "XCUITest에서 CoursePlannerPage의 bottomSheet 내부 자식(그래버, 접힌 헤더, 저장/전체왕복 버튼, 구간 리스트 행 등)을 accessibilityIdentifier로 조회할 때"
tags: [swiftui, accessibility, xcuitest, identifier, bottom-sheet]
related_components: [CoursePlannerPage, TraceUITests]
---

# bottomSheet 하위의 모든 accessibilityIdentifier가 자식 고유값 대신 부모로 뭉개진다

## Context

`CoursePlannerPage+BottomSheetComponent.swift`의 `bottomSheet` 하위 자식들(그래버 `coursePlanner.segmentPanel.grabber`, 접힌 헤더 `coursePlanner.segmentPanel.collapsed`, 저장 `coursePlanner.saveCourse`, 전체 왕복 `coursePlanner.wholeCourseRoundTrip`, 구간 행 `coursePlanner.segmentPanel.item.N` 등)은 각각 고유한 `accessibilityIdentifier`가 코드에 명시돼 있다. 그런데 XCUITest에서 `app.debugDescription`으로 접근성 트리를 덤프해보면, 이 자식들이 **전부** `identifier: 'coursePlanner.segmentPanel'`(bottomSheet 루트 VStack에 걸린 식별자)로 나타난다 — 자기 자신의 식별자가 아니라 부모 것으로 뭉개져 있다. `label`(예: "저장", "1.20, km, 도보 기준 · 탭해서 이어 그리기")은 각자 올바르게 유지된다.

정확한 메커니즘(어떤 모디파이어 조합이 이걸 일으키는지)은 이번 세션에서 특정하지 못했다 — `bottomSheet`가 `.background { ... .contentShape(Rectangle()).onTapGesture {} }` 히트테스트 백스톱을 가진 채로 루트에 `.accessibilityIdentifier("coursePlanner.segmentPanel")`를 걸고 있는 구조와 관련 있을 가능성이 있지만 확인되지 않았다.

## Guidance

- **`app.buttons["coursePlanner.segmentPanel.collapsed"]`처럼 bottomSheet 하위 자식을 식별자로 직접 조회하는 XCUITest 코드는 실패하거나 엉뚱한(부모) 엘리먼트를 반환할 수 있다.** 이 계층에서 자식을 정확히 짚어야 한다면:
  1. **좌표 기반 우회**: `map.tapCoordinate(xRatio:yRatio:)`처럼 화면 비율 좌표로 직접 탭한다. 대상의 실제 화면 위치는 먼저 `app.debugDescription`으로 한 번 확인해서 좌표를 구한다.
  2. **동일 식별자 다중 매치 + 위치/크기로 구분**: `app.otherElements.matching(identifier: "coursePlanner.segmentPanel").allElementsBoundByIndex`로 전체 후보를 가져온 뒤, `frame.height`가 가장 큰 것(=루트 컨테이너)이나 `frame.origin.y`가 가장 작은 것(=그래버처럼 맨 위 자식) 등 프레임 특성으로 원하는 엘리먼트를 골라낸다.
  3. **label 기반 조회**: `identifier` 대신 `label`로 쿼리하면(`app.buttons["저장"]` 등) 이 뭉개짐의 영향을 받지 않는다. 다만 label은 UI 카피가 바뀌면 깨지므로 국지적으로만 사용한다.
- bottomSheet **바깥**(topBar, fabStack 등)의 식별자는 이 문제의 영향을 받지 않는다 — `app.buttons["coursePlanner.courseList"]`, `coursePlanner.undo/redo/clear/recenter`는 정상적으로 각자의 식별자를 유지한다. 영향 범위는 `bottomSheet` 서브트리로 한정된 것으로 보인다.

## Why This Matters

이 뭉개짐은 **실제 사용자 경험이나 VoiceOver에는 영향이 없다**(VoiceOver는 주로 `label`을 읽지 `identifier`를 읽지 않는다) — 순수하게 XCUITest 자동화에서만 문제가 된다. 하지만 이 세션 초반에 `app.buttons["coursePlanner.segmentPanel.collapsed"].tap()` 같은 코드가 "No matches found" 에러로 계속 실패하면서, 실제 버그(레이아웃 움찔거림, 안전영역 피드백 루프) 진단이 지연됐다. 이 현상을 미리 알고 있었다면 좌표 기반 우회로 바로 넘어가 시간을 아꼈을 것이다.

## When to Apply

- `CoursePlannerPage`의 `bottomSheet` 서브트리 내부 엘리먼트를 대상으로 새 XCUITest를 작성할 때
- 기존 UI 테스트가 "No matches found for Elements matching predicate ... IN identifiers"로 실패하는데 코드상 identifier는 분명히 걸려 있을 때 — 먼저 `app.debugDescription`을 덤프해 실제 identifier가 뭉개졌는지부터 확인한다

## Examples

```swift
// 실패: 자식 identifier로 직접 조회
app.buttons["coursePlanner.segmentPanel.collapsed"].tap()  // No matches found

// 우회 1: 좌표 기반
map.tapCoordinate(xRatio: 0.251, yRatio: 0.883)  // 헤더 위치를 미리 확인한 좌표

// 우회 2: 동일 식별자 다중 매치 중 프레임으로 구분
let candidates = app.otherElements
    .matching(identifier: "coursePlanner.segmentPanel")
    .allElementsBoundByIndex
let grabber = candidates.min(by: { $0.frame.origin.y < $1.frame.origin.y })
let root = candidates.max(by: { $0.frame.height < $1.frame.height })
```

## Related

- `docs/solutions/ui-bugs/firsttextbaseline-alignment-jiggle-with-mixed-child-types.md` — 이 식별자 뭉개짐 문제를 우회하며 진단한 버그.
- `docs/solutions/ui-bugs/safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md` — 같은 세션, 같은 우회 방식으로 진단한 또 다른 버그.
- `docs/agent-rules/testing.md`의 "UI 테스트 실패 원인 파악 순서" — 이 문서는 "요소가 안 나타난다"는 실패를 다루지만, 이번 건은 "요소는 있는데 identifier가 다르다"는 별개의 실패 양상이라 그 섹션의 접근성 트리 덤프 습관과 함께 알아두면 좋다.
