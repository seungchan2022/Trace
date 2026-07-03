---
title: "시뮬레이터로 재현 안 되는 실기기 전용 버그는 임시 print + 콘솔 로그로 조사"
date: 2026-07-03
category: workflow-issues
module: Debugging workflow
problem_type: workflow_issue
component: development_workflow
severity: medium
applies_when:
  - "사용자가 실기기 QA에서 '기능이 안 되는 것 같다'고 보고했는데, 코드 리뷰·유닛테스트로는 원인이 안 보일 때"
  - "시뮬레이터 제스처 자동화(XcodeBuildMCP 등)가 막혀 있어 에이전트가 직접 재현할 수 없을 때"
tags: [debugging, real-device, systematic-debugging, print-logging, overlap-offset]
---

# 시뮬레이터로 재현 안 되는 실기기 전용 버그는 임시 print + 콘솔 로그로 조사

## Context

MVP8 겹침 오프셋 기능을 실기기 QA에서 사용자가 "같은 경로 위에 겹치게 그려도 안 갈라져 보인다"고 보고했다. 유닛 테스트(`OverlapOffsetResolverTests`)는 전부 통과했고, 코드 리뷰(opus, 2회)도 알고리즘을 상세히 trace-through해서 문제를 못 찾았다. 시뮬레이터 지도 탭 제스처 자동화가 이 세션 내내 막혀 있어(`docs/solutions/workflow-issues/xcodebuildmcp-test-tool-parallel-hang.md`와 별개로, XcodeBuildMCP의 elementRef 탭이 지도의 커스텀 `UITapGestureRecognizer`에 안 닿음) 에이전트가 직접 재현할 방법이 없었다.

## Guidance

말로 재현 조건을 좁혀가는 것보다, **의심되는 지점에 임시 `print()`를 추가해 실기기에서 한 번 재현시키고 Xcode 콘솔 로그를 받는 쪽이 훨씬 빠르고 확실하다.**

1. 의심 지점(이 경우 `MapViewRepresentable.updateUIView`의 resolver 호출 직후)에 핵심 값만 찍는 `print()`를 추가한다 — 세그먼트 개수, 좌표 개수, 계산된 이동거리처럼 "이 값이 0이면 계산이 안 된 것, 0이 아니면 계산은 됐는데 다른 문제"를 즉시 가를 수 있는 값을 고른다.
2. 빌드만 하고 **커밋하지 않는다** (조사용 임시 코드).
3. 사용자에게 Xcode로 기기에 직접 실행해서 재현 후 콘솔 로그를 캡처해 달라고 요청한다.
4. 로그를 받으면 그 자리에서 가설을 확정/기각한다. 이번 경우:
   - 1차 로그: `maxDisplacementMeters=0.0`이 계속 나옴 → "계산이 항상 0"처럼 보였다.
   - 좌표 개수가 2개(직선)로 매우 적다는 걸 로그에서 발견 → "겹치는 긴 선"이 아니라 "가까운 끝점으로의 짧은 연결"이 만들어지고 있다는 실마리.
   - 사용자에게 "출발점까지 끝까지 되짚어 그리기"로 재시도를 요청 → 그리기 모드에서 `maxDisplacementMeters≈4.0`(정확히 설계값)이 나와 **기능 자체는 정상 동작**한다고 확정.
5. 원인이 확정되면 즉시 `print()`를 제거하고 `git diff`로 파일이 커밋 시점 상태로 완전히 돌아왔는지 확인한다(`git diff --stat` 결과가 비어있어야 함).

## Why This Matters

코드 리뷰만으로는 "실기기에서만 나타나는 런타임 동작"(제스처 인터랙션, 좌표 스냅, 라우팅 결과의 실제 형태)의 진위를 확정할 수 없다. 추측을 여러 번 반복하는 것보다, 핵심 값 하나를 로그로 뽑아 실기기에서 한 번 확인받는 게 시행착오 횟수를 크게 줄인다. 이번 경우 로그 없이 순수 대화로 조사했다면 "탭 자동 연결이 의도인지 버그인지"를 여러 턴 더 오갔을 것이다.

## When to Apply

- 실기기 QA 피드백이 "기능이 이상하다"처럼 애매하게 들어오고, 코드 리뷰로 원인이 안 잡힐 때
- 에이전트가 시뮬레이터에서 직접 재현할 수 없는 제스처/실기기 전용 동작일 때
- 사용자가 Xcode로 직접 기기를 실행할 수 있어 콘솔 로그를 받아올 수 있을 때

## Examples

- 이번 케이스: `OverlapOffsetResolver.displayCoordinates` 호출 직후 `print("[overlap-debug] seg\(index): coords=\(count) maxDisplacementMeters=\(maxDisp)")` 추가 → 좌표 개수와 이동거리로 "겹침 미감지"와 "온전한 겹침 구간이 애초에 안 만들어짐"을 구분.

## Related

- `docs/agent-rules/testing.md` — Real-Device Verification, QA 체크리스트 템플릿
- `docs/solutions/workflow-issues/xcodebuildmcp-test-tool-parallel-hang.md` — 같은 세션에서 나온 시뮬레이터 자동화 한계 관련 별도 이슈
