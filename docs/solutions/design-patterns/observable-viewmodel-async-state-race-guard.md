---
title: "@Observable ViewModel의 비동기 상태 갱신 레이스 가드 (generation 토큰)"
date: 2026-06-22
category: design-patterns
module: Pages/CoursePlannerPage
problem_type: design_pattern
component: service_object
severity: medium
applies_when:
  - "@Observable/@MainActor ViewModel이 await 후 발행(published) 상태를 변경할 때"
  - "사용자가 같은 비동기 작업을 빠르게 연속 트리거하거나 도중에 clear/cancel을 호출할 수 있을 때"
tags: [swift, swiftui, observable, concurrency, mainactor, race-condition, ios]
---

# @Observable ViewModel의 비동기 상태 갱신 레이스 가드 (generation 토큰)

## Context

`@MainActor @Observable` ViewModel에서 `await`(네트워크/라우팅 등) 뒤에 발행 상태를 바꾸는 메서드는, `@MainActor`라도 **재진입 레이스**에 노출된다. `await`는 메인 액터를 양보하므로 그 사이 같은 메서드가 다시 호출되거나 `clear()`가 끼어들 수 있다. 가드가 없으면:

- **늦게 끝난 호출이 이김(stale overwrite):** 빠르게 A→B를 트리거하면, 늦게 도착한 응답이 최종 상태를 덮어 입력과 결과가 어긋난다.
- **유령 상태(phantom):** `clear()`/취소로 상태를 비웠는데, 진행 중이던 호출이 뒤늦게 완료되며 비운 상태를 되살린다.
- **로딩 플래그 깜빡임:** 한 호출이 `isLoading = false`로 끄는 사이 다른 호출이 아직 진행 중.

## Guidance

await 전에 **단조 증가 generation 토큰**을 캡처하고, await 후에는 토큰이 여전히 최신일 때만 상태를 변경한다. 상태를 무효화하는 동작(`clear()`, 마지막 입력 제거 등)도 토큰을 증가시켜 진행 중 작업을 무효화한다.

```swift
private var recomputeGeneration = 0

private func recompute() async {
    recomputeGeneration += 1
    let generation = recomputeGeneration
    isLoading = true
    do {
        let result = try await service.work(...)
        guard generation == recomputeGeneration else { return } // superseded
        course = result
    } catch {
        guard generation == recomputeGeneration else { return }
        errorMessage = "..."
    }
    guard generation == recomputeGeneration else { return }
    isLoading = false
}

func clear() {
    recomputeGeneration += 1   // 진행 중 recompute 무효화 → 비운 상태 되살아남 방지
    course = nil
    errorMessage = nil
}
```

대안: 이전 `Task`를 보관했다가 `cancel()`하고 `Task.isCancelled`를 확인하는 방식. 토큰 방식이 더 가볍고 `@MainActor` 직렬성과 잘 맞는다.

## Why This Matters

`@MainActor`는 동시 실행은 막지만 `await` 경계의 **인터리빙**은 막지 못한다. 이 갭은 단위 테스트의 가짜(fake) 서비스가 즉시 반환하면 드러나지 않아, 사람이 빠르게 조작하거나 실제 네트워크 지연이 있을 때만 터진다. 영속 저장이 붙는 순간 `상태 ↔ 입력` 불일치가 저장 데이터를 오염시킨다.

## When to Apply

- ViewModel 메서드가 `await` 후 `@Published`/`@Observable` 프로퍼티를 변경한다
- 같은 작업이 빠르게 재트리거되거나, 진행 중에 초기화/취소가 가능하다

## Examples

결정적 테스트: 가짜 서비스를 `CheckedContinuation`으로 **게이트**해 두고, `appendStroke`를 자식 `Task`로 시작(라우팅에서 suspend) → `clear()` 호출 → 게이트 오픈 → 자식 완료를 기다린 뒤 `course == nil` 단언. 게이트 없이 즉시 반환하는 fake로는 이 레이스를 못 잡는다.

## Related

- 구현: `Trace/Pages/CoursePlannerPage/CoursePlannerPageViewModel.swift` (`recomputeSnappedCourse` 등)
- 스펙/플랜: `docs/superpowers/specs/2026-06-20-marker-draw-snap-mvp-design.md`
