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

- **현재:** iOS 26.5 런타임 시뮬레이터 사용 (2026-06-23 크래시 없이 통과 확인). **"iOS 26+ 아무 버전"이 아니라 26.5로 고정 권장** — 아래 2026-07-03 재발 참고.
- **iOS 18.x에서도 테스트해야 할 경우:** ViewModel에 `nonisolated deinit { }` 추가 — 컴파일러가 isolated deinit을 합성하는 걸 방지하여 버그 경로 우회.

## 2026-07-03 재발: iOS 26.0에서도 크래시 확인

MVP9 edit-consistency 세션에서 iOS 26.0(build 23A343, iPhone 17 Pro) 시뮬레이터로 전체 스위트를 두 번 연속 실행 → 매번 동일한 5개 테스트가 결정적으로 크래시(`CameraStateStoreTests` 3개, `CoursePlannerViewModelTests.testDefaultModeIsTap`, `CourseEditSessionTests.testUndo_empty_doesNothing`). 5개 모두 해당 세션 diff와 무관한 기존 테스트(일부는 아예 미수정 파일)였고, 크래시 스택은 위와 동일(`swift_task_deinitOnExecutorImpl` → `___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED`, SIGABRT). 같은 UDID로 iOS 26.5로 전환 후 재실행하니 전체 통과.

**결론:** 이 버그는 26.x 내에서도 빌드별로 재발할 수 있다. "iOS 26+ 런타임" 대신 **iOS 26.5로 구체적으로 고정**해서 세션을 시작할 것 (`docs/agent-rules/testing.md`의 기준 시뮬레이터 선택 절차도 함께 갱신 필요).

**교훈 — pre-commit 스탬프 신선도:** `.githooks/pre-commit`은 `.git/trace-verify-*.ok` 스탬프의 *존재*만 확인하고 생성 시각은 검증하지 않는다. 이전 세션에서 만든 오래된 스탬프가 남아 있으면, 이번 세션에서 검증이 실패했는데도 커밋이 통과할 수 있다. 커밋 전 반드시 스탬프가 **이번 세션에서 방금** 생성됐는지 타임스탬프로 확인할 것 — 특히 서브에이전트에게 검증+커밋을 맡길 때.

## 추가 발견 (같은 세션)

1. **`-parallel-testing-enabled NO` 필수** — 없으면 xcodebuild가 시뮬레이터를 자동 복제(clone)해 병렬 테스트 실행 → 복제 시뮬레이터에서 앱 런칭 실패 (`FBSOpenApplicationServiceErrorDomain Code=1`).
2. **블로킹 Stub 분리** — `CheckedContinuation` 기반 블로킹 stub이 모든 테스트에서 사용되면, `snappedRoute` 기본 구현이 `route()`를 호출할 때 영원히 블로킹 → 테스트 타임아웃/크래시. 블로킹 stub은 레이스 컨디션 테스트 전용 클래스로 분리해야 함.
