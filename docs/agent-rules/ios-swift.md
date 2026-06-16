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
- Use `@Observable` for ViewModels and shared observable state where appropriate.
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

- Prefer Swift modern concurrency over classic GCD for new asynchronous code.
- Consider `async`/`await`, `Task`, `TaskGroup`, `AsyncSequence`, actors, and `Sendable` first.
- Use `DispatchQueue.async`, `DispatchGroup`, `DispatchSemaphore`, or manual queue hopping only for compatibility, callback bridging, or a clear performance reason.
- Prefer `@MainActor`, `MainActor.run`, or actor isolation over `DispatchQueue.main.async`.
- Wrap callback APIs with `withCheckedContinuation` or `withCheckedThrowingContinuation` when creating async call sites.
- Prefer task cancellation propagation over GCD work item cancellation.

## Xcode

- Prefer Xcode project settings and Swift Package Manager over custom build scripts.
- Do not hand-edit `project.pbxproj` unless necessary.
- Keep generated files, DerivedData, archives, and user-specific Xcode state out of git.

## Dependencies

- Add a dependency only when it clearly removes risk or substantial complexity.
- Before adding a package, record why native APIs are insufficient.
- Pin dependency versions through Swift Package Manager.
