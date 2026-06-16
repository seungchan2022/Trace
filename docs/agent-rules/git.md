# Git Rules

## Mandatory Safety Rules

- Do not push unless the user explicitly approves that exact push in the current conversation.
- The final push must be performed by the user. Agents must not run `git push`, even after preparing a branch.
- Do not commit on `main`.
- Agents may run `git commit` after the user asks for commits to be created.
- Agents may perform local fast-forward integration into `main` only when the user explicitly asks for it.
- Do not force push unless the user explicitly approves force push and names the branch.
- Do not use `git add -A` or `git add .`; stage files explicitly by path.
- Do not run destructive git commands such as `git reset --hard`, branch deletion, or history rewrite unless explicitly requested.
- Do not discard user changes.
- Do not include `Co-Authored-By:` lines in commit messages.

## Branches

- Default branch: `main`
- Feature branches should use `<type>/<short-description-kebab-case>`.
- Do not include `codex` in branch names.
- Make a feature branch before committing repository changes.
- Keep one branch focused on one coherent change.

Allowed branch prefixes:

| Prefix | Purpose | Example |
|---|---|---|
| `feature/` | New feature | `feature/login-view` |
| `fix/` | Bug fix | `fix/feed-crash` |
| `refactor/` | Refactor | `refactor/extract-service` |
| `chore/` | Setup and maintenance | `chore/bump-deps` |
| `docs/` | Documentation | `docs/agent-rules` |
| `test/` | Test-only changes | `test/auth-service` |

## Commits

Use this format:

```text
tag: 한국어 제목

변경 이유와 범위를 설명하는 한국어 본문 3~4줄.
무엇을 왜 바꿨는지, 검증이나 위험 요소가 있으면 함께 적는다.
```

Guidelines:

- First line: 50 characters is ideal, 72 maximum.
- Do not use vague messages such as `update`, `fix`, or `changes`.
- Use one of these tags: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `style`, `perf`.
- The tag stays in English; the title and body should be written in Korean.
- Do not end the title with a period.
- Do not use `Co-Authored-By:`.
- Commit only after verification appropriate to the change.
- Do not mix unrelated changes in one commit.

Example:

```text
feat: 로그인 화면 추가

- SwiftUI 기반 로그인 화면을 추가한다
- 인증 상태는 ViewModel을 통해 바인딩한다
- 토큰 저장은 Keychain 기반 서비스와 연결한다
```

## Before Commit

All three must pass before a commit is allowed:

1. Build passes.
2. Tests pass.
3. Lint passes.

Checklist:

- [ ] Build passes (`xcodebuild build` or package equivalent)
- [ ] Tests pass (`xcodebuild test` or `swift test`)
- [ ] Lint passes (`swiftlint`)
- [ ] Commit message follows the required format
- [ ] Change is one logical unit
- [ ] No secrets are staged
- [ ] No unintended files are staged

## Pull Requests

PR rules are optional while this is a solo project. Add formal PR/review rules when collaboration starts.

When creating a PR later, include:

- Summary: what changed and why
- Test plan: exact commands or manual checks
- Risks: migrations, data loss, privacy, performance, or UI regressions
- Screenshots or simulator evidence for visible UI changes when practical

## Local Guard

This repository uses local hooks:

- `.githooks/pre-commit`: blocks commits on `main`, scans staged files for common secrets and unsafe Swift patterns
- `.githooks/commit-msg`: blocks invalid commit messages and `Co-Authored-By:`
- `.githooks/pre-push`: 기본 차단, 사용자는 `ALLOW_PUSH=1 git push ...`로 수동 push 가능
- `.swiftlint.yml`: makes force unwrap/cast/try and implicitly unwrapped optionals lint errors

Enable it with:

```bash
git config core.hooksPath .githooks
```

## Merge Strategy

- Do not commit directly on `main`.
- Work on a feature branch.
- Recommended local integration flow:
  1. `git switch <work-branch>`
  2. `git rebase main`
  3. `git switch main`
  4. `git merge --ff-only <work-branch>`
- Do not rebase `main`; rebase the work branch onto `main`.
- Do not create merge commits for normal solo work; use fast-forward merge after rebase.
- Resolve conflicts file by file; do not use blanket `--ours` or `--theirs`.

## Verification Stamps

For Swift or Xcode project changes, `pre-commit` requires local verification stamps:

- `.git/trace-verify-build.ok`
- `.git/trace-verify-test.ok`
- `.git/trace-verify-lint.ok`

These stamps represent build, test, and lint passing in the current working tree. After the Xcode project exists, use the commands in `docs/agent-rules/testing.md` and update the stamps only after each command succeeds.
