---
name: trace-init
description: 새 Trace 세션을 시작하거나 재개할 때 현재 브랜치, 활성 플랜, 미결 결정, MVP 상태, 다음 작업을 복원해야 하는 경우 사용한다.
---

# Trace 세션 초기화 / 재개

> 이 스킬은 Claude Code와 Codex 양쪽에서 같은 본문을 사용한다.
> - Claude Code: `/trace-init`
> - Codex: `$trace-init`
>
> 목적: 세션을 차갑게 시작하지 않도록 **현재 상태를 복원**한다. 도구를 바꿔 이어받는 경우에도 동일하게 동작한다.
> 이 스킬은 **읽기 전용** — 파일을 수정하거나 커밋하지 않는다. 수집·보고·다음 액션 제안만 한다.
>
> 🔴 **파일을 읽을 때 줄 번호로 자르지 않는다 — 절 단위(`sed -n '/^## 머리/,/^## 다음/p'`)나
> `grep`을 쓴다.** 줄 번호는 파일이 자라면 그만큼 쓸데없는 것을 읽고, **정리를 해도 다른 내용이
> 그 자리를 채운다**(2026-08-31: 끝난 항목을 아래로 내렸더니 `+25p`가 그 자리를 새로 읽어
> 오히려 늘었다). 새 명령을 더할 때도 이 규칙이 걸린다.

## 전제

- 두 도구 모두 세션 시작 시 진입 파일을 자동 로드한다 (Codex `AGENTS.md`, Claude Code `CLAUDE.md` → `AGENTS.md` 심볼릭).
  따라서 init은 규칙을 다시 읽지 않고, 진입 파일이 다루지 않는 **동적 상태(git·미결 결정·진행 중 작업)**만 복원한다.
- Trace의 상태는 frank식 KPI/상태머신 파일이 아니라 **git + `docs/current-mvp.md`(사용자용 현황판) + `docs/agent-rules/project-decisions.md` + `docs/roadmap.md`(MVP/마일스톤 위치) + 진행 중 플랜의 체크박스**에 있다.
  도구별 메모리(Claude `~/.claude/.../memory/`, Codex `~/.codex/memories`)는 **상대 도구가 못 보므로 핸드오프 상태로 신뢰하지 않는다.**

## 수행 절차

### 1. 룰 인덱스 sanity 체크

진입 파일(`AGENTS.md` 및 그를 가리키는 `CLAUDE.md`)과 아래 파일들이 존재하는지만 확인 (내용 재독은 불필요):
`docs/agent-rules/`의 `workflow.md` · `git.md` · `ios-swift.md` · `architecture.md` · `testing.md` · `skills.md` · `project-decisions.md` · `dual-tool.md`.
빠진 파일이 있으면 보고한다.

### 2. Git 상태 복원

```bash
git branch --show-current
git status --short
git diff --stat
git log --oneline -5
```

- 현재 브랜치가 `main`이면 **경고**: 커밋 전 feature 브랜치를 파야 한다 (`git.md` 규칙).
- 미커밋 변경이 있으면 파일 목록과 규모를 요약한다.

### 3. 미결 결정 스캔

🔴 **통째로 읽지 않는다** — 이 파일은 142줄인데 **52KB**다(줄이 길다). 필요한 것은 두 곳뿐이다.

```bash
grep -n -i "undecided" docs/agent-rules/project-decisions.md          # 없으면 미결 없음
sed -n '/^## Decisions the User May Need/,/^## Resolved/p' docs/agent-rules/project-decisions.md
```

- `Current Defaults`에서 **`undecided`**로 남은 항목 (예: Persistence, 그 외)
- `Decisions the User May Need to Make Later` 중 지금 작업과 관련돼 곧 정해야 할 것
- 🔴 **줄 번호(`+25p`)로 자르지 않는다**(2026-08-31 개정). 정해진 항목을 아래 `## Resolved`로
  내리면 그 자리를 Resolved가 채워서 **읽는 양이 오히려 늘었다.** 절 단위로 뽑으면
  Resolved는 안 읽힌다 — `roadmap.md`에서와 같은 처방이다.

