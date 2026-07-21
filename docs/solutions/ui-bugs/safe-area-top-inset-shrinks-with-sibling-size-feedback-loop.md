---
title: "GeometryProxy.safeAreaInsets.top이 형제 뷰가 커질수록 더 작은 값을 보고해, 그 값으로 형제 크기를 다시 계산하면 피드백 루프가 생긴다"
date: 2026-07-13
category: ui-bugs
module: CoursePlannerPage
problem_type: ui_bug
component: rails_view
symptoms:
  - "바텀시트를 'full' 디텐트까지 드래그하면 시트 상단이 상태바/다이내믹 아일랜드를 실제로 덮는다(스크린샷: 시간 텍스트가 시트 모서리에 잘려 보임)"
  - "같은 화면에서 상단바(topBar)의 접근성 프레임 y좌표가 collapsed/medium(70)에서 full(48)로 22pt 위로 밀린 것이 실측됨"
  - "topBar 자신은 이 값을 직접 쓰지 않는데도(자동 safe-area 패딩에 의존) 위치가 바뀐다 — 즉 시스템이 실제로 보고하는 안전영역 자체가 줄어든다"
root_cause: logic_error
resolution_type: code_fix
severity: high
applies_when:
  - "ZStack 안에서 onGeometryChange(for: CGFloat.self) { proxy.safeAreaInsets.top }로 측정한 값을, 같은 ZStack의 다른(형제) 뷰의 최대 높이 계산에 다시 사용할 때"
  - "그 형제 뷰가 .ignoresSafeArea(edges: .bottom) 등으로 화면 하단까지 확장되며, 계산된 높이가 top safe area 경계에 가깝게 커질 수 있을 때"
tags: [swiftui, safeareainsets, geometryreader, feedback-loop, bottom-sheet, dynamic-island]
related_components: [CoursePlannerPage]
---

# GeometryProxy.safeAreaInsets.top이 형제 뷰가 커질수록 더 작은 값을 보고해, 그 값으로 형제 크기를 다시 계산하면 피드백 루프가 생긴다

> **⚠️ 이 문서의 해결책은 2026-07-21에 폐기됐다 — 되살리지 말 것.**
>
> 아래에 적힌 대응(안전영역을 측정해 ratchet으로 붙들고, 남은 잔여분을 `sheetTopMargin`으로
> 흡수)은 **시트 높이가 안전영역 측정값을 소비한다**는 전제 위에 있었다. 그 전제가 사라졌다:
> 지금 `maxSheetHeight`는 `pageHeight - sheetTopMargin`이고 안전영역 측정값을 쓰지 않는다.
> `pageHeight`는 body의 ZStack을 감싸는 GeometryReader가 보고하는 "부모가 제안한 크기"라
> 정의상 안전영역이 이미 제외돼 있고, 자식이 무엇을 하든 바뀌지 않아 되먹임 고리 밖에 있다.
>
> 그 결과 `SafeAreaInsetLatch`와 `topSafeAreaInset`은 삭제됐고, `sheetTopMargin`은 0이다.
> **아래 진단(왜 루프가 생기는가)은 여전히 유효하고 다른 화면에서 재현될 수 있다.**
> 다만 처방은 "측정해서 붙들고 흡수한다"가 아니라 **"되먹임을 타지 않는 앵커를 쓰고,
> 그 앵커에 이미 반영된 항을 다시 빼지 않는다"**로 바뀌었다.
>
> 이 교체 과정에서 파생된 별개의 회귀(앵커만 바꾸고 파생 항을 안 걷어내 62pt를 두 번 뺌)는
> [`anchor-swap-leaves-orphaned-derived-term.md`](anchor-swap-leaves-orphaned-derived-term.md) 참고.

## Problem

