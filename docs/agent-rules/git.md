# Git Rules

## Branches

- Default branch: `main`
- Feature branches should use `codex/` unless the user asks for another prefix.
- Keep one branch focused on one coherent change.

## Commits

Use short, imperative commit messages:

```text
Add iOS agent rule index
Configure SwiftUI project scaffolding
Fix simulator launch verification
```

Guidelines:

- First line: 50 characters is ideal, 72 maximum.
- Use English commit messages for consistency with tools and changelogs.
- Do not use vague messages such as `update`, `fix`, or `changes`.
- Commit only after verification appropriate to the change.
- Do not mix unrelated changes in one commit.

## Pull Requests

When creating a PR, include:

- Summary: what changed and why
- Test plan: exact commands or manual checks
- Risks: migrations, data loss, privacy, performance, or UI regressions
- Screenshots or simulator evidence for visible UI changes when practical

## History Safety

- Do not rewrite shared history without explicit user approval.
- Do not run destructive git commands such as `git reset --hard` unless explicitly requested.
- Never discard user changes without permission.
