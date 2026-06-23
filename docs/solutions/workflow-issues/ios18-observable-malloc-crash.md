---
module: testing
tags: [simulator, Observable, malloc, crash, iOS18]
problem_type: bug
---

# iOS 18.x @Observable malloc crash in unit tests

## 증상

`@Observable` ViewModel을 사용하는 XCTest가 실행 중 크래시:
```
malloc: *** error for object 0x25237aac0: pointer being freed was not allocated
```
- 항상 같은 주소 `0x25237aac0`
- xcodebuild가 `Restarting after unexpected exit, crash, or test timeout` 반복
- 시뮬레이터에서 "Trace 응용 프로그램이 예기치 않게 종료되었습니다" 리포트 연속 발생
- Exception Type: EXC_CRASH (SIGABRT)

## 원인

**확인된 Swift 런타임 버그** (`libswift_Concurrency.dylib`). `@MainActor` 클래스가 동기 XCTest에서 해제될 때 `swift_task_deinitOnExecutorImpl()`이 task-local 저장소 정리 과정에서 힙에 할당되지 않은 정적 메모리를 `free()` 호출 → double-free. `@Observable` 매크로가 내부 관찰 추적 코드를 합성하면서 이 경로를 더 쉽게 트리거.

관련 이슈:
- [swiftlang/swift#87316](https://github.com/swiftlang/swift/issues/87316)
- [swiftlang/swift#85663](https://github.com/swiftlang/swift/issues/85663)
- [Swift Forums: "pointer being freed was not allocated, unless I have an empty deinit"](https://forums.swift.org/t/pointer-being-freed-was-not-allocated-unless-i-have-an-empty-deinit/84034)

## 해결

- **현재:** iOS 26+ 런타임 시뮬레이터 사용. 동일 코드가 iOS 26.5에서 크래시 없이 통과 확인 (2026-06-23).
- **iOS 18.x에서도 테스트해야 할 경우:** ViewModel에 `nonisolated deinit { }` 추가 — 컴파일러가 isolated deinit을 합성하는 걸 방지하여 버그 경로 우회.

## 추가 발견 (같은 세션)

1. **`-parallel-testing-enabled NO` 필수** — 없으면 xcodebuild가 시뮬레이터를 자동 복제(clone)해 병렬 테스트 실행 → 복제 시뮬레이터에서 앱 런칭 실패 (`FBSOpenApplicationServiceErrorDomain Code=1`).
2. **블로킹 Stub 분리** — `CheckedContinuation` 기반 블로킹 stub이 모든 테스트에서 사용되면, `snappedRoute` 기본 구현이 `route()`를 호출할 때 영원히 블로킹 → 테스트 타임아웃/크래시. 블로킹 stub은 레이스 컨디션 테스트 전용 클래스로 분리해야 함.
