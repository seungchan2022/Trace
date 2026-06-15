# Testing and Verification Rules

## Baseline

Before claiming completion, run the strongest practical verification for the change.

Use these in order when available:

```bash
xcodebuild -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme Trace -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The exact scheme and simulator may change after the Xcode project is created. Update this file when they are known.

## Unit Tests

- Add unit tests for parsing, formatting, state transitions, persistence, services, and non-trivial domain logic.
- Keep tests deterministic.
- Avoid real network calls in tests.

## UI and Simulator Checks

- Use simulator verification for navigation, visible UI, gestures, permissions, and lifecycle behavior.
- Use `ios-debugger-agent` and XcodeBuildMCP-backed workflows for simulator build/run/debug tasks.

## Performance and Memory

- Use `swiftui-performance-audit` for jank, slow rendering, or expensive updates.
- Use `ios-ettrace-performance` for focused runtime profiling.
- Use `ios-memgraph-leaks` for leaks, retain cycles, or memory growth.
