# Skill and Plugin Rules

## Installed Plugins

- Superpowers: planning, TDD, debugging, review, verification workflows
- Compound Engineering: code review, documentation of reusable learnings, workflow utilities
- Build iOS Apps: SwiftUI, Xcode, Simulator, performance, memory workflows
- GitHub: repository, issue, PR, and review workflows when needed
- XcodeBuildMCP: configured globally as `XcodeBuildMCP` for simulator, UI automation, debugging, and logging
- Playwright MCP: configured globally for browser-backed checks when needed
- Sequential Thinking MCP: configured globally for structured reasoning support when needed

**규칙이 요구하는 스킬 호출이 실패하면 그 단계를 건너뛰고 진행하지 않는다.** 멈추고 사용자에게
알린다 — 어떤 스킬이 왜 실패했는지, 재시작이 필요한지. 실패를 삼키고 넘어가면 "필수"로 적힌
단계가 조용히 빠진다. MVP17 후반(`sheet-drag`·`lint-cleanup`, 2026-07-23~27)에서 나온 교훈이
`docs/solutions/`에 기록되지 않은 것이 그 예다 — 저장 키 개명이 사용자 데이터를 해독 불가로
만들 뻔한 건은 회고에만 남고 재사용 가능한 형태로 옮겨지지 않았다(경위: `docs/workflow-audit.md` §3-2-2 ③).

**플러그인을 설치·갱신·활성화한 뒤에는 도구를 완전히 재시작한다.** 재시작 전에는 스킬이
호출 목록에 나타나지 않고, 호출하면 `Unknown skill`로 실패한다 — 설정은 정상이므로
설정 파일을 봐서는 원인을 찾을 수 없다. 2026-07-29에 실제로 발생했다(경위: `docs/workflow-audit.md` §5-7).

**`disable-model-invocation: true`가 붙은 스킬은 에이전트가 호출할 수 없다.** 사용자가
직접 `/<name>`으로 실행해야 한다. compound-engineering 3.19.0에서는 8개가 여기 해당하며,
그중 `ce-test-xcode`(iOS 빌드·테스트)가 Trace와 관련이 있다.

## Trace-Specific Shared Skills

- `trace-init`: restore Trace session state at the start of a new chat.
- `daily-retro`: summarize the day and capture lessons or follow-up work.
  **사용자가 직접 호출한다** — 에이전트가 먼저 제안하지 않는다. 하루라는 단위가 세션 만료로
  자주 잘려서 회고 기준이 되기 어렵다는 것이 확인됐다(2026-07-30). 완결 단위 회고는
  `milestone-retro`가 맡는다.
- `milestone-retro`: 마일스톤 하나가 끝났을 때 사용자 인터뷰 기반 회고를 쓴다.
  **트리거 — 실기기 QA 결과를 수용하고 `docs/roadmap.md`의 마일스톤을 `[x]`로 바꾸는 시점**에
  에이전트가 제안한다(강제 아님). 산출물은 `docs/retro/`에 두고 `trace-archive`가 `history/mvpN/`으로 옮긴다.
  MVP 완료 회고에는 사용자 인터뷰가 없으므로, 사용자 판단이 기록되는 자리는 이 스킬과 `daily-retro`뿐이다.
- `trace-archive`: archive a completed MVP's artifacts and update its index/roadmap state.
- `trace-study`: build a learning walkthrough for a completed MVP.
- `trace-video-review`: review an external video/content tip (e.g. YouTube) against current Trace rules and memories, and judge whether it's worth adopting.

Each canonical source lives at `.agents/skills/<name>/SKILL.md`. Codex calls it with `$<name>`;
Claude Code calls the same source with `/<name>` through a `.claude/skills/<name>` symlink. No Trace skill body is copied into a tool-specific prompt directory. See `docs/prompts/setup-codex.md`, `setup-claude.md`, and `docs/agent-rules/dual-tool.md`.

## Required Skill Use

