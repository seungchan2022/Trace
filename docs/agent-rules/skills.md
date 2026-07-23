# Skill and Plugin Rules

## Installed Plugins

- Superpowers: planning, TDD, debugging, review, verification workflows
- Compound Engineering: code review, documentation of reusable learnings, workflow utilities
- Build iOS Apps: SwiftUI, Xcode, Simulator, performance, memory workflows
- GitHub: repository, issue, PR, and review workflows when needed
- XcodeBuildMCP: configured globally as `XcodeBuildMCP` for simulator, UI automation, debugging, and logging
- Playwright MCP: configured globally for browser-backed checks when needed
- Sequential Thinking MCP: configured globally for structured reasoning support when needed

## Trace-Specific Shared Skills

- `trace-init`: restore Trace session state at the start of a new chat.
- `daily-retro`: summarize the day and capture lessons or follow-up work.
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
- **Compound step (required at the end of every execute-review cycle).** Immediately after `superpowers:requesting-code-review` feedback is resolved and verified, and as the closing step of `superpowers:finishing-a-development-branch`, check whether the execute-review cycle exposed any mistake, repeated issue, surprising constraint, or reusable lesson. If yes, run `ce-compound` (use `ce-compound mode:headless` for skill-to-skill/automated runs) before moving on or marking the checkpoint complete. Capture: what happened, why, what signal would have caught it earlier, and the concrete rule/check/pattern to reuse. Do not use it for generic summaries.
  - This rule supplies the integration that Codex's `openai-curated` superpowers has built in but obra superpowers (v6.x, installed on Claude Code) does not call automatically. Keep it in the rules, not in the plugin's SKILL.md, so it survives plugin updates and applies in both tools.
- Use `ce-compound` when a workflow rule is updated because of an agent mistake.

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
