# Trace 공통 스킬 전환 구현 계획

> **For agentic workers:** 이 계획은 현재 세션에서 인라인으로 순서대로 실행한다. 각 단계가 끝나는 즉시 체크박스를 갱신한다.

**Goal:** `trace-init`을 한 개의 프로젝트 공통 스킬로 전환하고, Codex 프로젝트 설정을 저장소에 추가해 Claude Code와 Codex가 같은 세션 복원 정책을 따르게 한다.

**Architecture:** 스킬 본문은 `.agents/skills/trace-init/SKILL.md` 한 곳에 둔다. Codex는 이 프로젝트 스킬을 직접 발견하고 `$trace-init`으로 명시 호출하며, Claude Code는 `.claude/skills/trace-init` 심볼릭 링크를 통해 같은 본문을 발견하고 `/trace-init`으로 호출한다. 두 도구의 설정 파일 문법은 다르므로, 공통 정책인 "세션 복원 정보 보존"만 동일하게 유지한다.

**Tech Stack:** Agent Skills `SKILL.md`, Git 심볼릭 링크, Codex project `config.toml`, Claude Code project settings

**상태(2026-07-23):** 완료. 새 Codex 세션에서 `$trace-init` 발견과 실행을 확인했다.

## Global Constraints

- 기존 Superpowers 등 플러그인 스킬과 `~/.codex/` 전역 설정은 수정하지 않는다.
- `.claude/settings*.json`과 `.codex/config.toml`의 문법을 복사하지 않는다. 같은 정책만 각 도구의 지원 형식으로 표현한다.
- `trace-init` 외의 기존 커스텀 프롬프트는 이번 파일럿에서 전환하지 않는다.
- 사용자 미추적 파일 `docs/mvp17-kickoff`, `TRACE_PROJECT_ANALYSIS.md`, `docs/superpowers/plans/2026-07-21-history-tab.md`는 수정하지 않는다.
- 커밋과 push는 만들지 않는다.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `.agents/skills/trace-init/SKILL.md` | `trace-init`의 유일한 실행 본문과 스킬 메타데이터 |
| `.claude/skills/trace-init` | Claude Code가 공통 스킬 폴더를 찾도록 하는 심볼릭 링크 |
| `.codex/config.toml` | Trace 범위 Codex의 컴팩션·히스토리 보존 설정 |
| `docs/agent-rules/dual-tool.md` | 공통 스킬과 도구별 발견 경로의 기준 문서 |
| `docs/prompts/setup-codex.md` | Codex에서 `trace-init`을 `$trace-init`으로 호출하는 안내 |
| `docs/prompts/setup-claude.md` | Claude Code에서 `trace-init`을 `/trace-init`으로 호출하는 안내 |

### Task 1: 공통 `trace-init` 스킬과 Claude 발견 경로를 만든다

**Files:**
- Create: `.agents/skills/trace-init/SKILL.md`
- Create: `.claude/skills/trace-init` (symbolic link to `../../.agents/skills/trace-init`)
- Delete: `.claude/commands/trace-init.md` (legacy symbolic link)
- Delete: `docs/prompts/trace-init.md` (legacy prompt source)

- [x] `docs/prompts/trace-init.md`의 읽기 전용 세션 복원 절차를 `SKILL.md`로 옮긴다.
- [x] YAML frontmatter에 `name: trace-init`과 "세션 시작 시 동적 상태를 읽기 전용으로 복원"하는 설명을 넣는다.
- [x] Claude의 기존 command 링크를 제거하고, 공통 스킬 폴더를 가리키는 `.claude/skills/trace-init` 링크를 만든다.
- [x] 링크 대상과 `SKILL.md` frontmatter를 검사한다.

### Task 2: Codex 프로젝트 설정과 도구 전환 문서를 맞춘다

**Files:**
- Create: `.codex/config.toml`
- Modify: `docs/agent-rules/dual-tool.md`
- Modify: `docs/prompts/setup-codex.md`
- Modify: `docs/prompts/setup-claude.md`

- [x] `.codex/config.toml`에 Claude의 `compactPrompt`와 같은 다섯 가지 보존 항목을 `compact_prompt`로 넣는다.
- [x] `[history] persistence = "save-all"`을 넣어 Codex가 이 프로젝트 세션 이력을 저장하게 한다.
- [x] `dual-tool.md`에서 `trace-init`의 공통 원본을 `.agents/skills/trace-init/SKILL.md`로 바꾸고, Claude는 링크로·Codex는 직접 발견한다고 기록한다.
- [x] 두 setup 문서에서 예전 Codex 복사 등록 안내를 `trace-init`에는 제거하고, 각각 `/trace-init`과 `$trace-init` 호출법을 명시한다.

### Task 3: 구조·문서·Codex 설정을 검증한다

**Files:**
- Verify: `.agents/skills/trace-init/SKILL.md`
- Verify: `.claude/skills/trace-init`
- Verify: `.codex/config.toml`
- Verify: documentation changes

- [x] `test -L .claude/skills/trace-init && test -f .claude/skills/trace-init/SKILL.md`로 Claude 링크 해석을 확인한다.
- [x] `rg`로 남은 legacy `trace-init` 경로를 검사하고, 전역 legacy 프롬프트는 사용자 확인 전 삭제하지 않았음을 문서에 남긴다.
- [x] `git diff --check`과 `git status --short`로 공백 오류·변경 범위·사용자 미추적 파일 보존을 확인한다.
- [x] Codex는 새 대화 또는 재시작 후 `$trace-init`, Claude Code는 새 세션에서 `/trace-init`으로 수동 확인해야 함을 사용자에게 전달한다.