- Start a new milestone by reviewing `docs/backlog.md` and selecting what it addresses — backlog items are milestone candidates and an input to brainstorming, not a forced queue (a new feature can be chosen instead). Small, well-specified items may skip straight to spec/plan; decision-heavy or ambiguous ones go through `superpowers:brainstorming`. For work-unit definitions (MVP, milestone), top-down flow, and review checkpoints, see `docs/agent-rules/workflow.md`. Manual-test feedback is captured back into the backlog; see `docs/agent-rules/testing.md`.
- Use `superpowers:brainstorming` before creative product or feature work.
- Use `superpowers:writing-plans` before multi-step implementation.
- Implement a written plan task-by-task, never ad hoc. **Default execution method: `superpowers:subagent-driven-development`** — do not ask the user which method to use; proceed immediately. Only fall back to `superpowers:executing-plans` (inline) if the user explicitly requests it or if subagent dispatch is unavailable. Either way, tick each plan checkbox (`- [ ]` → `- [x]`) the moment its step completes — this is the cross-tool handoff channel, and it does not depend on any skill being installed; see `docs/agent-rules/dual-tool.md`.
- Use `superpowers:test-driven-development` for bug fixes and behavior changes where tests are practical.
- Use `superpowers:systematic-debugging` before fixing bugs or unexpected behavior.
- Use `superpowers:verification-before-completion` before claiming completion.
- Use `superpowers:requesting-code-review` for major work and before merge.
- **Compound step — 판단은 매번, 기록은 해당할 때만.** (2026-07-30 개정)

  **언제 판단하나** — 세 지점. 앞의 둘이 실제 기록 시점이고, 마지막은 그물이다.

  | 시점 | 무엇을 보나 |
  |---|---|
  | Task 하나를 끝내고 커밋한 직후 | 그 Task를 만들며 알게 된 것 |
  | 실기기 QA에서 나온 문제를 고치고 검증한 직후 | 실기기에서만 드러난 것 |
  | 마일스톤을 닫기 직전 | 위에서 빠뜨린 것이 없는지 최종 확인 |

  **모아뒀다 한꺼번에 하지 않는다.** `ce-compound`는 "맥락이 신선할 때 포착"하도록
  설계됐고 "한 번에 하나(One learning per run)"를 명시한다. 교훈이 둘이면 두 번 실행한다.
  미루면 세션 종료·컴팩션과 함께 사라진다 — MVP17 후반이 그렇게 빠졌다.

  **전제 (셋 다 충족해야 기록 대상)** — `ce-compound` 원문 Preconditions:
  문제가 해결됐고 · 해결이 검증됐고 · 사소하지 않다(오타·뻔한 오류 제외).

  **해당 여부 (하나라도 예면 기록)** — 항목 순서는 `docs/solutions/` 20건의 실제 분포 기준:

  | # | 질문 | 근거 |
  |---|---|---|
  | 1 | 도구·프레임워크·환경이 **예상과 다르게** 동작했나 | 20건 중 7건 (가장 잦음) |
  | 2 | 원인을 찾기 어려운 UI·레이아웃 문제를 풀었나 | 4건 |
  | 3 | 다른 곳에도 쓸 **해법 패턴**을 찾았나 | 4건 |
  | 4 | 같은 문제로 **두 번 이상** 막혔나 | 세션 리셋 기준 등 |
  | 5 | 놓쳤으면 **사용자 데이터·빌드가 깨졌을** 문제를 발견했나 | MVP17 저장 키 개명 건 |

  판단이 애매하면 기준선은 하나다 — **다음에 같은 상황이 와도 또 헤맬 것 같은가.**
  아니면 기록하지 않는다. 실제로 3개월간 20건, 마일스톤당 1건이 안 된다.

  기록 내용: 무엇이 일어났고 · 왜 그랬고 · 무엇을 봤으면 일찍 잡았을지 · 재사용할 규칙/검사/패턴.
  일반적인 요약에는 쓰지 않는다. 자동 실행에는 `ce-compound mode:headless`.

  - 이 규칙은 Codex의 `openai-curated` superpowers에는 내장돼 있으나 obra superpowers(v6.x,
    Claude Code 설치본)가 자동 호출하지 않는 통합을 대신한다. 플러그인 SKILL.md가 아니라
    규칙에 두어야 플러그인 갱신에도 살아남고 두 도구에 함께 적용된다.
  - `milestone-retro`와 엮지 않는다. 이쪽은 **에이전트가 기술적 함정을 기록**하는 것이고,
    회고는 **사용자가 판단·감각을 남기는** 것이다. 회고를 넘겨도 이 판단은 그대로 수행한다.
- Use `ce-compound` when a workflow rule is updated because of an agent mistake.

## 쓰지 않기로 정한 스킬 (2026-07-30 사용자와 함께 결정)

설치돼 있지만 Trace에서 쓰지 않는다. 매번 "이것도 써야 하나"를 다시 묻지 않기 위해 명시한다.

**중요 — "안 쓴다"가 "영원히 못 쓴다"는 뜻은 아니다.** 아래 각 항목의 *제안 조건*이 실제로
관측되면 **에이전트가 먼저 그 스킬을 제안한다.** 사용자가 스킬 이름을 기억해서 직접 꺼내야
하는 상태로 두지 않는다 — 사용자는 스킬 내부 동작을 알 수 없으므로, 에이전트가 알리지 않으면
필요한 순간에도 쓸 수 없다(2026-07-30 사용자 확인).