→ 이걸 "막히기 전에 정해야 할 것" 목록으로 제시한다.

### 4. 진행 중 작업 감지 (resume) — 핸드오프의 핵심

- **먼저 `docs/current-mvp.md`를 읽는다.** 이 파일에서 현재 MVP, 현재 단계, 사용자가 결정한 것,
  아직 확인할 것, 다음 사용자 확인을 복원한다. 문서 역할과 stale 판정 기준은
  `docs/agent-rules/product-visibility.md`를 따른다.
  - `docs/roadmap.md`의 진행 중 MVP·마일스톤과 이름이나 상태가 다르면 **현황판 stale**로 보고한다.
  - 이 스킬은 읽기 전용이므로 고치지 않는다. 어떤 정본과 어긋났는지와 갱신 필요만 알린다.
  - 진행 중인 MVP가 없으면 `없음`으로 표시하고, 현황판의 마지막 완료 MVP와 backlog 링크를 따른다.
- 브랜치명에서 작업 키워드 추출 (예: `feature/login-view` → 로그인 화면).
- **진행 중 플랜의 체크박스를 읽는다**: `docs/superpowers/plans/*.md`에서 `- [x]`(완료)와 `- [ ]`(미완료)를 세어 "Task N까지 완료, 다음은 Task N+1" 형태로 복원한다. 이게 도구를 바꿔 이어받을 때의 **1차 인수인계 채널**이다.
- ⚠️ 코드는 작성됐는데 체크박스가 안 켜져 있는 등 **플랜과 워킹 트리가 어긋나면 경고**한다 (상대 도구가 장님 상태로 재시작하는 원인).
- 🔴 **선행 작업 표시(`🔴`)를 찾는다.** 플랜·진행 상태 파일 안에 `🔴`로 시작하는 줄이 있으면
  그것은 **"다음 세션이 본 작업을 시작하기 전에 먼저 할 일"**이다. 앞 세션이 못 끝내고 넘긴
  것이라 **본문에 묻히면 그대로 유실된다.** 발견하면:
  - **재개 지점 맨 앞에 싣는다** — 무엇을·왜 밀렸는지·실패하면 어떻게 할지를 그 줄에서 그대로 옮긴다.
  - **"지금 할 수 있는 것" 목록의 A 항목**으로 올린다(다른 선택지보다 위).
  - 여러 개면 전부 싣는다. **요약하지 말고 원문을 살린다** — 앞 세션이 좁혀둔 확인 대상이
    거기 적혀 있고, 그게 이 표시의 존재 이유다.
- 📚 **학습(`trace-study`) 진행 상태는 활성 상태일 때만 복원한다.** 먼저
  `docs/superpowers/plans/2026-07-31-trace-study-catchup.md`의 `상태:`를 확인한다.
  `중단`이면 체크박스와 착수 메모를 읽거나 활성 작업·다음 선택지로 제시하지 않는다.
  사용자가 `trace-study`를 명시적으로 호출한 경우에만 보존된 재개 지점을 사용한다.
  활성 상태라면 해당 파일의
  체크박스가 그 채널이다 — "청크 N까지 완료, 다음은 청크 N+1" 형태로 보고하고, **그 청크 줄에 달린
  착수 메모(`🔑`·`⚠️`·`📌`)가 있으면 함께 싣는다.** 학습은 MVP가 아니라서 `roadmap.md`에 안 잡히고,
  이 파일을 안 보면 **"진행 중인 것 없음"으로 잘못 보고된다.**
  산출물은 `docs/study/<번호>-<슬러그>/` 폴더이고 그 안에 `note.html`(사용자)과 `agent-log.md`(에이전트)가 있다.
  - ⚙️ **진행 이력은 현재 청크·현재 파트 것만 이 파일에 남긴다**(2026-08-25 정리). 완료된 파트의
    이력은 그 청크 `agent-log.md`의 「📦 진행 요약 아카이브」로 밀어낸다. **이 파일이 341줄까지
    자란 원인이 그것이었고**(청크 3 줄 하나가 297줄), init이 매 세션 그걸 다 읽고 있었다.
  - ⚠️ **학습 재개를 안내할 때 `trace-study`의 파일 구성을 함께 알린다**(2026-08-25 분리).
    `SKILL.md`에는 목표 깊이·절대 원칙·절차 뼈대만 있고, **청크를 열 때 `session-cycle.md` ·
    노트를 쓸 때 `note-format.md` · 저장할 때 `saving.md`**를 읽는다. 옛 구성으로 열면 절차를 놓친다.
