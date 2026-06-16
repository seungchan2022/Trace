# Trace

Trace is an iOS app project built with Swift and SwiftUI.

## Project Baseline

- Platform: iOS
- Minimum deployment target: iOS 17.0
- Language: Swift
- UI framework: SwiftUI
- Architecture direction: MVVM with Clean Architecture boundaries
- Xcode project: `Trace.xcodeproj`
- Scheme: `Trace`

## Structure

```text
Trace.xcodeproj
Trace/          # App target
TraceTests/     # Unit tests
TraceUITests/   # UI tests
docs/           # Agent and project rules
```

## Verification

Use the current local simulator target:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test
swiftlint
```
