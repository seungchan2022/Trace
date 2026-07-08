---
title: "반복 실패한 버그 수정 — '몇 번 실패했나'가 아니라 '같은 층위를 맴도는가'로 세션 리셋을 판단"
date: 2026-07-08
category: workflow-issues
module: Debugging workflow
problem_type: workflow_issue
component: development_workflow
severity: medium
applies_when:
  - "같은 버그를 한 세션 안에서 여러 차례(3회 이상) 수정 시도했는데 핵심 증상이 남아있을 때"
  - "다음 수정이 이전 시도들과 같은 함수/같은 메커니즘을 다시 건드리려 할 때"
  - "사용자가 '세션이 오염된 것 같다'며 새 세션 전환을 제안할 때"
tags: [debugging, systematic-debugging, session-management, root-cause]
---

# 반복 실패한 버그 수정 — '몇 번 실패했나'가 아니라 '같은 층위를 맴도는가'로 세션 리셋을 판단

## Context

MVP11 QA에서 발견된 지도 줌아웃 버그(저장 알럿에서 이름 입력 중 지도가 순간 줌아웃)를 한 세션에서
4차례 수정 시도했다. 매번 사용자 실기기 검증 후 다음 시도로 넘어갔는데, 4번째 시도에서도 핵심 증상이
남았다. 사용자가 "한 세션에서 같은 버그를 2~3차례 시도해도 안 되면 이미 세션이 오염돼서 새 세션이
낫다"는 통념을 전제로 판단을 요청했다. 상세: `docs/superpowers/plans/2026-07-08-map-zoom-during-alert-bugfix.md`.

## Guidance

"N번 실패하면 리셋"이라는 고정 횟수 규칙은 정확하지 않다. 진짜 판단 기준은:

**매 시도가 새 증거로 새 가설을 세우고 있는가, 아니면 비슷한 층위를 맴돌고 있는가.**

- **새 증거 → 새 가설(수렴)의 예:** 이번 세션 초반엔 "리사이즈가 실제로 일어난다"는 사실 자체를
  몰랐다가, 실기기 로그로 지도 뷰의 bounds 크기 변화(572.67 ↔ 298.67)를 확인(증거)하고 나서야
  "MapKit이 리사이즈에 반응해 region을 자체 재계산한다"는 새 가설을 세울 수 있었다. 이 구간은
  실제로 원인에 가까워지고 있었다.
- **맴도는 예(4차 시도가 걸린 구간):** 시도 2~4는 전부 "리사이즈가 일어난 뒤 그 값을 SwiftUI 상태에
  어떻게 반영할지"(동기 보정 → async 지연 → writeback 차단)만 바꿨다. 되짚어보면 시도 3의 async
  지연조차 근본 수정이 아니라 시도 2 자신이 만든 부작용(동기 `setRegion` 호출로 인한 "Modifying
  state during view update" 경고)을 수습한 것이었다 — **패치가 패치를 낳는 패턴.** "왜 프레임 자체가
  리사이즈되는가"라는 원래 질문은 시도 1(`ignoresSafeArea`, 검증 없이 폐기) 이후 한 번도 다시
  세워지지 않았다.

이 구분이 실무적으로 중요한 이유: 실패한 시도들이 대화 맥락에 쌓이면, 다음 가설이 은근히 이전
시도들의 틀에 anchoring된다(이 경우 "state propagation을 어떻게 다룰지"라는 틀). 새 세션은 이
anchoring 없이 원래 질문으로 곧장 돌아갈 수 있다는 게 리셋의 진짜 가치다 — "세션이 더러워져서"가
아니라 **"다음 세션이 이미 실패한 층위를 다시 밟지 않게" 하기 위해서다.**

## Why This Matters

superpowers `systematic-debugging` 스킬의 "3회 이상 실패 시 아키텍처를 재검토하라"는 규칙과 방향은
같지만, 트리거는 횟수 자체가 아니라 **매 시도가 실제로 이전 시도보다 원인에 더 가까워지고 있는지**여야
한다. 횟수만 세면 두 방향으로 틀릴 수 있다: 실제로는 수렴 중인 조사를 조기에 리셋해버리거나, 반대로
완전히 맴도는데도 "아직 3번 안 됐으니"라며 같은 층위를 계속 패치하게 된다.

리셋을 선택했다면, 리셋의 성공 여부는 전부 **인수인계 문서에 무엇을 남기느냐**에 달려있다. 최소한
다음을 명시해야 한다: (1) 확정된 근본 메커니즘(재조사 불필요한 부분과 그렇지 않은 부분을 구분),
(2) 실패한 시도들과 왜 실패로 판정하는지(어떤 층위를 맴돌았는지), (3) 다음 세션이 재시도하면 안 되는
것, (4) 다음 세션이 실제로 물어야 할 질문(이전 세션이 아직 안 던진 질문).

## When to Apply

- 같은 버그에 여러 차례 수정을 시도했고, 다음 시도를 이전 시도와 같은 함수/메커니즘에 대해 하려고 할 때
- 세션을 리셋할지 판단할 때 — 리셋 여부보다 인수인계 문서의 내용이 다음 세션의 성패를 가른다

## Examples

- 이번 사례: `docs/superpowers/plans/2026-07-08-map-zoom-during-alert-bugfix.md`가 실제 인수인계
  문서다. "확정된 근본 메커니즘"과 "다음 세션이 물어야 할 질문"을 분리해서 적어, 다음 세션이 시도
  1~4를 반복하지 않고 곧장 레이아웃 층위 재조사부터 시작하도록 했다.

## Related

- `docs/superpowers/plans/2026-07-08-map-zoom-during-alert-bugfix.md` — 이 사례의 실제 인수인계 문서
- superpowers `systematic-debugging` 스킬 — Phase 4 "3+ Fixes Failed: Question Architecture"
- `docs/solutions/workflow-issues/live-only-bug-temp-print-debugging.md` — 실기기 전용 버그 조사 컨벤션
