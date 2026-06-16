# Testing and Verification Rules

## Baseline

Before claiming completion, run the strongest practical verification for the change.

All three must pass before commit:

1. Build
2. Tests
3. Lint

For Swift or Xcode project changes, the pre-commit hook requires verification stamps in `.git/`:

```bash
# After build succeeds
touch .git/trace-verify-build.ok

# After tests succeed
touch .git/trace-verify-test.ok

# After lint succeeds
touch .git/trace-verify-lint.ok
```

Do not create these stamps unless the corresponding command actually passed in the current working tree.

Use these in order when available:

```bash
xcodebuild -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 17' test
swiftlint
```

The exact scheme and simulator may change after the Xcode project is created. Update this file when they are known.
SwiftLint is configured by `.swiftlint.yml`.

## Unit Tests

- Use XCTest or Swift Testing.
- Add unit tests for parsing, formatting, state transitions, persistence, services, and non-trivial domain logic.
- Create mocks through protocol-based abstractions.
- Mock networking with `URLProtocol` subclasses.
- Keep tests deterministic.
- Avoid real network calls in tests.
- Maintain at least 90% coverage.

## UI and Simulator Checks

- Use simulator verification for navigation, visible UI, gestures, permissions, and lifecycle behavior.
- Use XCUITest or ViewInspector for UI tests.
- Use `ios-debugger-agent` and XcodeBuildMCP-backed workflows for simulator build/run/debug tasks.

## Performance and Memory

- Use `swiftui-performance-audit` for jank, slow rendering, or expensive updates.
- Use `ios-ettrace-performance` for focused runtime profiling.
- Use `ios-memgraph-leaks` for leaks, retain cycles, or memory growth.

## Security Verification

- Do not store sensitive information in UserDefaults.
- Store sensitive information in Keychain.
- Keep App Transport Security exceptions minimal.
- Keep authentication tokens in memory unless a Keychain-backed persistence decision exists.