- 미커밋 파일 + 최근 변경된 `docs/superpowers/specs/*`, `history/*`를 연결해 "직전에 뭘 하고 있었는지" 한 문장으로 재구성한다.
- **MVP/마일스톤 위치 복원**: `docs/roadmap.md`에서 현재 어느 MVP의 어느 마일스톤 단계인지 (진행 중/완료/아카이빙 대기) 파악한다. 마일스톤이 전부 `[x]`인데 아카이빙 안 된 MVP가 있으면 "**trace-archive 대기**"로 보고한다. 단위·흐름 규칙은 `docs/agent-rules/workflow.md`.
  - 🔴 **줄 번호로 자르지 않는다 — 절 단위로 뽑는다**(2026-08-31 개정). 파일은 270줄에 **36KB**이고
    뒤쪽 대부분이 **완료·아카이빙된 기록**이라, 필요한 것은 `## 진행 중 / 예정` 절뿐이다:

    ```bash
    sed -n '/^## 진행 중/,/^## 완료/p' docs/roadmap.md
    ```

    **옛 명령 `sed -n '1,60p'`은 46줄이 「2026-08-04에 끝난 정비 사이클 상세」였다** — 줄 번호로
    자르면 완료 기록이 앞에 쌓일 때마다 읽는 양이 늘고, *"진행 중인 MVP 없음이면 그 아래는 볼
    필요가 없다"*고 적어 둬도 이미 읽은 뒤가 된다. 절 단위면 그 절이 길어져도 잘리지 않는다.

### 5. 훅 배선 점검

```bash
git config core.hooksPath
```

- 값이 `.githooks`가 아니면 **경고** + 활성화 명령 안내:

  ```bash
  git config core.hooksPath .githooks
  ```

  (이게 pre-commit/commit-msg 가드를 켠다 — `git.md` 참고. push 차단은 `.claude/settings.json` deny로 처리.)

### 5.5 지금 할 수 있는 것 (선택지 구성)

진행 중 MVP가 있으면, **다음에 착수 가능한 항목을 선택지로 제시**한다. 한 줄 추천이 아니라
목록이어야 한다 — 문서 세션은 사이클 하나가 끝나면 닫으므로(`workflow.md` 세션 경계),
새 세션은 "문서를 더 쓸지 / 구현으로 갈지"를 매번 고른다.

재료는 두 곳에서 읽는다:

1. **킥오프 문서의 마일스톤 표** (`docs/superpowers/specs/*-kickoff-design.md`) — 각 마일스톤의
   **종류**(새 기능 / 작은 기능 / 정비)와 **앞 결과 의존 여부**.
2. **문서 존재 여부** — 그 마일스톤의 설계·계획 문서가 `docs/superpowers/specs|plans/`에 있나.

조합해서 이렇게 낸다:

