# Testing and Verification Rules

## Simulator Discipline (필수)

**시뮬레이터는 세션 전체에서 단 하나만 사용한다.** 이 규칙은 모든 에이전트·서브에이전트에 적용된다.

### 절대 금지

- `name=` 기반 destination 사용 금지 — 동일 이름 시뮬레이터가 iOS 버전별로 여러 개 존재하여 매칭이 모호해짐
- 테스트/빌드 실패 시 다른 시뮬레이터로 재시도 금지 — 실패 원인은 시뮬레이터가 아니라 코드임
- 동시에 여러 xcodebuild 프로세스 실행 금지 — 이전 빌드/테스트가 끝나기 전에 새 빌드를 시작하지 않는다
- 시뮬레이터가 응답하지 않을 때 다른 시뮬레이터로 전환 금지 — 아래 복구 절차를 따른다
- **테스트 스위트 실행에 XcodeBuildMCP의 테스트 툴(`test_sim` 등) 사용 금지** — 기본값이 병렬 테스트라 시뮬레이터를 자동 복제하고, 이 프로젝트의 알려진 크래시성 플레이키 테스트(iOS `@Observable` malloc 버그 등, 위 참고)가 그 복제본 중 하나에서 크래시하면 xcodebuild가 응답 없이 무한 대기한다(2026-07-02 확인: CPU 사용 없이 44분+ 행 상태, `test-without-building`이 죽은 병렬 러너를 기다리며 멈춤). 테스트는 반드시 Baseline의 raw bash `xcodebuild ... -parallel-testing-enabled NO test` 명령으로만 실행한다. 빌드/실행/런치/UI 자동화(스크린샷, 탭 등)에는 XcodeBuildMCP를 계속 사용해도 된다 — 막는 것은 테스트 실행 한 가지뿐이다.

### 기준 시뮬레이터 선택 절차

세션 시작 시 한 번만 실행:

```bash
# 1) iOS 26.5 런타임의 iPhone을 선택 (iOS 18.x·26.0은 @Observable malloc 버그로 테스트 크래시 발생, 아래 참고)
xcrun simctl list devices available | grep "iPhone"
# 출력 예: iPhone 17 Pro (D887D0A4-...) (Shutdown)  ← iOS 26.5

# 2) 선택한 UDID를 세션 전체에서 고정
SIM_UDID="D887D0A4-074C-4AFB-8D08-D87329D0EFD4"
```

한번 선택하면 세션이 끝날 때까지 이 UDID만 사용한다. 절대 중간에 바꾸지 않는다.

> **iOS 18.x·26.0 런타임 금지 (2026-06-23 확인, 2026-07-03 26.0 재발 확인):** iOS 18.5에서 `@Observable` 객체 해제 시 `malloc: pointer being freed was not allocated` (고정 주소 `0x25237aac0`)가 발생해 테스트 프로세스가 크래시 → xcodebuild가 재시작을 반복하는 무한 루프. iOS 26.5에서는 크래시 없이 통과 확인했으나, 2026-07-03 iOS 26.0(build 23A343)에서 동일 크래시가 재발했다(전체 스위트 실행 시 5개 테스트가 결정적으로 크래시, `docs/solutions/workflow-issues/ios18-observable-malloc-crash.md` 참고). "iOS 26+ 아무 버전"이 아니라 **iOS 26.5로 구체적으로 고정**한다.

### 시뮬레이터 무응답/무한 로딩 복구

시뮬레이터가 멈추거나 xcodebuild가 타임아웃되면:

```bash
# 1) 걸린 xcodebuild 먼저 종료
pkill -f "xcodebuild.*Trace"

# 2) 모든 시뮬레이터 종료
xcrun simctl shutdown all

# 3) 같은 UDID로 재부팅하여 재시도 (다른 시뮬레이터로 바꾸지 않는다)
xcrun simctl boot $SIM_UDID
```

다른 UDID로 전환하는 것은 복구가 아니라 좀비 누적의 원인이다.

**"Busy"/preflight 실패는 위 절차로 안 풀린다 (2026-07-12 확인):** 짧은 시간에 boot/erase/install/실행을 수십 번 반복하면 `Error Domain=FBSOpenApplicationErrorDomain Code=6 "Application failed preflight checks", BSErrorCodeDescription=Busy`가 나면서 앱 실행 자체가 거부된다. `simctl shutdown all` + 재부팅만으로는 이 상태가 풀리지 않는다 — CoreSimulator 데몬 자체를 재시작해야 한다:

```bash
xcrun simctl shutdown all
killall -9 com.apple.CoreSimulator.CoreSimulatorService
xcrun simctl boot $SIM_UDID
```

이 증상이 나타났다고 그 시점에 조사 중이던 앱/테스트 코드까지 "환경 문제"로 성급히 결론짓지 않는다 — 별개의 문제일 수 있다(아래 "UI 테스트 실패 원인 파악 순서" 참고).

