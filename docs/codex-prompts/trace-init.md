# 세션 초기화 / 재개 (Codex 커스텀 프롬프트)

> 이 파일을 `~/.codex/prompts/trace-init.md`에 복사하면 Codex에서 `/trace-init`으로 호출된다.
> 목적: 세션을 차갑게 시작하지 않도록 **현재 상태를 복원**한다.
> 이 프롬프트는 **읽기 전용** — 파일을 수정하거나 커밋하지 않는다. 수집·보고·다음 액션 제안만 한다.

## 전제

- Codex는 세션 시작 시 `AGENTS.md`를 자동 로드한다. 따라서 init은 규칙을 다시 읽지 않고,
  AGENTS.md가 다루지 않는 **동적 상태(git·미결 결정·진행 중 작업)**만 복원한다.
- Trace의 상태는 KPI/마일스톤 파일이 아니라 **git + `docs/agent-rules/project-decisions.md`**에 있다.

## 수행 절차

### 1. 룰 인덱스 sanity 체크

`AGENTS.md`와 아래 파일들이 존재하는지만 확인 (내용 재독은 불필요):
`docs/agent-rules/`의 `git.md` · `ios-swift.md` · `architecture.md` · `testing.md` · `skills.md` · `project-decisions.md`.
빠진 파일이 있으면 보고한다.

### 2. Git 상태 복원

```bash
git branch --show-current
git status --short
git diff --stat
git log --oneline -5
```

- 현재 브랜치가 `main`이면 **경고**: 커밋 전 feature 브랜치를 파야 한다 (git.md 규칙).
- 미커밋 변경이 있으면 파일 목록과 규모를 요약한다.

### 3. 미결 결정 스캔

`docs/agent-rules/project-decisions.md`를 읽고:
- `Current Defaults`에서 **`undecided`**로 남은 항목 (예: Persistence, 그 외)
- `Decisions the User May Need to Make Later` 중 지금 작업과 관련돼 곧 정해야 할 것

→ 이걸 "막히기 전에 정해야 할 것" 목록으로 제시한다.

### 4. 진행 중 작업 감지 (resume)

- 브랜치명에서 작업 키워드 추출 (예: `feature/login-view` → 로그인 화면).
- 미커밋 파일 + 최근 변경된 `docs/superpowers/specs/*`, `docs/retro/*`를 연결해
  "직전에 뭘 하고 있었는지" 한 문장으로 재구성한다.

### 5. 훅 배선 점검

```bash
git config core.hooksPath
```

- 값이 `.githooks`가 아니면 **경고** + 활성화 명령 안내:
  ```bash
  git config core.hooksPath .githooks
  ```
  (이게 pre-commit/commit-msg/pre-push 가드를 켠다 — git.md 참고.)

### 6. 사용 가능한 도구 + 다음 스킬 제안

- 설치된 플러그인: Superpowers, Compound Engineering, Build iOS Apps, XcodeBuildMCP.
- 재개한 작업 성격에 맞는 **다음 스킬**을 제안한다:
  - 새 기능/제품 고민 → `superpowers:brainstorming`
  - 다단계 구현 → `superpowers:writing-plans`
  - 버그/이상동작 → `superpowers:systematic-debugging`
  - 완료 주장 전 → `superpowers:verification-before-completion`
  - iOS UI/시뮬레이터 작업 → Build iOS Apps 스킬 / `ios-debugger-agent`

### 7. 출력

아래 형식으로 요약한다:

```
# Trace 세션 상태

- 브랜치: {branch}  {main이면 ⚠️ feature 브랜치 필요}
- 변경: staged {n} / unstaged {n}
- 훅: {core.hooksPath 값 — .githooks면 ✅}
- 최근 커밋: {1줄}

# 재개 지점
- 진행 중: {브랜치+변경으로 재구성한 한 문장}
- 미결 결정: {project-decisions.md에서 곧 정할 것, 없으면 "없음"}
- 다음 액션 추천: {스킬/명령}
```

마지막에 한국어로 "이어서 진행할까요, 아니면 다른 작업을 시작할까요?"로 닫는다.
