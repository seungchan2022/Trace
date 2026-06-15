# Trace Agent Guide

This file is the entry point for agents working in this repository.
Keep it short. Put detailed rules in `docs/agent-rules/` and link them here.

## Project

- Product: `Trace`
- Platform: iOS
- Language: Swift
- UI stack: SwiftUI by default
- IDE/build system: Xcode
- Default branch: `main`
- Remote: `https://github.com/seungchan2022/Trace.git`

## Rule Index

Read the relevant rule file before making changes:

- iOS and Swift rules: `docs/agent-rules/ios-swift.md`
- Architecture rules: `docs/agent-rules/architecture.md`
- Git, branch, commit, and PR rules: `docs/agent-rules/git.md`
- Testing and verification rules: `docs/agent-rules/testing.md`
- Skill and plugin usage rules: `docs/agent-rules/skills.md`
- Current project decisions and defaults: `docs/agent-rules/project-decisions.md`

## Working Rules

- Do not start implementation from guesses. If product behavior is unclear, choose a conservative default and record it in `project-decisions.md`, or ask the user when the choice changes architecture, data ownership, privacy, or cost.
- Keep changes small and reviewable. Avoid broad refactors unless they directly support the current task.
- Prefer native Apple APIs and SwiftUI patterns before adding dependencies.
- Before claiming work is complete, run the relevant verification command and report the exact command and result.
- For reusable mistakes or lessons found during review, run `ce-compound` or document the lesson so the same issue is not repeated.

## Required Workflow

1. Read this file and the relevant indexed rule files.
2. Clarify or record open product decisions before implementation.
3. Use Superpowers for brainstorming, planning, debugging, TDD, review, and verification when applicable.
4. Use Build iOS Apps skills for SwiftUI, simulator, Xcode, performance, and memory workflows.
5. Commit only coherent changes with a message that follows `docs/agent-rules/git.md`.
