# Git Rules

## Mandatory Safety Rules

- Do not push unless the user explicitly approves that exact push in the current conversation.
- Do not commit on `main`.
- Do not force push unless the user explicitly approves force push and names the branch.
- Do not run destructive git commands such as `git reset --hard`, branch deletion, or history rewrite unless explicitly requested.
- Do not discard user changes.

## Branches

- Default branch: `main`
- Feature branches should use `codex/` unless the user asks for another prefix.
- Make a feature branch before committing repository changes.
- Keep one branch focused on one coherent change.

## Commits

Use short, imperative English commit messages:

```text
Add iOS agent rule index
Configure SwiftUI project scaffolding
Fix simulator launch verification
```

Guidelines:

- First line: 50 characters is ideal, 72 maximum.
- Do not use vague messages such as `update`, `fix`, or `changes`.
- Commit only after verification appropriate to the change.
- Do not mix unrelated changes in one commit.

## Pull Requests

When creating a PR, include:

- Summary: what changed and why
- Test plan: exact commands or manual checks
- Risks: migrations, data loss, privacy, performance, or UI regressions
- Screenshots or simulator evidence for visible UI changes when practical

## Local Guard

This repository uses a local pre-commit hook in `.githooks/pre-commit` to block commits on `main`.

Enable it with:

```bash
git config core.hooksPath .githooks
```