### UI 테스트 실패 원인 파악 순서

UI 테스트가 "요소가 나타나지 않는다"는 형태로 실패하면, 타임아웃 조정·병렬 시뮬레이터 경합·테스트 호스트 오염 같은 환경 가설을 세우기 **전에** 먼저 실패 시점의 접근성 트리부터 확인한다. XCTest는 실패한 모든 `waitForExistence`/쿼리 단언에 대해 전체 접근성 트리("Debug description")를 커스텀 계측 없이 이미 `.xcresult`에 자동 캡처해 둔다:

```bash
xcrun xcresulttool export attachments --path <xcresult-path> --output-path <dir>
```

`<xcresult-path>`는 테스트 실행 로그에 출력되는 `Test session results...` 경로(보통 `~/Library/Developer/Xcode/DerivedData/<project>/Logs/Test/*.xcresult`)다. export된 "Debug description" 텍스트 파일을 읽으면 실패 순간 화면에 정확히 무엇이 렌더링되어 있었는지(엘리먼트 위치, 라벨, disabled 여부 등) 바로 보인다 — 타이밍/환경 가설을 며칠씩 뒤쫓는 대신 몇 분 만에 근본 원인에 도달할 수 있다. 상세 사례는
`docs/solutions/ui-bugs/frame-maxheight-inflates-zstack-child-and-swallows-taps.md` 참고.

