---
title: "ZStack 안에서 .frame(maxHeight:, alignment: .top)이 형제 뷰 앞에서 콘텐츠를 화면 위로 밀어올리고 탭을 삼킨다"
date: 2026-07-12
category: ui-bugs
module: CoursePlannerPage
problem_type: ui_bug
component: rails_view
symptoms:
  - "Collapsed 상태 바텀시트(grabber + 한 줄 헤더)가 화면 하단이 아니라 상단(874pt 화면 기준 y≈62~192)에 렌더된다"
  - "지도를 두 번 탭해 경로를 생성해도 반응이 없고, 화면은 계속 유휴 상태 문구('0, 지도를 탭해 출발지를 선택하세요')를 보여준다"
  - "undo/redo/clear 버튼이 계속 Disabled 상태로 남아 경로가 전혀 생성되지 않았음을 확인시켜 준다"
  - "TraceUITests.testSelectingTwoPointsShowsDistance, testRouteFailureShowsError 두 UI 테스트가 실패한다"
root_cause: wrong_api
resolution_type: code_fix
severity: high
applies_when:
  - "ZStack(alignment:) 안에서, 전체 화면을 차지하는 형제 뷰(.ignoresSafeArea() 등)와 나란히 자기 콘텐츠보다 작은 자식 뷰를 배치할 때"
  - "그 자식 뷰에 idealHeight/정확한 height 없이 .frame(maxHeight:, alignment:)만 적용해 '이 정도까지만 커지게' 제한하려 할 때"
tags: [swiftui, zstack, maxheight, layout, bottom-sheet, hit-testing, xcresulttool, xctest]
related_components: [CoursePlannerPage, MapView, XCTest-UI-automation]
---

# ZStack 안에서 .frame(maxHeight:, alignment: .top)이 형제 뷰 앞에서 콘텐츠를 화면 위로 밀어올리고 탭을 삼킨다

## Problem

`CoursePlannerPage.swift`의 `bottomSheet`(풀 디텐트가 상태바/다이내믹 아일랜드까지 자라는 것을 막기 위한 안전장치)에 `.frame(maxHeight:)` + `.clipped()`를 추가했다가, `ZStack` 레이아웃 특성상 시트가 화면 상단 근처로 밀려 올라가고 그 위에 얹힌 투명 히트테스트 배경이 지도 탭을 통째로 가로채는 회귀가 발생했다. 사용자 입장에서는 지도 위 두 지점을 탭해도 거리 계산/에러 표시가 전혀 뜨지 않는다.

## Symptoms

- `TraceUITests.swift`의 `testSelectingTwoPointsShowsDistance`, `testRouteFailureShowsError` 두 UI 테스트가 실패
- 두 테스트 모두 동일한 패턴: `coursePlanner.map` 접근성 요소에 고정된 정규화 좌표로 두 번 탭한 뒤, 기대하는 텍스트("1.20" 거리 표시 또는 에러 메시지)의 `waitForExistence`가 끝내 `true`가 되지 않음
- 타임아웃을 5초 → 15초로 늘려도 여전히 실패(= 시간 문제가 아니라 탭이 애초에 지도에 도달하지 못하는 문제)
- 실패한 테스트의 접근성 트리를 열어보면 시트가 화면 하단이 아니라 y≈62-192, 즉 화면 상단 근처에 렌더링되어 있었고 앱 상태는 여전히 "완전 idle/무경로" 상태 — 탭이 지도에 아무 효과도 주지 못했음을 의미

## What Didn't Work