| 스킬 | 쓰지 않는 이유 | 에이전트가 제안할 조건 |
|---|---|---|
| `superpowers:using-git-worktrees`, `ce-worktree` | 한 작업 세션은 브랜치 하나로 진행한다(`git.md`). MVP17 마일스톤 4개 중 3개가 서로 파일을 공유했고(`run-idle-polish`는 `history-tab`의 산출물을 제거, `lint-cleanup`은 전 파일 개명), 앞 마일스톤의 실기기 QA 실패가 뒤 마일스톤 설계를 바꿨다 — 순서가 필요한 구조다 | **파일이 겹치지 않는 독립 작업 두 개를 동시에 진행해야 할 때** (예: iOS와 웹 버전을 투 트랙으로) |
| `superpowers:dispatching-parallel-agents` | 여러 문제를 나눠 조사하는 도구다. TDD로 작게 만들기 때문에 한 번에 하나씩만 깨지고, 버그도 규칙상 하나씩 처리한다(`workflow.md` 버그 처리 경로) | **테스트가 3개 이상 깨졌고 원인이 서로 다를 때** (예: iOS 메이저 버전 전환처럼 한 번에 여러 곳을 건드린 뒤) |
| `ce-brainstorm`, `ce-plan`, `ce-work`, `ce-debug` | superpowers 쪽과 역할이 같다. 겹치는 지점은 **superpowers를 쓴다.** 이전에 `brainstorming` + `ce-ideate`를 둘 다 부르게 적혀 있어 같은 일을 두 번 하던 전례가 있다 | 문서 체계를 ce 계열로 통째 전환하기로 결정할 때만 (부분 도입은 이음새가 어긋난다) |
| `ce-ideate` | ce 세트의 첫 단계이고 출력을 `ce-brainstorm`으로 넘기도록 설계됐다(SKILL.md 3·44행). 기본 출력이 HTML이라 markdown 문서 체계와도 어긋난다. 아이디어 비교는 `superpowers:brainstorming`의 2~3안 비교로 대응한다 | — (같은 기능을 커스텀 스킬로 만들지 검토 중: `docs/backlog.md`) |
| 브라우저 QA 계열 (`ce-test-browser`, `ce-dogfood`, `ce-polish`) | 웹 페이지를 띄워 검증하는 도구다. Trace는 iOS 앱이고 웹 화면이 없다 | — |

**아직 정하지 않은 것:** `superpowers:receiving-code-review`, `ce-test-xcode`,
그리고 위 표에 없는 나머지 `ce-*`. 근거와 쟁점은 `docs/workflow-audit.md` §3-2-2.

**`ce-code-review`는 여기 없다** — `/code-review`가 곧 `ce-code-review`이며 실제로 쓰고 있다
(`dual-tool.md` 최종 브랜치 리뷰 절).

## Asking the User Decisions

- When proposing options or asking the user to make a decision, ask **in chat as plain text** using an `A / B / C` list, and mark the recommended option with `(추천)`. Do not use the built-in interview/question UI (e.g. the `AskUserQuestion` tool or any skill's structured-question prompt) for this.
- This applies to essentially every time you propose something or ask the user to choose, including inside `superpowers:brainstorming` and other skills that would otherwise pop a structured question UI. The skill flow still applies — only its asking mechanism changes to A/B/C chat.
- Kept here (not in any plugin SKILL.md) so it survives plugin updates and applies in both Codex and Claude Code. Established 2026-06-20 at user request.
- **Multi-question sequences (e.g. `daily-retro` Phase 2, brainstorming's clarifying questions):** when a user's answer to one question includes elaboration or a tangent, do not act on it immediately (no editing, no implementing) — note it, finish asking the remaining questions in the list first, then synthesize all answers together before moving to the next phase. (2026-07-13, after repeated mid-interview implementation drift.)

## iOS Skill Index

- `swiftui-ui-patterns`: SwiftUI screen composition, navigation, state, controls
- `swiftui-view-refactor`: split large views, tighten state ownership
- `swiftui-performance-audit`: diagnose rendering and update performance
- `swiftui-liquid-glass`: iOS 26+ Liquid Glass UI work
- `ios-debugger-agent`: build, run, inspect logs, and debug on Simulator
- `ios-simulator-browser`: mirror Simulator and preview SwiftUI in browser
- `ios-ettrace-performance`: capture and interpret ETTrace profiles
- `ios-memgraph-leaks`: capture and inspect memgraphs and leaks
- `ios-app-intents`: Shortcuts, Siri, Spotlight, widgets, and controls

## Xcode MCP

- Use the `XcodeBuildMCP` MCP server for Xcode project discovery, simulator control, build/run, UI inspection, screenshots, logging, and debugging.
- Server configuration (per tool; each tool registers MCP separately):
  - command: `npx`
  - args: `-y xcodebuildmcp@latest mcp`
  - workflows: `simulator,ui-automation,debugging,logging`
  - Codex: `~/.codex/config.toml` `[mcp_servers.*]`; Claude Code: `claude mcp add`. See `docs/prompts/setup-codex.md` / `setup-claude.md`.
- Restart the tool after MCP config changes so the server tools become available.

## Git Safety Integration

- Skills and plugins never override the repository Git safety rules in `docs/agent-rules/git.md`.
- Even if a skill suggests pushing, creating a PR, or finishing a branch, do not push or integrate without explicit user approval; the user performs the final push.
