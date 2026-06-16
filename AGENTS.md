# Trace Agent Guide

This file is the required entry point for agents working in this repository.

## Non-Negotiable Git Safety

- Never push without explicit user approval in the current conversation.
- Never commit directly on `main`.
- Create a feature branch before committing any repository change.
- Do not force push unless the user explicitly asks for force push and names the target branch.
- Do not rewrite history, reset shared branches, or discard user changes without explicit approval.
- The final push must be performed by the user. Agents may prepare changes, commits, and instructions, but must not run `git push`.
- Agents may run `git commit` after the user asks for commits to be created.
- Do not use `git add -A` or `git add .`; stage files explicitly by path.

These rules override all other workflow convenience.

## Project

- Product: `Trace`
- Platform: iOS
- Language: Swift
- UI stack: SwiftUI by default
- Minimum iOS version: iOS 17+
- Presentation architecture: MVVM
- IDE/build system: Xcode
- Default branch: `main`
- Remote: `https://github.com/seungchan2022/Trace.git`

## Rule Index

Read the relevant rule file before making changes:

- Git safety, branches, commits, and PRs: `docs/agent-rules/git.md`
- iOS and Swift rules: `docs/agent-rules/ios-swift.md`
- Architecture rules: `docs/agent-rules/architecture.md`
- Testing and verification rules: `docs/agent-rules/testing.md`
- Skill and plugin usage rules: `docs/agent-rules/skills.md`
- Current project decisions and defaults: `docs/agent-rules/project-decisions.md`

## Working Rules

- Do not start implementation from guesses. If product behavior is unclear, choose a conservative default and record it in `project-decisions.md`, or ask the user when the choice changes architecture, data ownership, privacy, or cost.
- Keep changes small and reviewable.
- Prefer native Apple APIs and SwiftUI patterns before adding dependencies.
- Before claiming work is complete, run the relevant verification command and report the exact command and result.
- For reusable mistakes or lessons found during review, run `ce-compound` or document the lesson so the same issue is not repeated.

## Required Workflow

1. Read this file and the relevant indexed rule files.
2. If on `main`, create or switch to a feature branch before editing or committing.
3. Clarify or record open product decisions before implementation.
4. Use Superpowers for brainstorming, planning, debugging, TDD, review, and verification when applicable.
5. Use Build iOS Apps skills for SwiftUI, simulator, Xcode, performance, and memory workflows.
6. Stage files explicitly by path and show the staged diff before asking for commit approval.
7. Commit only after the user asks for commits, with a message that follows `docs/agent-rules/git.md`.
8. Never push. The user performs the final push.