**"레이아웃이 잠깐 움찔거렸다 돌아온다"는 애니메이션/전환 중 버그는 접근성 트리 정적 덤프로 안 잡힌다** — 위 기법은 실패 시점의 한 프레임짜리 스냅샷이라, 몇백 ms 동안만 나타났다 사라지는 크기 변화는 코드 추론만으로 찾으려 하지 말고 직접 실측한다: 의심되는 하위 뷰마다 임시 `onGeometryChange`를 붙이고 그 값을 `-traceUITesting` 플래그로 게이팅한 숨김 `Text`(`.opacity(0.01)` + `accessibilityIdentifier`)로 노출한 뒤, XCUITest에서 짧은 간격(20~80ms)으로 폴링해 전이 순간의 실제 값을 잡는다. 목업 서비스가 즉시 응답해 관찰 창이 폴링 간격보다 짧으면, 목업에 짧은 인위적 지연(`Task.sleep`, 임시 launch-argument로 게이팅)을 추가해 창을 넓힌다. 확인 후 진단 코드는 전부 제거한다. 이 방식으로 잡은 두 사례: `docs/solutions/ui-bugs/firsttextbaseline-alignment-jiggle-with-mixed-child-types.md`, `docs/solutions/ui-bugs/safe-area-top-inset-shrinks-with-sibling-size-feedback-loop.md`. bottomSheet 내부 자식은 accessibilityIdentifier가 부모로 뭉개지는 별도 이슈가 있으니 `docs/solutions/workflow-issues/child-accessibility-identifiers-collapse-to-parent-in-bottomsheet.md`도 참고.

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
# SIM_UDID는 위 "기준 시뮬레이터 선택 절차"에서 고정한 값을 사용
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" build
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug -destination "platform=iOS Simulator,id=$SIM_UDID" -parallel-testing-enabled NO test
swiftlint
```

`-parallel-testing-enabled NO`는 필수 — 없으면 xcodebuild가 시뮬레이터를 자동 복제(clone)해 테스트를 병렬 실행하며, 복제된 시뮬레이터에서 앱 런칭 실패(`FBSOpenApplicationServiceErrorDomain`)가 발생한다.

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
- Use `ios-debugger-agent` and XcodeBuildMCP-backed workflows for simulator build/run/debug tasks — **not for running the test suite**; see Simulator Discipline above for why.

## Real-Device Verification

- Agents cannot run on physical hardware (no attached device; code signing is interactive). For user-facing features that touch UI, gestures, location/permissions, or other hardware, simulator and automated tests are necessary but not sufficient — do not claim device behavior verified from the simulator.
- After automated tests and simulator verification pass, the agent MUST produce a real-device QA checklist for the user to execute. Treat it as the closing step of such features (alongside `superpowers:verification-before-completion` / `finishing-a-development-branch`); it augments those plugin flows and is not edited into them.
- User real-device sign-off is required before a release (TestFlight or App Store), not for every branch merge. Pure logic, refactors, docs, and non-UI changes are exempt.
- The checklist must target what the simulator and tests cannot: real permission prompts and GPS, true touch/gesture feel, region-specific behavior (e.g., Korea map/routing quality), performance under real network, and intent-match (does the built feature match the intended UX).
- Save the feature-specific checklist as `docs/qa/YYYY-MM-DD-<feature>-device-checklist.md` and hand it to the user. Use the template below.
- Capture feedback from manual testing into `docs/backlog.md`: genuinely broken behavior is fixed in the current session, but intent-mismatches and improvements are recorded as backlog items (where/now/desired) and deferred to a later milestone — do not expand the current milestone to chase them. The backlog is consumed at milestone start; see `docs/agent-rules/skills.md`.

### 체크리스트 배치 처리 (2026-07-13)

사용자는 체크리스트 전체를 실기기에서 다 채운 뒤 한 번에 전달한다(항목별로 나눠 보고하지
않음). 이 배치를 받았을 때의 처리 순서:

1. **통과 항목은 조치 없음** — 백로그에도 등록하지 않는다. 확인 끝.
2. **실패 항목만 모아 분류** — 항목별로 `docs/agent-rules/workflow.md`의 "버그 처리 경로"
   1번(분류: 진짜 고장 → 지금 고침 / 의도 불일치·개선 → 백로그)을 그대로 적용한다. 백로그
   행은 이 시점에 즉시 기록하고, 사용자에게 "무엇을 지금 고치고 무엇을 백로그로 보냈는지" 1차
   보고를 한다. 이후 최종 보고에서 백로그 항목을 다시 언급하지 않는다.
3. **"지금 고침" 항목끼리 연관성 판단** — 같은 원인으로 보이는 항목은 하나로 묶는다(예:
   항목 1·2가 연관, 항목 3은 무관이면 [1,2] 묶음 하나 + [3] 묶음 하나).
4. **묶음 단위로 위임** — 서로 무관한 묶음은 각각 별도 서브에이전트로 **병렬** 위임한다
   (`superpowers:dispatching-parallel-agents`). 같은 묶음 안의 항목은 원인을 공유한다고 보고
   한 서브에이전트가 함께 처리한다. 각 서브에이전트는 `docs/agent-rules/workflow.md`의 버그
   처리 경로(2·3번: systematic-debugging, 시도 자가관리, 3회 실패 시 되돌리기+인수인계)를
   그대로 따른다 — 묶은 항목들은 한 원인으로 보고 시도 횟수를 합산해서 센다(항목별 3회가
   아니다).
5. **컨트롤러 검증** — 서브에이전트가 완료를 보고하면 컨트롤러가 diff와 테스트 결과를 직접
   확인한 뒤 승인한다. 서브에이전트가 이미 통과시킨 동일 테스트를 그대로 재실행하지는 않되,
   확인 자체를 생략하지 않는다.
6. **최종 보고는 한 번에** — 모든 묶음이 끝나면 고친 항목 / 되돌리고 인수인계한 항목을 한
   번에 정리해 보고한다.

### Real-Device Checklist Template

Use a scenario card for any test that needs multiple physical steps or a specific gesture sequence. Keep plain single-line checkboxes only for one-shot checks (build/install, known-limitations notes).

Write every scenario for a first-time user who has never seen the implementation: concrete physical actions ("두 손가락으로 지도를 축소하세요"), and a result the user can literally see ("어느 핀이 움직이는지 보세요"). Never use internal/implementation terms — threshold, gap, routing, hit-test, pixel/meter distinction, rule numbers, class/function names, spec/plan file paths, milestone names. This applies to the whole section the user reads, not just the numbered step lines: section headings, intro blockquotes, and closing/footer notes must be just as jargon-free as the steps — a plain-language step under a jargon-heavy heading still reads as confusing. If a scenario exists to probe an internal edge case, translate it into what the user would actually do and observe, not what the code checks.

```markdown
# <기능> 실기기 체크리스트 (YYYY-MM-DD)

## 빌드/설치
- [ ] 기기 연결, 자동 서명 팀 확인, Xcode Run 성공
- [ ] 첫 실행 시 기기에서 개발자 인증서 신뢰(설정 > 일반 > VPN 및 기기 관리)

## 권한
- [ ] 실제 권한 팝업 문구 확인, 허용 경로 동작
- [ ] 거부 경로 동작(크래시 없이 폴백)

## 핵심 기능 (손으로 수행)

### 시나리오 <N>: <한 줄 요약 — 무슨 결과를 보는 시나리오인지>

**준비:** <시작하기 전에 이미 되어 있어야 하는 상태>

**수행:**
1. <구체적인 동작 1 — 손으로 뭘 하는지>
2. <구체적인 동작 2>

**확인할 것:** <무엇을 눈으로 보면 되는지 — 통과/실패가 바로 판단되는 관찰 포인트>

**결과:** ☐ 통과 ☐ 실패
**메모:**

## 제스처/입력 감
(위와 같은 시나리오 카드 형식)

## 지역/환경 의존
(위와 같은 시나리오 카드 형식)

## 엣지/견고성
(위와 같은 시나리오 카드 형식)

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
