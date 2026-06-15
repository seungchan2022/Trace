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
- Keep tests deterministic. Avoid sleeps and real network calls.
- Use fixtures for repeatable data.

## UI and Simulator Checks

- Use simulator verification for navigation, visible UI, gestures, permissions, and lifecycle behavior.
- Capture screenshots or logs for UI changes when useful.
- Use `ios-debugger-agent` and XcodeBuildMCP-backed workflows for simulator build/run/debug tasks.

## Performance and Memory

- Use `swiftui-performance-audit` for jank, slow rendering, or expensive updates.
- Use `ios-ettrace-performance` for focused runtime profiling.
- Use `ios-memgraph-leaks` for leaks, retain cycles, or memory growth.

## Completion Standard

A task is not complete until:

- Required behavior is implemented.
- Relevant tests or build checks pass.
- Manual simulator evidence exists for UI behavior when needed.
- Any skipped verification is clearly reported with the reason.
