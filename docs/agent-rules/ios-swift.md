# iOS and Swift Rules

## Defaults

- Target iOS 17+.
- Use Swift and SwiftUI unless the user explicitly requests UIKit or another framework.
- Follow Swift's official API Design Guidelines.
- Use Swift concurrency (`async`/`await`, actors, `Task`) where it fits naturally.
- Prefer value types and immutable data flow.
- Prefer `struct`; use `class` only when reference semantics, identity, inheritance, or Objective-C/runtime interoperability is required.
- Prefer protocol-oriented programming where it improves testability and boundaries.
- Use native Apple frameworks before third-party dependencies.
- Keep platform availability explicit when using iOS 26+ APIs.
- Data models should conform to `Codable` unless there is a clear reason not to.
- Presentation architecture is MVVM. Do not switch to MVI without an explicit project decision.

## SwiftUI

- Keep views small and composable.
- Use declarative SwiftUI patterns.
- Use local `@State` for view-local state.
- For iOS 17+ ViewModels and shared observable state, prefer the Observation API:
  `@Observable` plus `@State` ownership in SwiftUI views.
- Do not introduce new `ObservableObject`, `@Published`, `@StateObject`, or
  `@ObservedObject` patterns unless interoperability with legacy code or an
  older deployment target requires them.
- Use `.task { await loadData() }` for view-scoped asynchronous loading.
- Use ViewModels for presentation state, side effects, service calls, permission requests, and network event handling.
- Views should declare UI, bind state, and forward user actions.
- Keep business logic out of view bodies.
- Model navigation explicitly.

## Type Safety

- Minimize `Any` and `AnyObject`; prefer generics or protocols.
- Do not use force unwrap (`!`) outside tests. Use `guard let`, `if let`, or `??`.
- Do not use force cast (`as!`). Use `as?` with `guard`.
- Do not use force try (`try!`). Use `do/catch` or propagate errors.
- Minimize `@objc`; prefer Swift-native APIs.

## MVVM

- The presentation layer uses MVVM by default.
- ViewModels receive dependencies as protocol types where practical.
- ViewModels should be testable without launching the app or simulator.
- Keep state transitions explicit and observable.

## Dependency Injection

- Use protocol-based abstraction for services.
- Use a `DependencyContainer` for app-wide dependencies.
- Before constructing a service inside a View or ViewModel, check whether the container or an existing injection path should provide it.
- Expose services as protocol types where practical.

## Clean Architecture Direction

- Keep dependencies pointing inward toward policy and domain behavior.
- UI should focus on user input and state presentation.
- UI should not directly depend on networking, storage, or system API implementation details.
- Separate protocols, services, mappers, DTOs, and entities where it improves testability.
- Keep platform-specific or framework-heavy code behind services or adapters.
- Write feature code so it can later move into a Swift Package without rewriting core business logic.
- Keep domain/app models free of SwiftUI imports.
- Map API/persistence DTOs into app/domain models before they reach ViewModels.

## Concurrency

- Write new asynchronous Swift code for Swift 6 concurrency checking.
- Prefer Swift modern concurrency over classic GCD for new asynchronous code.
- Consider `async`/`await`, `Task`, `TaskGroup`, `AsyncSequence`, actors, and `Sendable` first.
- Use `DispatchQueue.async`, `DispatchGroup`, `DispatchSemaphore`, or manual queue hopping only for compatibility, callback bridging, or a clear performance reason.
- Prefer `@MainActor`, `MainActor.run`, or actor isolation over `DispatchQueue.main.async`.
- Wrap callback APIs with `withCheckedContinuation` or `withCheckedThrowingContinuation` when creating async call sites.
- Prefer task cancellation propagation over GCD work item cancellation.
- Keep UI state mutation on `@MainActor`.
- Mark value types that cross concurrency boundaries as `Sendable` when their
  stored properties support it.

### 격리 기본값과 `nonisolated` 판단 (2026-08-03 정리 · 근거는 MVP12 실기기 크래시 `18fa11a`)

- **프로젝트 기본 격리를 두지 않는다.** `SWIFT_DEFAULT_ACTOR_ISOLATION`은 미설정이 정답이다(현재 0건).
  **새 Xcode 템플릿이 `= MainActor`를 자동으로 넣어주므로**, 프로젝트를 새로 만들거나 빌드 설정을
  손댈 때 다시 들어오지 않았는지 확인한다. 되돌리면 안 되는 이유는 `project-decisions.md`의
  "Swift 언어 모드" 항목.
- **`@MainActor`는 화면·상태를 다루는 타입에 붙인다.** 그 외에는 붙이지 않는다.
- **`nonisolated`는 "애플이 직접 부르는 멤버"에 붙인다.** 판단 기준은 *무엇을 하는가*가 아니라
  **누가 부르는가**다. 순수 계산이어도 우리만 부르면 `@MainActor` 아래 둬도 무해하고, 반대로
  UI 상태를 바꾸는 delegate 콜백이라도 애플이 부르면 **반드시 빼야 한다** — 빼고 그 안에서
  `Task { @MainActor in }`으로 필요한 부분만 메인에 넘긴다(`CoreLocationService`가 그 형태다).
- **위험 신호 셋** — ① `~Delegate` 프로토콜이 요구하는 메서드 ② 애플 프로토콜이 요구하는 프로퍼티
  (`MKOverlay.boundingMapRect`, `MKAnnotation.coordinate` 등) ③ **`NSObject` 상속 + 애플 프로토콜 채택.**
  **③이 실기기를 죽인 조합이다.** 클래스 상속 불일치는 컴파일 경고가 나지만
  **프로토콜 준수는 경고가 안 나서** 런타임에만 드러난다(테스트 178개 전부 통과한 상태였다).
  이 조합의 타입을 새로 만들면 리뷰에서 반드시 확인하고, 시뮬레이터 스모크로 실제 렌더링을 한 번 본다.

## Xcode

- Prefer Xcode project settings and Swift Package Manager over custom build scripts.
- Do not hand-edit `project.pbxproj` unless necessary.
- Keep generated files, DerivedData, archives, and user-specific Xcode state out of git.

## Dependencies

- Add a dependency only when it clearly removes risk or substantial complexity.
- Before adding a package, record why native APIs are insufficient.
- Pin dependency versions through Swift Package Manager.
