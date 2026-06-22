# Trace Agent Guide

This file is the required entry point for agents working in this repository.

## Non-Negotiable Git Safety

These hard-stops apply even before you open `docs/agent-rules/git.md`:

- Never push. The final push is the user's; agents must not run `git push`.
- Never commit directly on `main`; create a feature branch first.
- No force push, history rewrite, or `git reset --hard` on shared branches without explicit, branch-named approval.
- Stage files explicitly by path; never `git add -A` or `git add .`.

Full git rules — commit format, integration/merge flow, branch hygiene — live in `docs/agent-rules/git.md`. These hard-stops override all other workflow convenience.

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

- Work units (MVP, milestone), top-down flow, review checkpoints, step visibility, archiving, and study: `docs/agent-rules/workflow.md`
- Git safety, branches, commits, and PRs: `docs/agent-rules/git.md`
- iOS and Swift rules: `docs/agent-rules/ios-swift.md`
- Architecture rules: `docs/agent-rules/architecture.md`
- Testing and verification rules: `docs/agent-rules/testing.md`
- Skill and plugin usage rules: `docs/agent-rules/skills.md`
- Current project decisions and defaults: `docs/agent-rules/project-decisions.md`
- Documentation and rule-file authoring: `docs/agent-rules/authoring.md`
- Working across Codex and Claude Code (handoff, shared vs tool-specific setup): `docs/agent-rules/dual-tool.md`
- Documented solutions and reusable learnings (bugs, design patterns, workflow gotchas): `docs/solutions/` — organized by category with YAML frontmatter (`module`, `tags`, `problem_type`); relevant when implementing or debugging in a documented area, maintained via `ce-compound`.

## Working Rules

- Do not start implementation from guesses. If product behavior is unclear, choose a conservative default and record it in `project-decisions.md`, or ask the user when the choice changes architecture, data ownership, privacy, or cost.
- Keep changes small and reviewable.
- 한 작업 세션은 하나의 브랜치에서 진행하고(커밋은 여러 번 가능), 통합이 끝난 브랜치는 즉시 삭제한다. 같은 작업을 새 브랜치로 다시 만들지 않는다. 상세는 `docs/agent-rules/git.md`.
- Prefer native Apple APIs and SwiftUI patterns before adding dependencies.
- Before claiming work is complete, run the relevant verification command and report the exact command and result.
- For reusable mistakes or lessons found during review, run `ce-compound` or document the lesson so the same issue is not repeated.
- Before creating or editing any rule or documentation file under `docs/agent-rules/`, read `docs/agent-rules/authoring.md` and follow its structure (lean entry point, one rule one home, index over duplication).

## Required Workflow

1. Read this file and the relevant indexed rule files.
2. If on `main`, create or switch to a feature branch before editing or committing.
3. Clarify or record open product decisions before implementation.
4. Use Superpowers for brainstorming, planning, debugging, TDD, review, and verification when applicable.
5. Use Build iOS Apps skills for SwiftUI, simulator, Xcode, performance, and memory workflows.
6. Stage files explicitly by path.
7. Commit only after the user asks for commits, with a message that follows `docs/agent-rules/git.md`.
8. Never push. The user performs the final push.
