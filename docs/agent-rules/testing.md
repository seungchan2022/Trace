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

Use these in order:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test
swiftlint
```

If the `iPhone 17` / `iOS 26.5` simulator is unavailable, use `xcrun simctl list devices available` or XcodeBuildMCP to select an available iOS simulator, then keep the project and scheme arguments unchanged.
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

## Real-Device Verification

- Agents cannot run on physical hardware (no attached device; code signing is interactive). For user-facing features that touch UI, gestures, location/permissions, or other hardware, simulator and automated tests are necessary but not sufficient — do not claim device behavior verified from the simulator.
- After automated tests and simulator verification pass, the agent MUST produce a real-device QA checklist for the user to execute. Treat it as the closing step of such features (alongside `superpowers:verification-before-completion` / `finishing-a-development-branch`); it augments those plugin flows and is not edited into them.
- User real-device sign-off is required before a release (TestFlight or App Store), not for every branch merge. Pure logic, refactors, docs, and non-UI changes are exempt.
- The checklist must target what the simulator and tests cannot: real permission prompts and GPS, true touch/gesture feel, region-specific behavior (e.g., Korea map/routing quality), performance under real network, and intent-match (does the built feature match the intended UX).
- Save the feature-specific checklist as `docs/qa/YYYY-MM-DD-<feature>-device-checklist.md` and hand it to the user. Use the template below.
- Capture feedback from manual testing into `docs/backlog.md`: genuinely broken behavior is fixed in the current session, but intent-mismatches and improvements are recorded as backlog items (where/now/desired) and deferred to a later slice — do not expand the current slice to chase them. The backlog is consumed at slice start; see `docs/agent-rules/skills.md`.

### Real-Device Checklist Template

```markdown
# <기능> 실기기 체크리스트 (YYYY-MM-DD)

## 빌드/설치
- [ ] 기기 연결, 자동 서명 팀 확인, Xcode Run 성공
- [ ] 첫 실행 시 기기에서 개발자 인증서 신뢰(설정 > 일반 > VPN 및 기기 관리)

## 권한
- [ ] 실제 권한 팝업 문구 확인, 허용 경로 동작
- [ ] 거부 경로 동작(크래시 없이 폴백)

## 핵심 기능 (손으로 수행)
- [ ] 주요 사용자 플로우가 의도대로 동작

## 제스처/입력 감
- [ ] 실제 터치 반응·자연스러움, 충돌 없음

## 지역/환경 의존
- [ ] 대상 지역(예: 한국)에서 동작·품질 확인

## 엣지/견고성
- [ ] 빠른 반복 조작·대용량 입력·네트워크 지연 시 안정

## 의도 일치
- [ ] 만든 기능이 내가 원한 UX와 맞는가 (불일치 메모)

## 알려진 한계 (버그 아님)
- [ ] 사전 합의된 follow-up 항목 구분
```

## Performance and Memory

- Use `swiftui-performance-audit` for jank, slow rendering, or expensive updates.
- Use `ios-ettrace-performance` for focused runtime profiling.
- Use `ios-memgraph-leaks` for leaks, retain cycles, or memory growth.

## Security Verification

- Do not store sensitive information in UserDefaults.
- Store sensitive information in Keychain.
- Keep App Transport Security exceptions minimal.
- Keep authentication tokens in memory unless a Keychain-backed persistence decision exists.