- **환경/동시성 지연 이론**: `xcodebuild test`의 병렬 테스트가 시뮬레이터 "Clone"들을 여러 개 띄우고, 앱에는 탭 분류에 실제로 ~0.35초 걸리는 `TapClassifier.window` 지연이 탭마다(총 2회) 존재하므로, 리소스 경합 시 5초 타임아웃을 넘길 수 있다고 추정했다. `TraceUITests.swift`의 두 단언 타임아웃을 5초→15초로 올렸다. → 결과: 여전히 실패, 이번엔 15초를 다 기다린 뒤 실패. 시간 문제가 아니었음을 확인시켜 줬을 뿐, 근본 원인은 그대로였다.
- **유닛 테스트 호스트 오염 이론**: `TraceTests`의 `TEST_HOST`가 `Trace.app` 자신임(`project.pbxproj`의 `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Trace.app/..."`으로 확인)을 근거로, `TraceApp.swift`의 `init()`이 `-traceUITesting` 런치 아규먼트만 보고 `.uiTesting()`(모킹된 안전 환경) vs `.live()`(실제 CoreLocation/MapKit/디스크 SwiftData)를 가르는데, 순수 유닛 테스트 호스트 실행에는 이 아규먼트가 없어 `.live()`로 빠질 수 있다고 의심했다. XCTest가 모든 테스트 호스트 프로세스에 설정하는 `XCTestConfigurationFilePath` 환경변수 체크를 추가해 유닛 테스트 호스트도 `.uiTesting()`으로 라우팅하도록 수정했다. 이 코드 경로가 실제로 실행되는지 확인하려고 임시 `NSLog`도 추가했으나, `xcrun simctl spawn log stream`/`log show`/`xcodebuild` 캡처 로그 어디에서도 해당 NSLog가 한 번도 나타나지 않았다 — 즉 이 가설은 확인조차 되지 않았고, UI 테스트 실패도 해결하지 못해 결국 되돌렸다.
- **시뮬레이터 인프라 문제와의 혼선**: 같은 디버깅 세션 중 시뮬레이터를 수십 번 재부팅/삭제/재설치하다가 실제로 OS 레벨에서 `Error Domain=FBSOpenApplicationErrorDomain Code=6 "Application failed preflight checks", BSErrorCodeDescription=Busy`가 발생했다. 이는 앱 코드와 무관한, 반복적인 부팅/종료/설치 사이클 자체가 원인인 실제 CoreSimulator/SpringBoard 이슈였다. `xcrun simctl shutdown all` + 같은 시뮬레이터 재부팅으로는 "Busy" 상태가 풀리지 않았고, `killall -9 com.apple.CoreSimulator.CoreSimulatorService`로 데몬 자체를 재시작해야 해결됐다. 이 인프라 이슈가 "결국 다 환경/플레이키니스 문제다"라는 잘못된 서사를 일시적으로 강화시켜, 실제 앱 버그 발견을 지연시켰다.

## Solution

`CoursePlannerPage+BottomSheetComponent.swift`의 `bottomSheet`에서 추가했던 두 줄을 제거한다.

```diff
 var bottomSheet: some View {
     VStack(alignment: .leading, spacing: 0) {
         grabberHandle
         sheetHeader
         if sheetDetent != .collapsed { expandedSheetBody }
     }
-    .frame(maxHeight: maxSheetHeight, alignment: .top)
-    .clipped()
     .background { /* rounded rect fill, ignoresSafeArea(.bottom), contentShape+onTapGesture{} 히트테스트 백스톱 */ }
     .accessibilityIdentifier("coursePlanner.segmentPanel")
 }
```

"full" 디텐트의 높이 상한은 이미 기존의 `expandedListHeight` 계산 프로퍼티(`expandedSheetBody` 내부 스크롤 리스트에서만 사용)가 안전하게 처리하고 있었다:

```swift
private var expandedListHeight: CGFloat {
    switch sheetDetent {
    case .collapsed: return 0
    case .medium: return panelMaxListHeight
    case .full:
        let maxListHeight = maxSheetHeight - grabberTotalHeight - sheetHeaderHeight
        return max(panelMaxListHeight, maxListHeight)
    }
}
```

이 내부 전용 캡은 그대로 두면 충분하며, `bottomSheet` 전체에 외부 클램프를 씌우는 것은 불필요할 뿐 아니라 안전하지도 않다.

검증: `xcodebuild test -project Trace.xcodeproj -scheme Trace -destination 'id=D887D0A4-074C-4AFB-8D08-D87329D0EFD4'` (raw bash, 고정 시뮬레이터 1개, 리포지토리 테스팅 규칙 준수) — 수정 직후 클린 실행에서 178/178 테스트 통과, 실패 0건.

## Why This Works

`ZStack` 안에서는 모든 자식 뷰에 부모(ZStack)가 이미 확정한 크기가 그대로 제안된다 — 여기서는 형제 뷰인 `mapView`가 `.ignoresSafeArea()`로 전체 화면 크기를 강제하고 있으므로, `bottomSheet`에도 전체 화면 크기가 제안된다.

`.frame(maxHeight: X, alignment: .top)`은 `idealHeight`나 정확한 `height` 지정이 없을 때, 부모가 자식의 실제 필요 크기보다 더 많은 공간(최대 `X`까지)을 제안하면 그 제안된 크기를 그대로 받아들여 자기 부모에게 "내 크기는 X"라고 보고한다. 그런 다음 실제(더 작은) 콘텐츠를 그 부풀려진 보이지 않는 박스 안에서 `.top`으로 정렬한다.

`ZStack(alignment: .bottom)`은 각 자식을 자신이 보고한 크기 기준으로 배치하므로, 이 부풀려진 박스 전체가 하단 정렬되고, 그 결과 진짜 작은 콘텐츠는 박스 안에서 `.top` 정렬되어 시각적으로 화면 상단 쪽으로 밀려 올라간다.

여기에 더해, 시트의 `.background { ... .contentShape(Rectangle()).onTapGesture {} }` 히트테스트 백스톱도 동일하게 부풀려진 프레임 크기에 맞춰지면서, 원래는 지도에 도달해야 할 탭을 화면의 거대한 보이지 않는 영역에서 조용히 가로채 버렸다. 두 줄을 제거하면 `bottomSheet`가 자신의 실제 콘텐츠 크기만 보고하게 되어 정상적으로 하단에 정렬되고, 히트테스트 영역도 실제 시트 크기로 줄어들어 지도 탭이 다시 지도에 도달한다.