`CoursePlannerPage.swift`는 `.onGeometryChange(for: CGFloat.self) { proxy.safeAreaInsets.top }`로 상단 안전영역을 측정해 `topSafeAreaInset` state에 저장하고, 이 값을 `bottomSheet`의 `maxSheetHeight = mapHeight - topSafeAreaInset - sheetTopMargin` 계산에 사용해 "full" 디텐트가 상태바/다이내믹 아일랜드 바로 아래에서 멈추도록 했다. 그런데 시트가 "full"에 가까워질수록 이 `topSafeAreaInset` 측정값 자체가 더 작게 보고되는 현상이 있었고, 그 결과 `maxSheetHeight`가 더 커지고 → 시트가 더 커지고 → 안전영역이 더 줄고 … 하는 피드백 루프가 발생해 시트가 실제로 상태바를 덮었다.

## Symptoms

- XCUITest로 `topSafeAreaInset`을 직접 실측: medium 디텐트에서 62pt, full 디텐트에서 40pt로 실제로 줄어듦(`mapHeight`, `sheetHeaderHeight`는 이 구간에서 변화 없음)
- topBar(오른쪽 상단 버튼)의 접근성 프레임 y좌표가 collapsed/medium(70)에서 full(48)로 22pt 밀림 — topBar는 이 state 값을 직접 참조하지 않고 SwiftUI 자동 safe-area 패딩에만 의존하므로, 이는 **시스템이 실제로 보고하는 안전영역이 줄었다**는 뜻
- 스크린샷으로 확인 시 full 디텐트에서 시트 상단이 상태바 시간 텍스트를 실제로 가림

## What Didn't Work

- **다이내믹 아일랜드가 스크린샷에 안 찍힐 것이라는 가정**: 시뮬레이터의 다이내믹 아일랜드는 실제 카메라 하드웨어가 아니라 검은 pill 그래픽으로 렌더링되며, 스크린샷에 그대로 캡처된다. 이 전제로 문제를 재해석하려 한 시도는 방향이 틀렸다 — 실제로는 시트가 그 위치까지 진짜로 자라난 것이었다.
- **여유값(`sheetTopMargin`)만 늘리면 될 거라는 가정**: 처음엔 12pt 여유값이 부족한 줄 알았으나, 근본 원인(측정값 자체가 줄어드는 피드백 루프)을 고치지 않고 여유값만 늘리면 루프가 여전히 남아있어 일부는 완화되지만 완전히 없어지지 않는다(피드백 루프를 끊은 뒤 남은 잔여분만 여유값으로 흡수해야 함).

## Solution

1. **피드백 루프를 끊는다**: 한 번 측정한 `topSafeAreaInset`보다 작은 값이 들어오면 무시한다(ratchet-up). 이 화면은 기기 회전이 없으므로 진짜 안전영역은 세션 내내 고정값이라 안전하다.

```diff
     .onGeometryChange(for: CGFloat.self) { proxy in
         proxy.safeAreaInsets.top
-    } action: { topSafeAreaInset = $0 }
+    } action: { newValue in
+        if newValue > topSafeAreaInset { topSafeAreaInset = newValue }
+    }
```

2. **잔여분을 여유값으로 흡수한다**: 루프를 끊은 뒤에도 시스템이 보고하는 실제 안전영역이 약간(이 경우 11pt) 줄어드는 현상이 남아있었다 — `sheetTopMargin`을 12pt → 40pt로 늘려 이 잔여분까지 흡수한다.

수정 후 실측: `topSafeAreaInset` 62pt로 고정(더 이상 40으로 안 줄어듦), topBar y좌표가 collapsed/medium/full 전 구간에서 70으로 고정, 스크린샷에서도 시트가 상태바를 덮지 않음.

### 2026-07-20 갱신: "회전이 없다" 전제가 깨진 뒤의 형태

