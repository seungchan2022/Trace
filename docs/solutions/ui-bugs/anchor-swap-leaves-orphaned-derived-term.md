---
title: "레이아웃 계산의 측정 앵커를 바꾸면서 그 앵커에서 파생된 항을 안 걷어내면, 경고 없이 같은 값을 두 번 빼게 된다"
date: 2026-07-21
category: ui-bugs
module: CoursePlannerPage
problem_type: ui_bug
component: rails_view
symptoms:
  - "풀 디텐트 바텀시트가 예전에는 topBar를 덮었는데 언젠가부터 topBar가 통째로 드러난다"
  - "크래시도 경고도 없고 테스트도 전부 통과한다 — 화면에서 높이만 조용히 줄어든다"
  - "'예전엔 됐는데 그 근처를 고친 뒤로 달라졌다'는 사용자 기억은 있으나, 회귀인지 원래 그랬는지 코드만 봐서는 구분이 안 된다"
root_cause: logic_error
resolution_type: code_fix
severity: medium
applies_when:
  - "레이아웃 계산의 기준 측정값(앵커)을 A에서 B로 교체할 때, A와 B가 안전영역·인셋 포함 여부가 다른 경우"
  - "그 계산식에 앵커에서 파생된 보정항(- safeAreaInset, - inset, + padding 등)이 함께 들어 있을 때"
tags: [swiftui, geometryreader, safeareainsets, bottom-sheet, regression, layout-math]
related_components: [CoursePlannerPage, SheetHeightBudget]
---

# 레이아웃 계산의 측정 앵커를 바꾸면서 그 앵커에서 파생된 항을 안 걷어내면, 경고 없이 같은 값을 두 번 빼게 된다

## 무슨 일이 있었나

바텀시트 높이 예산이 원래 이랬다:

```swift
maxSheetHeight = mapHeight - topSafeAreaInset - sheetTopMargin
```

`mapHeight`는 `.ignoresSafeArea(edges: .top)`이 걸린 지도의 높이라 **상단 안전영역을 포함**한다.
그래서 `- topSafeAreaInset`이 그 포함분을 정확히 상쇄해 결과는 `pageHeight - sheetTopMargin`이었다.

가로모드 오버플로를 잡으면서 앵커를 되먹임에 오염되지 않는 값으로 교체했다:

```swift
maxSheetHeight = pageHeight - topSafeAreaInset - sheetTopMargin
```

앵커 교체 자체는 옳았다(`mapHeight`는 실측에서 784↔812로 흔들렸고 `pageHeight`는 722로 고정).
**문제는 `- topSafeAreaInset`을 그대로 둔 것이다.** `pageHeight`는 GeometryReader가 보고하는
"부모가 제안한 크기"라 **안전영역이 이미 제외된 값**이다 — 상쇄할 포함분이 없는데 한 번 더 뺐다.

실측(iPhone 17 Pro): `pageHeight=722`, `safeAreaInsets.top=62`, `mapHeight=784(=722+62)`
→ 옛 결과 `711`, 새 결과 `649`. **정확히 62pt가 조용히 사라졌고** 그만큼 topBar가 드러났다.

## 왜 안 잡혔나

- 크래시·경고·테스트 실패가 **하나도** 없다. 화면의 숫자만 달라진다.
- 앵커 교체 커밋의 리뷰 초점은 "가로 오버플로가 막혔는가"였고, 세로에서 시트가 62pt 짧아진 것은
  같은 커밋의 부수 효과라 검토 범위 밖이었다.
- 남은 틈이 "원래 있던 여백이 드러난 것"인지 "새로 생긴 회귀"인지 코드만 봐서는 구분되지 않아,
  백로그에 "원인 미확인"으로 오래 남았다.

## 어떻게 찾았나

추론만으로 단정하지 않고 **임시 계측**을 넣어 런타임 값을 직접 찍었다:

```swift
let _ = print("[DIAG] proxyH=\(proxy.size.height) safeTop=\(proxy.safeAreaInsets.top) "
              + "pageHeight=\(pageHeight) mapHeight=\(mapHeight)")
```

한 줄 로그로 `mapHeight = pageHeight + safeTop`이 확인되는 순간 이중 차감이 확정됐다.
"사용자가 예전엔 됐다고 기억한다"는 것도 결정적 단서였다 — 회귀 쪽으로 범위를 좁혀줬다.

## 교훈

1. **앵커를 바꿀 때는 그 앵커에서 파생된 항을 전부 감사한다.** 특히 인셋·패딩 보정항은 앵커가
   그것을 포함하느냐 제외하느냐에 따라 의미가 정반대가 된다. 앵커만 갈아끼우면 보정항이
   고아가 되어 조용히 틀린다.
2. **"측정값이 인셋을 포함하는가"를 이름이나 느낌으로 판단하지 않는다.** `pageHeight`와
   `mapHeight`는 이름이 비슷하지만 62pt 차이가 났다. 한 줄 로그가 몇 시간의 추론보다 빠르다.
3. **조용히 틀리는 계산은 뷰 밖으로 빼서 테스트로 못박는다.** 이 예산 계산은 `SheetHeightBudget`
   (순수 enum)으로 분리하고 테스트를 붙였다 — `FabLayoutPolicy`와 같은 관례.
4. **"이 값 이하로 낮추지 말 것" 같은 경고 주석은 전제와 함께 적는다.** `sheetTopMargin`에
   붙어 있던 "11pt 미만 금지"는 근거(되먹임 흡수)가 사라진 뒤에도 남아 있었다. 근거를 함께
   적어두면 전제가 깨졌을 때 안전하게 풀 수 있다.

## 관련

- 앵커 교체의 원래 동기이자 이 문서의 전신: [`safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md`](safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md) (해결책 폐기됨)
- 결정 기록: `docs/agent-rules/project-decisions.md` (아이폰 세로 전용 고정)
