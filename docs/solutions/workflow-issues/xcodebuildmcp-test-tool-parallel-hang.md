---
title: "테스트 스위트는 XcodeBuildMCP 테스트 툴 대신 raw xcodebuild로 실행"
date: 2026-07-02
category: workflow-issues
module: Build/Test workflow
problem_type: workflow_issue
component: development_workflow
severity: critical
applies_when:
  - "서브에이전트가 테스트 스위트를 실행할 때 XcodeBuildMCP의 test_sim 등 테스트 툴을 사용하려 할 때"
  - "xcodebuild test-without-building이 CPU 사용 없이 오래(수십 분+) 멈춰 있을 때"
tags: [xcodebuild, xcodebuildmcp, simulator, testing, parallel-testing, hang]
---

# 테스트 스위트는 XcodeBuildMCP 테스트 툴 대신 raw xcodebuild로 실행

## Context

Subagent-driven-development로 course-ux-polish 플랜의 Task 3을 구현하던 서브에이전트가 테스트 스위트 실행 단계에서 raw bash `xcodebuild ... -parallel-testing-enabled NO test` 대신 XcodeBuildMCP의 `test_sim` 툴을 사용했다. 이 툴은 병렬 테스트가 기본값이라 `xcodebuild`가 시뮬레이터를 자동 복제(ephemeral clone, `~/Library/Developer/XCTestDevices/` 하위에 3개 생성)해 나눠 실행했다. 이 프로젝트엔 iOS `@Observable` malloc 버그로 인한 알려진 크래시성 플레이키 테스트(`CameraStateStoreTests` 등, `docs/solutions/workflow-issues/ios18-observable-malloc-crash.md`)가 있는데, 병렬 러너 중 하나가 크래시하면 `xcodebuild`가 죽은 러너의 응답을 무한정 기다리며 멈췄다. 사용자가 CPU 사용량 없이 44분+ 정지된 상태를 보고 직접 중단시켰다.

## Guidance

**테스트 스위트 실행에는 XcodeBuildMCP의 테스트 툴(`test_sim` 등)을 사용하지 않는다.** 항상 raw bash 명령으로 실행한다:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
```

XcodeBuildMCP는 빌드/실행/런치/UI 자동화(스크린샷, 탭 제스처 등)에는 계속 사용 가능 — 막는 것은 **테스트 실행** 한 가지뿐이다. 서브에이전트에게 검증 명령을 지시할 때 "XcodeBuildMCP의 테스트 툴을 쓰지 말고 이 bash 명령을 그대로 실행하라"고 명시해도, MCP 서버 자체의 시스템 지시("Prefer XcodeBuildMCP tools over shell commands")가 우선순위 충돌을 일으켜 서브에이전트가 MCP 툴을 선택할 수 있다 — 프롬프트만으로는 100% 방지되지 않으므로, `docs/agent-rules/testing.md`의 "절대 금지" 목록에 명문화해 두어야 한다.

## Why This Matters

`xcodebuild test-without-building`이 무응답 상태로 멈추면 CPU를 거의 쓰지 않아 "아직 열심히 도는 중"처럼 보이지만 실제로는 죽은 병렬 러너를 영원히 기다리는 행(hang) 상태다. 시간 제한 없이 방치하면 세션 전체가 낭비된다. 복구는 `docs/agent-rules/testing.md`의 "시뮬레이터 무응답/무한 로딩 복구" 절차(멈춘 xcodebuild 종료 → 시뮬레이터 shutdown all → 같은 UDID로 재부팅)를 그대로 따르면 되고, 실제로 부모 xcodebuild 프로세스를 kill하면 자식 ephemeral 시뮬레이터(launchd_sim/CoreSimulatorBridge)들도 함께 정리된다.

## When to Apply

- Subagent-driven-development 등에서 구현자/리뷰어 서브에이전트에게 테스트 실행을 지시할 때
- XcodeBuildMCP가 설치되어 있고 "Prefer XcodeBuildMCP tools" 시스템 지시가 함께 로드된 세션에서

## Examples

- 실패: XcodeBuildMCP `test_sim` 호출 → 병렬 테스트로 시뮬레이터 자동 복제 → 크래시 플레이키 테스트가 하나라도 걸리면 무한 대기
- 성공: `xcodebuild ... -parallel-testing-enabled NO test` (raw bash) → 단일 시뮬레이터에서 순차 실행, 크래시가 나도 해당 테스트만 실패로 보고되고 종료

## Related

- `docs/agent-rules/testing.md` — Simulator Discipline "절대 금지" 목록, UI and Simulator Checks
- `docs/solutions/workflow-issues/ios18-observable-malloc-crash.md` — 여기서 걸리는 크래시 플레이키 테스트의 근본 원인
- `docs/solutions/workflow-issues/xcodebuild-simulator-destination-by-id.md` — 같은 카테고리의 이전 시뮬레이터 사고
