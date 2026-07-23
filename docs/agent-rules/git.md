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
- Do not include tool names such as `codex` or `claude` in branch names. Name branches by the work, not the tool that did it.
- Make a feature branch before committing repository changes.
- Keep one branch focused on one coherent change.
- 한 작업 세션은 하나의 브랜치에서 진행하고, 그 안에서 커밋을 여러 번 나눠서 한다.
  커밋마다 새 브랜치를 만들지 않는다. 커밋이 늘어나는 것은 메시지로 구분하면 된다.

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

이 저장소는 두 레이어로 보호된다:

### Git Hooks (코드 품질 가드)

- `.githooks/pre-commit`: main 직접 커밋 차단, 시크릿 파일 감지, force unwrap/cast/try 차단, verification stamp 검증
- `.githooks/commit-msg`: 커밋 메시지 형식 검증, Co-Authored-By 차단
- `.githooks/pre-merge-commit`: 머지 커밋 차단 — --no-ff 시도 시 rebase + --ff-only 흐름을 안내하고 종료
- `.swiftlint.yml`: makes force unwrap/cast/try and implicitly unwrapped optionals lint errors

Enable hooks with:

```bash
git config core.hooksPath .githooks
```

### Agent Runtime Guards (에이전트 실행 차단)

공통 안전 원칙의 단일 소유자는 이 문서다. 도구별 런타임 문법은 달라도 Claude Code와 Codex는 아래 위험 명령을 각각 실행 단계에서 차단한다:

- Claude Code: `.claude/settings.json`의 `permissions.deny`
- Codex: `.codex/rules/trace-safety.rules`의 `forbidden` prefix rules

- `git push` — 모든 형태의 push 차단 (사용자가 터미널에서 직접 push)
- `git add -A` / `git add .` — 전체 스테이징 차단
- `--no-verify` — 훅 우회 차단
- `rm -rf` — 위험 삭제 차단
- `git reset --hard` — 작업물 손실 차단
- `.env` 편집 — 시크릿 파일 보호

Codex는 `.codex/config.toml`에서 `sandbox_mode = "workspace-write"`와 `approval_policy = "never"`를 사용한다. 따라서 일반 프로젝트 명령은 승인 없이 실행하고, 사용자 계정이 읽을 수 있는 외부 경로는 분석할 수 있다. 다만 워크스페이스 밖 쓰기·네트워크·보호 경로 쓰기는 자동 허용하지 않는다. `swiftlint`처럼 일반 작업 명령은 별도 allowlist 없이 이 범위에서 실행된다.

## Merge Strategy

- Do not commit directly on `main`.
- Work on a feature branch.
- Recommended local integration flow:
  1. `git switch <work-branch>`
  2. `git rebase main`
  3. `git switch main`
  4. `git merge --ff-only <work-branch>`
  5. `git branch -d <work-branch>`  ← 통합이 끝난 브랜치는 즉시 삭제한다.
- Do not rebase `main`; rebase the work branch onto `main`.
- Do not create merge commits for normal solo work; use fast-forward merge after rebase.
- Resolve conflicts file by file; do not use blanket `--ours` or `--theirs`.
- 통합 후 브랜치를 삭제하지 않으면, 끝난 작업이 그래프에 갈래로 남는다. 4단계까지만 하고 멈추지 말 것.
- 이미 다른 브랜치에 있는 작업을, 새 브랜치를 만들어 처음부터 다시 만들지 말 것.
  같은 작업은 기존 작업 브랜치를 이어가거나 `git rebase`로 갱신한다. 새 브랜치에 중복 커밋하면
  같은 변경이 두 갈래로 갈라지고, 한쪽이 버려진 채 남는다.

### 두 브랜치 동시 진행 시 그래프 꼬임 방지

독립적인 두 피처 브랜치를 같은 base에서 동시에 진행하면, 커밋 날짜가 겹쳐서 그래프에서 한 브랜치의 커밋이 다른 브랜치 커밋 사이에 시각적으로 끼어드는 현상이 생긴다.

**예방책 (우선순위 순):**

1. 브랜치 하나를 먼저 완전히 통합(FF 머지 + 삭제)한 뒤 다음 브랜치를 시작한다.
2. 불가피하게 동시 진행해야 한다면, 두 번째 브랜치는 첫 번째 브랜치 위에서 시작하거나 통합 전에 `git rebase <첫번째-브랜치>`로 선형화한다.
3. 두 브랜치 통합 순서: `git rebase <먼저-들어갈-브랜치>` → FF 머지 순으로 진행한다.

**수정 절차 (이미 꼬인 경우):**

```bash
# 두 번째 브랜치를 첫 번째 브랜치 위에 rebase
git checkout <second-branch>
git rebase <first-branch>

# 첫 번째 브랜치를 main에 통합 (second-branch도 포함됨)
git switch main
git merge --ff-only <second-branch>
git branch -d <first-branch> <second-branch>
```

### 통합 헬퍼

위 1~5단계를 한 번에 수행하는 스크립트:

```bash
scripts/trace-integrate.sh [work-branch]   # 인자 생략 시 현재 브랜치
```

rebase → `--ff-only` 통합 → 브랜치 삭제까지 자동으로 처리하며, 통합 루프를 항상 닫는다.
push는 수행하지 않는다(정책상 사용자가 직접). 충돌이 나면 해당 단계에서 멈추므로
파일 단위로 해결한 뒤 다시 실행한다.

### 커밋 헬퍼

분할 커밋을 만들 때, 커밋 직전 staged를 비우고 지정 경로만 stage·커밋하는 스크립트:

```bash
scripts/trace-commit.sh -m "tag: 제목

- 본문 1
- 본문 2
- 본문 3" -- <path>...
```

`git commit`이 staged 전체를 담는 탓에 이전 시도의 잔여가 엉뚱한 커밋에 섞이는 사고를 막는다.
시작 시 `git reset`으로 staged를 비우므로(워킹트리는 보존), 의도적으로 미리 stage해 둔 것이
있으면 그 경로도 함께 인자로 넘긴다. 본문은 비어 있지 않은 3~4줄이어야 한다(commit-msg 훅 요건).

## Verification Stamps

For Swift or Xcode project changes, `pre-commit` requires local verification stamps:

- `.git/trace-verify-build.ok`
- `.git/trace-verify-test.ok`
- `.git/trace-verify-lint.ok`

These stamps represent build, test, and lint passing in the current working tree. After the Xcode project exists, use the commands in `docs/agent-rules/testing.md` and update the stamps only after each command succeeds.
