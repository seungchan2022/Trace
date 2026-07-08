---
module: CoursePlannerPage
tags: [SwiftUI, keyboard-avoidance, ignoresSafeArea, UIViewRepresentable, MapKit, alert, TextField]
problem_type: design-pattern
---

# SwiftUI keyboard avoidance는 알럿의 키보드에도 반응해 UIViewRepresentable 프레임을 줄인다

## 증상

`.alert { TextField(...) }`로 띄운 저장 알럿에 이름을 입력하는 동안, 알럿 뒤의 지도
(`MKMapView`를 감싼 `MapViewRepresentable`)가 순간적으로 줌아웃됐다가 알럿이 닫히면
원래대로 돌아왔다 (2026-07-08, MVP11 실기기 QA 시나리오 3).

## 원인

키보드가 뜨면 SwiftUI의 **자동 keyboard avoidance**가 `.keyboard` safe area 리전을
추가한다. 이 리전을 무시하는 뷰가 없으면 레이아웃 가용 높이가 키보드만큼 줄어
representable의 프레임이 축소된다(실측: bounds 높이 576→275). MKMapView는 프레임이
바뀌면 `region.span`을 자체 재계산하고, 그 값이 `mapViewDidChangeVisibleRegion` →
`@Binding region` writeback으로 SwiftUI 상태에 반영돼 줌 레벨이 사라진다.

두 가지가 직관과 어긋난다:

1. **알럿(UIAlertController)의 TextField가 띄운 키보드에도 배경 SwiftUI 뷰가 반응한다.**
   키보드 알림은 전역이라, 포커스가 알럿에 있어도 뒤에 깔린 페이지가 keyboard avoidance를
   수행한다.
2. 프레임 축소 **이후**를 수습하는 모든 시도(writeback 차단 플래그, `setRegion` 보정,
   async 지연)는 증상 패치다 — 이 버그에서 4차례 전부 실패했고, 패치가 패치를 낳았다.

## 해법

`.ignoresSafeArea(.keyboard)`를 페이지 body 수정자 체인의 **가장 바깥**에 적용한다.

```swift
var body: some View {
    mapView
        .safeAreaInset(edge: .top) { controls }
        .safeAreaInset(edge: .bottom) { statusPanel }
        .alert(...) { TextField(...) ... }
        .ignoresSafeArea(.keyboard)   // ← 체인 마지막 = 가장 바깥
}
```

**위치가 핵심이다.** 수정자는 바깥에서 안으로 레이아웃되므로, `.ignoresSafeArea(.keyboard)`가
`safeAreaInset`보다 바깥에 있어야 keyboard 리전이 인셋 레이아웃 계산에 들어가기 전에
제거된다. 안쪽(예: `mapView` 자체)에 적용하면 바깥 인셋 레이아웃이 이미 줄어든 뒤라 효과가
없다 — 이전 세션에서 같은 수정자가 "효과 없음"으로 폐기된 원인이 적용 계층이었을 가능성이 높다.
"같은 수정자를 시도했는데 안 됐다"는 기록이 있어도, **어느 계층에 적용했는지**가 함께
기록돼 있지 않으면 기각된 가설로 취급하지 말 것.

인라인 텍스트 입력이 있는 화면이라면 이 수정이 키보드 회피를 통째로 끄므로 부적합할 수
있다 — 이 페이지는 키보드가 알럿에서만 뜨므로 전면 차단이 정답이었다.

## 시뮬레이터 재현 기법 (부산물)

- 지도 탭 자동화가 막혀 있어도(elementRef 필수), **런치 인자 임시 스캐폴딩**으로 알럿을
  자동 표시하면 "알럿+키보드"만 분리한 최소 재현이 된다(조사용 임시 코드 — 커밋 금지 컨벤션은
  `workflow-issues/live-only-bug-temp-print-debugging.md`).
- 시뮬레이터에서 소프트웨어 키보드가 안 뜨면 keyboard avoidance 자체가 발동하지 않는다.
  Simulator 메뉴 **I/O > Keyboard > Toggle Software Keyboard**를 켜야 재현된다
  (osascript로 메뉴 클릭 가능; ⌘⇧K keystroke 전송은 기기로 문자가 입력돼 버림).
- 검증은 증상(줌아웃)이 아니라 **원인(bounds 불변)**을 관측한다: 키보드가 화면에 떠 있는
  스크린샷 + bounds 로그 불변이 함께 있어야 "고쳐졌다"고 말할 수 있다.

## 관련

- 플랜(재현·검증 로그 상세): `docs/superpowers/plans/2026-07-08-map-zoom-during-alert-bugfix.md`
- 임시 print 조사 컨벤션: `docs/solutions/workflow-issues/live-only-bug-temp-print-debugging.md`
- 세션 리셋 판단 기준(이 버그의 전사): `docs/solutions/workflow-issues/session-reset-after-repeated-fix-failures.md`