가로모드 지원(MVP16 tab-restructure)으로 "이 화면은 기기 회전이 없다"는 전제가 깨졌다 —
세로에서 latch된 62pt가 가로(진짜 top inset 0)에서도 유지되는 stale 문제가 실측됐다
(`.git/sdd/task-landscape-layout-report.md`). 단, 이 stale 값은 가로에서 시트를 *짧게* 누르는
보호막이기도 해서, **ratchet만 단독으로 고치면 가로 full에서 시트가 실제로 화면 위로 뚫린다**
(실측: 시트 top y=-56). 수정은 반드시 ① RootView 구조 클램프(GeometryReader) ② 시트 예산
min-클램프(pageHeight) ③ ratchet의 size class별 분리(`SafeAreaInsetLatch`) 순서로 진행해야
한다. 상세: `docs/superpowers/plans/2026-07-20-landscape-sheet-overflow.md`.

## Why This Works

`proxy.safeAreaInsets.top`은 이론상 시스템 UI(노치/다이내믹 아일랜드/상태바)가 차지하는 고정 영역이어야 하지만, 실제로는 같은 화면 트리 안의 다른 뷰가 화면을 거의 다 채우는 것처럼 보이는 순간 iOS/SwiftUI가 이 값을 동적으로 더 작게 보고하는 경우가 있다(이 세션에서는 `bottomSheet`가 `.ignoresSafeArea(edges: .bottom)`로 확장되며 top safe area 경계에 매우 가깝게 커질 때 관찰됨). 이 측정값을 **같은 뷰의 크기 계산에 그대로 되먹이면**, 값이 줄어들수록 계산된 크기가 커지고, 커진 크기가 다시 값을 더 줄이는 악순환이 생긴다. 측정값에 "이전 값보다 작아지면 무시" 규칙을 걸면, 최초의(신뢰할 수 있는) 측정값이 고정되어 루프가 원천적으로 성립하지 않는다.

## Prevention

- **어떤 `@State`가 (a) `GeometryProxy`로 측정되고 (b) 그 값이 같은 트리의 형제/자신의 프레임 계산에 다시 쓰인다면, 값이 줄어드는 방향으로도 피드백 루프가 성립하는지 항상 검토한다.** `docs/solutions/design-patterns/self-measuring-frame-causes-layout-jiggle.md`가 다루는 "자기 자신을 측정해 자기 프레임에 되먹이는" 순환과 같은 계열이지만, 이번 건은 "자기 자신"이 아니라 **시스템이 보고하는 값(safeAreaInsets)이 자신의 크기 변화에 의해 간접적으로 영향받는** 더 미묘한 변형이다.
- `safeAreaInsets`처럼 "원래는 고정이어야 할" 시스템 측정값을 파생 계산에 쓸 때는, 회전/멀티태스킹 등 정당한 변화가 없는 화면이라면 ratchet(단조 증가만 허용) 패턴을 기본으로 고려한다.
- 이런 버그는 실기기 스크린샷만으로는 "얼마나 겹치는지"까지만 보이고 "왜 겹치는지"는 안 보인다 — 의심되는 state 값(`topSafeAreaInset`, `mapHeight`, `sheetHeaderHeight` 등)을 직접 실측 노출(임시 `onGeometryChange` + 숨김 진단 텍스트 + XCUITest 폴링)해서 어떤 값이 실제로 움직이는지 좁혀야 근본 원인에 도달한다.

## Related Issues

- `docs/solutions/ui-bugs/frame-maxheight-inflates-zstack-child-and-swallows-taps.md` — 같은 `maxSheetHeight`/full 디텐트 영역에서 발생한 별개의 이전 버그(오버슈트 방어를 `bottomSheet` 전체에 걸었다가 히트테스트가 깨진 사례). 이번 건은 그 교훈(오버슈트 방어는 `expandedSheetBody` 내부 리스트에만 걸어야 한다)을 그대로 유지한 채, `maxSheetHeight` 계산 자체에 쓰이는 입력값의 피드백 루프를 고친 것이다.
- `docs/solutions/design-patterns/self-measuring-frame-causes-layout-jiggle.md` — "측정값을 같은 트리에 되먹이면 안 된다"는 같은 원칙의 다른 사례.
