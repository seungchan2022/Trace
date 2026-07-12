---
title: "HStack(alignment: .firstTextBaseline)에서 자식의 '첫 서브뷰 타입'이 Text↔비-Text로 바뀌면 개별 뷰 크기는 그대로인데 전체 높이가 흔들린다"
date: 2026-07-13
category: ui-bugs
module: CoursePlannerPage
problem_type: ui_bug
component: rails_view
symptoms:
  - "경로 계산이 시작될 때(구간 추가 등) 바텀시트 헤더가 아주 짧게 커졌다가(로딩 완료 시) 다시 원래 크기로 줄어든다"
  - "거리 숫자, 서브타이틀, StatusChip 각각의 높이를 개별로 실측하면 로딩 전/중/후 전혀 변화가 없다"
  - "그런데도 헤더 전체(HStack)의 바깥 프레임 높이는 로딩 중에만 약 10~11pt 더 크게 측정된다"
root_cause: wrong_api
resolution_type: code_fix
severity: medium
applies_when:
  - "HStack(alignment: .firstTextBaseline) 또는 .lastTextBaseline으로 두 개 이상의 이질적인 컬럼(예: 텍스트 컬럼과 '아이콘+텍스트'가 조건부로 바뀌는 컬럼)을 나란히 배치할 때"
  - "그 중 한 컬럼의 '첫 번째 자식 뷰'가 상태에 따라 Text ↔ 비-Text(ProgressView, Image 등)로 바뀔 때"
tags: [swiftui, hstack, firsttextbaseline, alignment, layout-jiggle, statuschip, baseline]
related_components: [CoursePlannerPage, StatusChip]
---

# HStack(alignment: .firstTextBaseline)에서 자식의 '첫 서브뷰 타입'이 Text↔비-Text로 바뀌면 개별 뷰 크기는 그대로인데 전체 높이가 흔들린다

## Problem

`CoursePlannerPage+BottomSheetComponent.swift`의 `sheetHeader`는 `HStack(alignment: .firstTextBaseline)`로 왼쪽(거리+서브타이틀) 컬럼과 오른쪽(StatusChip+버튼) 컬럼을 나란히 배치한다. 경로 계산 중(`isLoading == true`)에는 오른쪽 컬럼의 `StatusChip`이 `.calculating` variant(`ProgressView` + `Text("계산 중")`)로 바뀌고, 평상시엔 `.route` variant(`Text(segmentLabel)` + `Image(chevron)`)를 보여준다. 이 전환이 일어날 때마다 헤더 전체 높이가 순간적으로 커졌다가 돌아오는 움찔거림이 있었다.

## Symptoms

- 실기기/시뮬레이터에서 지도를 탭해 구간을 추가할 때마다 바텀시트 헤더가 살짝 위로 올라갔다 내려오는 것이 육안으로 보임
- 개별 하위 뷰(칩, 서브타이틀, 좌/우 컬럼 각각)의 `onGeometryChange` 높이 실측값은 로딩 전/중/후 **전혀 변하지 않음** (예: chipH=27.67, subH=16.33, leftH=73.0, rightH=64.0 — 모두 동일)
- 그런데도 `sheetHeader` 자신의 `onGeometryChange` 높이는 대기 105.0 → 로딩 중 131.17 → 완료 후 105.0 으로 흔들림 (수정 전 값 기준)

## What Didn't Work

- **자기측정 순환(self-measuring-frame) 이론**: 이전 세션에서 문서화한 `docs/solutions/design-patterns/self-measuring-frame-causes-layout-jiggle.md`의 패턴(콘텐츠 높이를 측정해 같은 뷰의 프레임에 되먹임)이 원인일 거라 가정하고 그 문서의 체크리스트만 재확인했다. 이 세션의 코드에는 이미 그 순환이 없었다(전 세션에 고쳐졌음) — 다른 원인을 찾아야 했다.
- **StatusChip 자체의 높이 차이 이론**: `.calculating`의 `ProgressView`가 `.controlSize(.mini)` + `.frame(width:14,height:14)`로 이미 명시적으로 눌려있어 칩 자체 높이는 두 variant가 동일하다(2026-07-12 수정, 코드 주석에 기록됨). 칩 높이를 직접 실측해도 로딩 전/중 차이가 없어 이 이론은 기각됐다.
- **distanceText가 로딩 중 nil이 되어 "0" 플레이스홀더로 바뀌는 이론**: 실측해보니 로딩 중에도 `viewModel.distanceText`는 기존 값("1.20 km")을 그대로 유지하고 있었다(새 구간이 실제로 `course`에 반영되는 건 계산 완료 후이므로). 이 경로도 아니었다.
- **subtitleText 줄바꿈 이론**: "경로를 계산하고 있어요"(로딩 중)와 "도보 기준 · 탭해서 이어 그리기"(평상시)의 렌더링 폭 차이로 2줄 wrap이 생기는지 의심했으나, 서브타이틀 자신의 실측 높이가 두 상태에서 동일해 기각됐다.

