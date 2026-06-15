# iOS and Swift Rules

## Defaults

- Use Swift and SwiftUI unless the user explicitly requests UIKit or another framework.
- Use Swift concurrency (`async`/`await`, actors, `Task`) where it fits naturally.
- Prefer value types and immutable data flow.
- Use native Apple frameworks before third-party dependencies.
- Keep platform availability explicit when using iOS 26+ APIs.

## SwiftUI

- Keep views small and composable.
- Use local `@State` for view-local state.
- Use `@Observable` or environment-injected models for shared app state when needed.
- Do not introduce view models by default. Add them only when they reduce real complexity or match the existing architecture.
- Keep business logic out of view bodies.
- Model navigation explicitly.

## Xcode

- Prefer Xcode project settings and Swift Package Manager over custom build scripts.
- Do not hand-edit `project.pbxproj` unless necessary.
- Keep generated files, DerivedData, archives, and user-specific Xcode state out of git.

## Dependencies

- Add a dependency only when it clearly removes risk or substantial complexity.
- Before adding a package, record why native APIs are insufficient.
- Pin dependency versions through Swift Package Manager.
