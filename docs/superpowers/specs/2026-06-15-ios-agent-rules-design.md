# iOS Agent Rules Design

## Goal

Prepare the `Trace` repository for Swift iOS app development before creating the Xcode project. The setup must protect the user from accidental git changes by agents.

## Design

Use `AGENTS.md` as the short entry point and keep detailed rules under `docs/agent-rules/`.

Git safety is the first rule:

- no agent-run push; the user performs the final push manually
- no commit directly on `main`
- commits may be created by the agent after the user asks for commits
- no force push without explicit branch-specific approval
- no destructive git operation without explicit approval
- no `git add -A` or `git add .`

Add `.githooks/pre-commit`, `.githooks/commit-msg`, and `.githooks/pre-push`, then configure `core.hooksPath`.

The iOS rules target iOS 17+, SwiftUI, MVVM, Clean Architecture boundaries, future modularization readiness, protocol-based dependency injection, Codable data models, Swift modern concurrency, Keychain for sensitive data, and 90% coverage.

## Verification

- confirm the hook blocks commits on `main`
- confirm pre-push blocks agent-run pushes
- confirm commit-msg blocks invalid messages and `Co-Authored-By:`
- confirm rule files exist
- confirm git status before any push