## Prevention

- **UI 테스트가 "요소가 나타나지 않는다"는 형태로 실패하면, 타임아웃/동시성/환경 오염 같은 가설을 세우기 전에 먼저 `xcresult`에 자동 첨부된 접근성 트리부터 열어본다.** XCTest는 실패한 모든 `waitForExistence`/쿼리 단언에 대해 전체 접근성 트리("Debug description")를 별도 커스텀 계측 없이 이미 `.xcresult`에 자동 캡처해 두며, 다음 명령으로 바로 export할 수 있다:
  ```bash
  xcrun xcresulttool export attachments --path <xcresult-path> --output-path <dir>
  ```
  이번 세션에서도 결국 이 방법으로 "시트가 y≈62-192에 렌더링되고 앱은 여전히 idle 상태"라는 사실을 즉시 확인했고, 그 순간 바로 근본 원인(레이아웃 버그)이 드러났다. 반대로 타이밍/동시성/테스트 호스트 오염 가설은 며칠간 뒤쫓았지만 전부 헛수고였다. **UI 테스트 실패 조사의 기본 순서는 "먼저 접근성 트리를 본다 → 그다음에야 타이밍/환경을 의심한다"여야 한다.**
- `ZStack` 안에서 형제가 `.ignoresSafeArea()`로 전체 화면을 강제하는 상황이라면, 다른 자식에 `idealHeight`/정확한 `height` 없이 `.frame(maxHeight:)`만 씌우는 것을 경계한다 — 실제 콘텐츠보다 큰 "제안된 크기"를 그대로 보고해 정렬이 틀어질 수 있다. 높이 상한이 필요하면 그 상한을 실제로 소비하는 자식(예: 내부 스크롤 리스트)에 직접 거는 편이 안전하다.
- 시뮬레이터를 짧은 시간에 수십 번 boot/erase/install하는 세션에서 `FBSOpenApplicationErrorDomain Code=6 (Busy)`가 나오면, `simctl shutdown`/재부팅이 아니라 `killall -9 com.apple.CoreSimulator.CoreSimulatorService`로 데몬을 재시작한다. 이 증상이 나타났다고 해서 그 시점에 조사 중이던 앱 버그까지 "환경 문제"로 성급히 결론짓지 않는다 — 두 문제는 별개일 수 있다.

## Related Issues

- `docs/solutions/design-patterns/self-measuring-frame-causes-layout-jiggle.md` — 같은 컴포넌트(`CoursePlannerPage+BottomSheetComponent.swift`)에서 발생한 이전의 다른 프레임/레이아웃 버그(자기 콘텐츠를 측정해 자기 프레임에 되먹이는 순환). 메커니즘은 다르지만 이 문서가 도입한 `expandedListHeight` 고정값이 이번 버그의 해법이 기대는 바로 그 값이다 — "이 뷰 트리의 크기는 오직 안정적인 외부 값(`expandedListHeight`)으로만 결정한다"는 원칙이 두 버그 모두를 관통한다.
- `docs/solutions/workflow-issues/xcodebuildmcp-test-tool-parallel-hang.md` — "테스트 실패가 환경/시뮬레이터 문제처럼 보여도 성급히 결론짓지 말라"는 같은 정신을 공유하는 이전 교훈(다만 그쪽은 "어떤 커맨드로 테스트를 실행하느냐"가 핵심이고, 이 문서는 "실패 시 어떤 증거부터 확인하느냐"가 핵심이라 서로 다른 각도).
- `docs/solutions/ui-bugs/safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md` — 같은 `maxSheetHeight`/full 디텐트 영역에서 이후(2026-07-13) 발견된 별개의 버그. 이 문서의 "오버슈트 방어는 `expandedSheetBody` 내부에만" 교훈을 그대로 유지한 채, 계산에 쓰이는 입력값(top safe area)의 피드백 루프를 고쳤다.
- `docs/solutions/ui-bugs/firsttextbaseline-alignment-jiggle-with-mixed-child-types.md` — 같은 컴포넌트에서 이후 발견된, "레이아웃이 움찔거린다"는 증상의 진짜 원인(베이스라인 정렬). 이 문서가 다루는 문제와는 다르지만 진단에 쓴 실측 기법(개별 하위 뷰 높이를 하나씩 분리 측정)은 같은 계열이다.
- `docs/solutions/workflow-issues/child-accessibility-identifiers-collapse-to-parent-in-bottomsheet.md` — 이 컴포넌트의 bottomSheet 서브트리에서 자식 accessibilityIdentifier가 부모로 뭉개지는 별개의 발견. 향후 이 영역에 새 XCUITest를 작성할 때 참고.
