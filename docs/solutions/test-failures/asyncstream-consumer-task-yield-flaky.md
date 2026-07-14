---
title: "AsyncStream 소비 Task 대기에 Task.yield() 사용 시 플레이키"
date: 2026-07-13
category: test-failures
module: TraceTests/RunSessionTests
problem_type: test_failure
component: testing_framework
symptoms:
  - "AsyncStream을 소비하는 백그라운드 Task가 yield를 처리했다고 가정하고 곧바로 상태를 단언(assert)하는 테스트가 간헐적으로 실패함"
  - "동일 테스트 스위트를 반복 실행하면 11개 중 최대 8개까지 실패 횟수가 들쭉날쭉함(같은 코드, 같은 머신에서 재현)"
root_cause: async_timing
resolution_type: test_fix
severity: medium
tags: [swift, asyncstream, concurrency, mainactor, xctest, flaky-test, task-yield]
---

# AsyncStream 소비 Task 대기에 Task.yield() 사용 시 플레이키

## Problem

`@MainActor` 컨텍스트에서 `Task { for await sample in stream { ... } }`로 만든 소비 Task는, 생성 즉시 스케줄되어 실행된다는 보장이 없다. 테스트가 `stream.yield(...)` 직후 `await Task.yield()`를 몇 번 호출해 "그 사이 소비 Task가 처리했을 것"이라 가정하고 바로 상태를 확인하면, 실제로 소비 Task가 아직 한 번도 스케줄되지 않은 채로 단언이 실행되어 간헐적으로 실패한다.

## Symptoms

- `RunSessionTests`(MVP13 run-tracking Task 2)에서 `drain()` 헬퍼를 `await Task.yield(); await Task.yield(); await Task.yield()`로 구현했더니, 로컬에서 반복 실행 시 11개 테스트 중 최대 8개가 실패했다(항상 같은 테스트가 실패하는 것도 아니어서 재현이 들쭉날쭉했다).
- 실패한 단언은 전부 "방금 yield한 샘플이 세션 상태에 반영됐는지" 확인하는 것들 — 예: `session.state == .tracking`, `session.track.samples.count == 1`.

## What Didn't Work

- `Task.yield()` 호출 횟수를 3번으로 고정: 스케줄러가 다른 작업으로 바빠서 3번 양보로는 소비 Task 차례가 안 오는 경우가 실측으로 존재했다.
- (참고, 이번 세션에서 직접 시도하진 않았지만 흔한 오해) `Task.yield()`를 늘리기만 하면 해결될 거라는 가정 — 구현자가 yield 횟수를 늘려도(예: 50회) 증상이 재현됨을 확인해, "몇 번 양보하냐"가 근본 원인이 아님을 확인했다.

## Solution

`Task.yield()` 반복 대신 짧은 wall-clock 대기(`Task.sleep`)로 바꿨다:

```swift
/// AsyncStream 소비 태스크가 yield를 처리할 틈을 준다
private func drain() async {
    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
}
```

`RunSessionTests` 11개 테스트를 반복 실행(8회 이상)해 안정적으로 통과함을 확인했다.

## Why This Works

`Task.yield()`는 "현재 Task가 실행을 양보한다"는 뜻일 뿐, 스케줄러가 특정 다른 Task를 그 사이에 반드시 실행시켜준다는 보장이 없다 — 몇 번 양보해야 목표 Task 차례가 오는지는 스케줄러 부하에 따라 달라진다. 반면 `Task.sleep`은 실제로 스레드를 일정 시간 양보하므로, 그 사이 소비 Task가 실행될 기회가 훨씬 안정적으로 주어진다. `@MainActor` 격리 하에서 소비 Task는 한 번 스케줄되면 다음 suspension point(다음 `for await`의 대기)까지 동기적으로 상태를 갱신하므로, "스케줄됐는지"만 보장되면 상태 갱신 자체는 확정적이다.

## Prevention

- AsyncStream(또는 그 외 백그라운드 Task)을 소비하는 코드를 테스트할 때, "소비 Task가 실행될 시간을 준다"는 목적이면 `Task.yield()` 반복보다 짧은 `Task.sleep`(수십 ms)을 우선 고려한다.
- 더 견고한 대안(이번 태스크 스코프에서는 과했다고 판단해 채택하지 않음, 향후 테스트가 더 많아지면 고려): 폴링 방식으로 "조건이 참이 될 때까지 짧게 반복 대기 + 타임아웃"을 두는 헬퍼. wall-clock 슬립보다 CI 부하 변동에 더 안전하다.
- 이런 타이밍 문제가 있는 테스트는 반드시 여러 번 반복 실행해 안정성을 확인한 뒤 커밋한다(1회 통과는 증거가 아니다).

## Related Issues

- 구현: `Trace/Application/RunTracking/RunSession.swift`(`start()`의 `streamTask` 소비 루프), 테스트: `TraceTests/RunSessionTests.swift`(`drain()`)
- 플랜: `docs/superpowers/plans/2026-07-13-run-tracking.md` (Task 2)
- 관련이지만 다른 문제: [`observable-viewmodel-async-state-race-guard.md`](../design-patterns/observable-viewmodel-async-state-race-guard.md) — 그쪽은 프로덕션 코드의 재진입 레이스 가드(generation 토큰), 이 문서는 테스트 타이밍 문제로 서로 다른 스코프.
