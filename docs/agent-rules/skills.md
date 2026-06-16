# Skill and Plugin Rules

## Installed Plugins

- Superpowers: planning, TDD, debugging, review, verification workflows
- Compound Engineering: code review, documentation of reusable learnings, workflow utilities
- Build iOS Apps: SwiftUI, Xcode, Simulator, performance, memory workflows
- GitHub: repository, issue, PR, and review workflows when needed
- XcodeBuildMCP: configured globally as `XcodeBuildMCP` for simulator, UI automation, debugging, and logging
- Playwright MCP: configured globally for browser-backed checks when needed
- Sequential Thinking MCP: configured globally for structured reasoning support when needed

## Custom Prompts

- `/trace-init`: restore Trace session state at the start of a new chat.
- `/daily-retro`: summarize the day and capture lessons or follow-up work.

These are Codex custom prompts, not skills. They are registered under `~/.codex/prompts/` and may require a Codex restart or new session after edits.

## Required Skill Use

- Use `superpowers:brainstorming` before creative product or feature work.
- Use `superpowers:writing-plans` before multi-step implementation.
- Use `superpowers:test-driven-development` for bug fixes and behavior changes where tests are practical.
- Use `superpowers:systematic-debugging` before fixing bugs or unexpected behavior.
- Use `superpowers:verification-before-completion` before claiming completion.
- Use `superpowers:requesting-code-review` for major work and before merge.
- Use `ce-compound` after review when the work exposed a reusable mistake, lesson, or pattern.
- Use `ce-compound` when a workflow rule is updated because of an agent mistake.

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
- The server is configured in `~/.codex/config.toml` as:
  - command: `npx`
  - args: `-y xcodebuildmcp@latest mcp`
  - workflows: `simulator,ui-automation,debugging,logging`
- Restart Codex after MCP config changes so the server tools become available.

## Git Safety Integration

- Skills and plugins never override the repository Git safety rules in `docs/agent-rules/git.md`.
- Even if a skill suggests pushing, creating a PR, or finishing a branch, do not push or integrate without explicit user approval; the user performs the final push.
