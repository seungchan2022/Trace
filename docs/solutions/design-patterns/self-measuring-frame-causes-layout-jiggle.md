---
module: CoursePlannerPage
tags: [SwiftUI, onGeometryChange, layout, ScrollView, feedback-loop, animation]
problem_type: design-pattern
---

# 자기 콘텐츠 크기를 측정해 자기 프레임에 되먹이면 레이아웃이 잠깐 움찔거린다

## 증상

바텀시트 구간 리스트에서 구간을 선택하거나 콘텐츠가 살짝 바뀔 때마다, 시트(또는 그 안의
스크롤 영역)의 레이아웃이 아주 짧게 움직였다가 원래 자리로 돌아오는 현상이 있었다
(2026-07-12, 사용자 관찰 — "레이아웃이 약간씩 움직였다가 돌아오고"). 재현이 산발적이고
정확히 어떤 상호작용에서 발생하는지 특정하기 어려웠다.

또한 별개로, 구간을 추가할수록 시트 자체가 점점 커지는 문제도 같은 코드에서 함께 있었다.

## 원인 — 측정→적용→재측정 순환

```swift
ScrollView {
    LazyVStack { ... }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            panelContentHeight = height   // ① 콘텐츠의 "자연 크기"를 측정
        }
}
.frame(height: min(panelContentHeight, cap))   // ② 그 측정값으로 같은 뷰의 프레임을 다시 결정
```

이 패턴은 자기 자신을 측정해서 자기 자신의 크기 제약으로 되먹인다:

1. `LazyVStack`이 제약 없이 자연 크기로 렌더된다.
2. 그 높이를 측정해 `panelContentHeight`에 저장한다.
3. 그 값으로 감싸는 `ScrollView`의 프레임을 다시 정한다.
4. 프레임이 바뀌면 SwiftUI가 다시 레이아웃하고, 내부 콘텐츠(스크롤 인디케이터 여백, 줄바꿈
   등)가 미세하게 달라질 수 있어 ①이 다시 트리거될 여지가 생긴다.

콘텐츠가 조금이라도 바뀌는 상호작용(행 선택, 텍스트 폭 변화 등) 이후 이 순환이 한두 프레임
다시 돌면, 사용자 눈에는 "잠깐 움찔거렸다 돌아온다"로 보인다. 콘텐츠 양에 따라 매번 최종
높이도 달라지므로("추가할 때마다 커진다") 두 증상은 사실 같은 원인의 다른 표현이었다.

## 해법 — 크기를 콘텐츠가 아니라 외부 상태로 결정한다

레이아웃 안정성이 콘텐츠에 딱 맞추는 것보다 중요하면, 그 뷰의 크기를 **자기 콘텐츠가 아닌
외부의 안정적인 값**(고정값, 화면 비율, 또는 자주 바뀌지 않는 별도 소스)으로만 결정한다.

```swift
.frame(height: cap)   // 콘텐츠 실측과 무관한 고정값 — presentationDetents와 동일한 발상
```

콘텐츠가 짧으면 빈 공간이 남고, 길면 스크롤된다 — 둘 다 정상이고 예측 가능하다. `cap` 자체는
**다른 안정적인 소스**(예: 지도 뷰의 측정 높이처럼 이 상호작용 중에는 거의 안 바뀌는 값)에서
와도 된다; 문제는 "자기 자신을 측정해 자기 자신에 되먹이는" 순환이지, 측정 자체가 아니다.

## 일반화한 규칙

> **한 뷰의 프레임 크기를, 그 뷰(또는 그 자식)를 측정한 값으로 정하지 않는다.** 크기를
> 안정적으로 유지해야 하는 뷰는 외부의 안정적인 소스(고정값, 화면/부모 비율, 자주 안 바뀌는
> 형제 뷰의 측정값)로만 프레임을 정한다. `onGeometryChange`/`GeometryReader`로 무언가를
> 측정했다면, 그 결과를 **같은 렌더 패스에서 측정 대상 자신의 프레임에** 다시 쓰지 않는지
> 항상 확인한다.

체크리스트:
- [ ] 이 뷰의 `.frame(...)`이 참조하는 `@State`가, 바로 그 `.frame`이 감싸는 서브트리에서
      `onGeometryChange`/`GeometryReader`로 측정된 값인가? → 그렇다면 순환 후보.
- [ ] 콘텐츠가 바뀌면(행 추가/제거/선택/텍스트 폭 변화) 이 프레임도 따라 바뀌어야 하는가?
      아니라면 측정값 대신 고정값/외부값을 쓴다.
- [ ] "잠깐 움찔거렸다 돌아온다"는 버그 리포트를 받으면, 먼저 그 뷰 트리에 이 패턴이 있는지
      찾는다 — 애니메이션 타이밍보다 이 구조적 원인일 확률이 높다.

## 관련

- 실제 수정: `Trace/Pages/CoursePlannerPage/UIComponent/CoursePlannerPage+BottomSheetComponent.swift`
  (`expandedSheetBody`) — `panelContentHeight` 측정·`min()` 결합 제거, `expandedListHeight`
  고정값만 사용 (2026-07-12).
- 결정 기록: `docs/agent-rules/project-decisions.md`