## Solution

각 하위 뷰에 임시 `onGeometryChange` + 숨김 진단 `Text`(`-traceUITesting` 플래그로 게이팅)를 붙여 chip/subtitle/leftColumn/rightColumn 높이를 개별 실측했다. 전부 동일한데 오직 `sheetHeader`의 **바깥 HStack 자체의 측정값만** 흔들리는 것을 확인하고, `HStack(alignment: .firstTextBaseline)`을 의심해 `.top`으로 바꿔 재현·검증했다.

```diff
-    HStack(alignment: .firstTextBaseline) {
+    HStack(alignment: .top) {
```

수정 후 실측: 대기 105.0 → 로딩 중 105.0 → 완료 후 105.0 (완전히 고정).

## Why This Works

`.firstTextBaseline` 정렬은 HStack의 각 직계 자식이 노출하는 "첫 번째 텍스트 베이스라인" 정렬 가이드를 기준으로 전체 높이를 계산한다. 컨테이너 뷰(VStack 등)의 첫 베이스라인은 재귀적으로 **그 첫 번째 자식**의 베이스라인을 상속한다.

오른쪽 컬럼(`VStack(alignment: .trailing) { StatusChip; buttonsRow }`)의 첫 자식은 `StatusChip`이고, `StatusChip`은 내부적으로 `HStack(spacing: 6) { <아이콘류>; <텍스트> }` 구조다:
- `.route` variant: 첫 서브뷰가 `Text(segmentLabel)` → 진짜 글리프 베이스라인을 제공
- `.calculating` variant: 첫 서브뷰가 `ProgressView`(비-텍스트) → 텍스트 베이스라인이 없어 SwiftUI가 대체 기준점(대략 뷰의 수직 중심/하단)으로 폴백

두 variant가 컨테이너에 노출하는 "첫 베이스라인" 자체의 기준점이 다르므로, `firstTextBaseline`으로 왼쪽 컬럼과 정렬을 맞추는 과정에서 필요한 전체 바운딩 박스 크기가 달라진다 — 개별 자식의 실제 렌더 크기는 하나도 안 바뀌었는데, **정렬 기준점의 차이 때문에 부모 HStack의 계산된 전체 높이만** 바뀌는 것이다. `.top` 정렬은 베이스라인 계산 자체를 쓰지 않으므로 이 클래스의 문제를 원천 차단한다.

## Prevention

- **"레이아웃이 잠깐 움찔거렸다 돌아온다"는 보고를 받으면, 먼저 `HStack`/`VStack`에 `.firstTextBaseline`/`.lastTextBaseline` 정렬이 쓰였는지, 그리고 그 정렬 대상 자식들의 "첫 서브뷰 타입"이 상태에 따라 Text ↔ 비-Text로 바뀌는지 확인한다.** 개별 하위 뷰 높이가 전혀 안 바뀌는데 부모 컨테이너 높이만 흔들린다면 이 패턴을 최우선으로 의심한다.
- 베이스라인 정렬이 꼭 필요한 게 아니라면(텍스트 두 줄을 시각적으로 정확히 맞춰야 하는 경우가 아니라면), 기본값인 `.center`나 `.top`을 쓰는 편이 이 클래스의 버그를 원천적으로 피한다.
- **실측 방법**: 의심되는 하위 뷰마다 임시 `onGeometryChange(for: CGFloat.self) { $0.size.height } action: { ... }`를 붙이고, 그 값들을 `-traceUITesting` 플래그로 게이팅한 숨김 `Text`(`.opacity(0.01)`, `accessibilityIdentifier`)로 노출한 뒤, XCUITest에서 `app.staticTexts["diag.state"].label`을 짧은 간격(예: 20ms)으로 폴링해 실제 전이 순간의 값을 잡는다. 목업 서비스가 즉시 응답하면 로딩 구간이 폴링 간격보다 짧아 못 잡을 수 있으니, 필요하면 목업에 짧은 인위적 지연(`Task.sleep`)을 임시로 추가해 관찰 창을 넓힌다. 확인이 끝나면 이 진단 코드는 전부 제거한다.

## Related Issues

- `docs/solutions/design-patterns/self-measuring-frame-causes-layout-jiggle.md` — 같은 "움찔거림" 증상으로 오인되어 먼저 문서화됐던 **다른** 버그(자기측정 순환). 두 문서는 증상 설명이 비슷해 보이지만 원인이 다르므로, 움찔거림 재현 시 두 체크리스트를 모두 확인해야 한다.
- `docs/solutions/ui-bugs/frame-maxheight-inflates-zstack-child-and-swallows-taps.md` — 같은 컴포넌트에서 발생한 별개의 프레임 버그.
