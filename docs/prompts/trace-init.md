# 세션 초기화 / 재개 (공용 프롬프트)

> 이 절차는 Codex와 Claude Code **양쪽에서 `/trace-init`으로 호출**된다.
> - Codex: 이 파일을 `~/.codex/prompts/trace-init.md`에 복사해 등록 (`docs/prompts/setup-codex.md` 참고).
> - Claude Code: `.claude/commands/trace-init.md`가 이 파일을 가리키므로 별도 복사 없이 인식된다.
> 목적: 세션을 차갑게 시작하지 않도록 **현재 상태를 복원**한다. 도구를 바꿔 이어받는 경우에도 동일하게 동작한다.
> 이 프롬프트는 **읽기 전용** — 파일을 수정하거나 커밋하지 않는다. 수집·보고·다음 액션 제안만 한다.

## 전제

- 두 도구 모두 세션 시작 시 진입 파일을 자동 로드한다 (Codex `AGENTS.md`, Claude Code `CLAUDE.md` → `AGENTS.md` 심볼릭).
  따라서 init은 규칙을 다시 읽지 않고, 진입 파일이 다루지 않는 **동적 상태(git·미결 결정·진행 중 작업)**만 복원한다.
- Trace의 상태는 KPI/마일스톤 파일이 아니라 **git + `docs/agent-rules/project-decisions.md` + 진행 중 플랜의 체크박스**에 있다.
  도구별 메모리(Claude `~/.claude/.../memory/`, Codex `~/.codex/memories`)는 **상대 도구가 못 보므로 핸드오프 상태로 신뢰하지 않는다.**

## 수행 절차

### 1. 룰 인덱스 sanity 체크

진입 파일(`AGENTS.md` 및 그를 가리키는 `CLAUDE.md`)과 아래 파일들이 존재하는지만 확인 (내용 재독은 불필요):
`docs/agent-rules/`의 `git.md` · `ios-swift.md` · `architecture.md` · `testing.md` · `skills.md` · `project-decisions.md` · `dual-tool.md`.
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

### 4. 진행 중 작업 감지 (resume) — 핸드오프의 핵심

- 브랜치명에서 작업 키워드 추출 (예: `feature/login-view` → 로그인 화면).
- **진행 중 플랜의 체크박스를 읽는다**: `docs/superpowers/plans/*.md`에서 `- [x]`(완료)와 `- [ ]`(미완료)를 세어
  "Task N까지 완료, 다음은 Task N+1" 형태로 복원한다. 이게 도구를 바꿔 이어받을 때의 **1차 인수인계 채널**이다.
- ⚠️ 코드는 작성됐는데 체크박스가 안 켜져 있는 등 **플랜과 워킹 트리가 어긋나면 경고**한다 (상대 도구가 장님 상태로 재시작하는 원인).
- 미커밋 파일 + 최근 변경된 `docs/superpowers/specs/*`, `history/*`를 연결해
  "직전에 뭘 하고 있었는지" 한 문장으로 재구성한다.

### 5. 훅 배선 점검

```bash
git config core.hooksPath
```

- 값이 `.githooks`가 아니면 **경고** + 활성화 명령 안내:
  ```bash
  git config core.hooksPath .githooks
  ```
  (이게 pre-commit/commit-msg/pre-push 가드를 켠다 — git.md 참고. 도구와 무관하게 리포 단위로 공유된다.)

### 6. 백로그 확인 + 사용 가능한 도구 + 다음 단계 제안

- **먼저 `docs/backlog.md`의 open 항목을 확인**한다. 새 슬라이스는 backlog에서 다룰 항목을 고르는 것으로 시작한다(작고 명확하면 spec/plan 바로, 결정·모호하면 brainstorm). 단 강제 큐가 아니라 **메뉴** — 사용자가 새 기능을 먼저 하자고 하면 그쪽으로 간다. backlog가 없거나 비어 있으면 넘어간다.
- 설치된 워크플로: Superpowers(브레인스토밍·플랜·TDD·디버깅·리뷰·검증), Compound Engineering, Build iOS Apps, XcodeBuildMCP.
- 호출 방식은 도구마다 다를 수 있으나(스킬/프롬프트/MCP), **개념은 동일**하다. 재개한 작업 성격에 맞는 다음 단계를 제안한다:
  - 새 기능/제품 고민 → 브레인스토밍 (`superpowers:brainstorming` 등)
  - 다단계 구현 → 플랜 작성 (`superpowers:writing-plans` 등)
  - 버그/이상동작 → 체계적 디버깅 (`superpowers:systematic-debugging` 등)
  - 완료 주장 전 → 완료 전 검증 (`superpowers:verification-before-completion` 등)
  - iOS UI/시뮬레이터 작업 → Build iOS Apps 스킬 / `ios-debugger-agent` / XcodeBuildMCP

### 7. 출력

아래 형식으로 요약한다:

```
# Trace 세션 상태

- 브랜치: {branch}  {main이면 ⚠️ feature 브랜치 필요}
- 변경: staged {n} / unstaged {n}
- 훅: {core.hooksPath 값 — .githooks면 ✅}
- 최근 커밋: {1줄}

# 재개 지점
- 진행 중: {브랜치+변경+플랜 체크박스로 재구성한 한 문장}
- 플랜 진행률: {Task N/M 완료, 다음 단계 / 플랜 없으면 "없음", 플랜↔코드 불일치 시 ⚠️}
- 미결 결정: {project-decisions.md에서 곧 정할 것, 없으면 "없음"}
- 백로그: {docs/backlog.md open 항목 수 + 핵심 1~2개, 없으면 "없음"}
- 다음 액션 추천: {스킬/명령}
```

마지막에 한국어로 "이어서 진행할까요, 아니면 다른 작업을 시작할까요?"로 닫는다.
