---
module: MapViewRepresentable
tags: [UIKit, gesture-recognizer, MapKit, double-tap, require-to-fail]
problem_type: design-pattern
---

# `UITapGestureRecognizer.require(toFail:)`는 탭 위치를 구분하지 않는다

## 증상

한 화면 위에서 서로 다른 두 지점을 빠르게 잇달아 탭하는 정상 플로우(예: 탭 모드로 코스 두 지점을 순서대로 찍기)가, "더블탭과 싱글탭 충돌 방지"를 위해 추가한 `require(toFail:)` 관계 때문에 **둘 다 무시**돼 버렸다. 유닛/UI 테스트(서로 다른 두 좌표를 탭하는 기존 테스트)가 실패하면서 발견됨.

## 원인

`tapGR.require(toFail: doubleTapGR)` (또는 자체 만든 2탭 sentinel 인식기)는 "짧은 시간 안에 탭이 두 번 들어왔는가"만 판정하고, **두 탭이 같은 위치인지는 검사하지 않는다.** 그래서 서로 다른 화면 위치를 빠르게 순서대로 탭해도 "더블탭"으로 오인되어 `doubleTapGR`이 성공 판정되고, `require(toFail:)`로 묶인 싱글탭 인식기는 자동으로 실패 처리된다 — 두 탭 모두 콜백이 호출되지 않는다.

추가로: MapKit 내장 더블탭-줌 인식기를 `mapView.gestureRecognizers`에서 찾아서 거는 방식도 별개로 실패했다 — `makeUIView` 시점(뷰가 아직 화면 계층에 안 붙은 시점)엔 MapKit이 그 내장 인식기를 등록 안 해놨을 가능성이 높다.

## 해결

제스처 인식기 레벨의 `require(toFail:)`를 쓰지 말고, **직접 만든 탭 핸들러 안에서 시간+거리를 함께 검사**한다:

```swift
private var lastTapTime: Date?
private var lastTapPoint: CGPoint?

@objc func handleTap(_ recognizer: UITapGestureRecognizer) {
    let point = recognizer.location(in: mapView)
    if let lastTime = lastTapTime, let lastPoint = lastTapPoint,
       Date().timeIntervalSince(lastTime) < 0.35,
       hypot(point.x - lastPoint.x, point.y - lastPoint.y) < 40 {
        lastTapTime = nil
        lastTapPoint = nil
        return  // 같은 자리 + 짧은 시간 → 더블탭의 두 번째 탭으로 간주, 무시
    }
    lastTapTime = Date()
    lastTapPoint = point
    // ... 정상 처리
}
```

시간 조건만으로는 위치가 다른 정상적인 연속 탭까지 잡아먹으므로, **반드시 거리 조건을 함께** 걸어야 한다.

## 언제 적용하나

- 같은 뷰 위에 "네이티브 더블탭 제스처(줌 등)"와 "우리 앱의 싱글탭 핸들러"가 공존해야 할 때
- `require(toFail:)`로 해결하려다 서로 다른 위치의 정상 연속 탭까지 깨지는 회귀가 보일 때

## 관련

- `Trace/Pages/CoursePlannerPage/MapViewRepresentable.swift`의 `Coordinator.handleTap`
- MVP9 edit-consistency 실기기 QA에서 발견 (2026-07-04)
