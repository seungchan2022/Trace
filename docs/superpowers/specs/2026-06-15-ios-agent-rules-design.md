# iOS Agent Rules Design

## Goal

Prepare the `Trace` repository for Swift iOS app development before creating the Xcode project. The setup must protect the user from accidental git changes by agents.

## Design

Use `AGENTS.md` as the short entry point and keep detailed rules under `docs/agent-rules/`.

Git safety is the first rule:

- no push without explicit user approval
- no commit directly on `main`
- no force push without explicit branch-specific approval
- no destructive git operation without explicit approval

Add `.githooks/pre-commit` and configure `core.hooksPath` so local commits on `main` are blocked by git itself.

## Verification

- confirm the hook blocks commits on `main`
- confirm rule files exist
- confirm git status before any push
