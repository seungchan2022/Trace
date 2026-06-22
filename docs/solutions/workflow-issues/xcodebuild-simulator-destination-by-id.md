---
title: "xcodebuild 시뮬레이터 destination은 name 대신 id(udid)로 지정"
date: 2026-06-22
category: workflow-issues
module: Build/Test workflow
problem_type: workflow_issue
component: development_workflow
severity: low
applies_when:
  - "xcodebuild build/test에 -destination을 지정할 때"
  - "\"platform=iOS Simulator,name=iPhone NN\" 형태가 destination 해석 실패로 빌드/테스트가 멈출 때"
tags: [xcodebuild, simulator, destination, ios, build, testing]
---

# xcodebuild 시뮬레이터 destination은 name 대신 id(udid)로 지정

## Context

`xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 16' test` 가 간헐적으로 destination 해석에 실패하며 멈췄다. 같은 머신에 동일/유사 이름의 시뮬레이터가 여럿 있거나 stale/placeholder destination(예: 과거 visionOS 항목)이 남아 있으면, `name=` 매칭이 모호해지거나 엉뚱한 항목으로 해석된다.

## Guidance

빌드/테스트 destination은 **이름이 아니라 udid로** 지정한다.

```bash
# 1) 가용 시뮬레이터 udid 확인
xcrun simctl list devices available | grep "iPhone 16"
#   예: iPhone 16 (A826F6E1-E5B4-46E7-976F-78895A2E0A62) (Shutdown)

# 2) id=로 지정 (name= 대신)
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination 'platform=iOS Simulator,id=A826F6E1-E5B4-46E7-976F-78895A2E0A62' test
```

`project-decisions.md`/`testing.md`가 기준 시뮬레이터(iPhone 17/iOS 26.5 등)를 명시하더라도, 그게 머신에 없으면 가용 udid로 폴백하는 게 규칙이다. 프로젝트·스킴 인자는 그대로 둔다.

## Why This Matters

`name=` 모호성으로 인한 실패는 코드와 무관한데도 빌드/테스트 사이클을 통째로 막아 시간을 잡아먹는다. udid는 정확히 하나의 기기를 가리키므로 해석이 결정적이다. CI/자동화·서브에이전트 작업에서 특히 중요(반복 실패의 원인).

## When to Apply

- 로컬/자동화에서 시뮬레이터 대상 `xcodebuild` 명령을 작성할 때
- `name=` destination이 "Unable to find a destination" / 해석 실패로 멈출 때

## Examples

- 실패: `-destination 'platform=iOS Simulator,name=iPhone 16'` → destination 해석 실패
- 성공: `-destination 'platform=iOS Simulator,id=<udid>'` (위 simctl로 확보한 udid)

## Related

- 검증 명령: `docs/agent-rules/testing.md` (Real-Device Verification / 검증 절차)
- 플랜의 검증·커밋 프로토콜: `docs/superpowers/plans/2026-06-20-marker-draw-snap-mvp.md`