```
# 지금 할 수 있는 것

A. 사이클 '<슬러그>' 구현        — 문서 준비됨 (설계·계획 있음)
B. 사이클 '<슬러그>' 문서 작성    — 독립적이라 지금 가능
C. 사이클 '<슬러그>' 목록·분류    — 정비. 설계 문서 불필요

⚠️ 사이클 '<슬러그>'는 아직 불가 — '<앞 마일스톤>'의 실기기 QA 결과가 필요
```

- **킥오프 표가 없으면** "종류·의존 정보 없음"으로 보고하고, 기존 방식대로 다음 액션 하나만
  추천한다. 표가 없는 MVP를 억지로 분류하지 않는다(MVP17 이전 킥오프 문서에는 이 표가 없다).
- 진행 중 MVP가 없으면 이 절을 건너뛰고 6항의 백로그 확인으로 간다.

### 6. 백로그 확인 + 사용 가능한 도구 + 다음 단계 제안

- **먼저 `docs/backlog.md`의 open 항목을 확인**한다. 새 마일스톤은 backlog에서 다룰 항목을 고르는 것으로 시작한다(작고 명확하면 spec/plan 바로, 결정·모호하면 brainstorm). backlog 항목은 마일스톤 후보이며, 묶어서 MVP를 구성하거나 기존 MVP에 편입한다(`docs/agent-rules/workflow.md`). 단 강제 큐가 아니라 **메뉴** — 사용자가 새 기능을 먼저 하자고 하면 그쪽으로 간다. backlog가 없거나 비어 있으면 넘어간다.
  - 🔴 **init이 읽는 파일 중 가장 크다 — 305줄에 `136KB`다.** 항목 하나가 한 줄인데 그 한 줄에
    *what · 영향 · 미검증 · 확인 방법 · why deferred · trigger*가 전부 들어 있기 때문이다.
    **통째로 읽으면 안 된다.** 건수와 제목만 뽑는다:

    ```bash
    grep -c '^- \[ \].*`open`$' docs/backlog.md              # open 건수
    grep -o '^- \[ \] \*\*[^*]*\*\*' docs/backlog.md | head -8   # 제목만
    ```

    ⚠️ **건수를 셀 때 상태 범례 줄과 본문 언급이 섞이지 않게 한다** — `grep -c '`open`'`으로 세면
    머리말의 범례와 다른 항목의 *관련:* 주석까지 잡혀 실제보다 많이 나온다(2026-08-24에 55 대 50으로 어긋났다).
  - 사용자가 특정 항목을 고르면 **그때 그 줄만** `grep -n`으로 찾아 편다.
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

# 현재 MVP
- MVP: {current-mvp.md 기준 이름 / 없으면 "없음"}
- 현재 단계: {기획 / 구현 / 실기기 QA / 완료 대기 / 없음}
- 사용자가 결정할 것: {항목 / 없음}
- 다음 사용자 확인: {항목 / 없음}
- 현황판: docs/current-mvp.md {roadmap과 다르면 ⚠️ stale}

# 재개 지점
- 진행 중: {브랜치+변경+플랜 체크박스로 재구성한 한 문장}
- 플랜 진행률: {Task N/M 완료, 다음 단계 / 플랜 없으면 "없음", 플랜↔코드 불일치 시 ⚠️}
- MVP/마일스톤: {roadmap.md 기준 현재 MVP·마일스톤 단계, 아카이빙 대기면 ⚠️ trace-archive, 없으면 "없음"}
- 미결 결정: {project-decisions.md에서 곧 정할 것, 없으면 "없음"}
- 백로그: {docs/backlog.md open 항목 수 + 핵심 1~2개, 없으면 "없음"}

# 지금 할 수 있는 것
{5.5의 선택지 목록. 킥오프 표가 없으면 "종류·의존 정보 없음" + 다음 액션 1개}
```

`# 현재 MVP`를 플랜·학습 진행률보다 먼저 보여준다. 중단된 학습은 출력하지 않는다.
마지막에 한국어로 "이어서 진행할까요, 아니면 다른 작업을 시작할까요?"로 닫는다.
