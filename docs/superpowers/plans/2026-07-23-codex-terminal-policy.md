# Codex 터미널 정책 동기화 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trace에서 Codex가 일반 프로젝트 작업을 승인 없이 수행하되, 보호된 Git
메타데이터 쓰기는 사용자 승인을 요청할 수 있고 위험 터미널 명령은 프로젝트 규칙으로
계속 차단되게 한다.

**Architecture:** `.codex/config.toml`은 프로젝트 범위의 `workspace-write` 샌드박스와
`on-request` 승인 정책을 제공한다. 일반 작업은 샌드박스 안에서 바로 실행하고, 커밋처럼
보호된 `.git` 쓰기만 사용자 승인을 요청한다. `.codex/rules/trace-safety.rules`는 위험한
명령 접두사를 `forbidden`으로 차단한다. 공통 Git 안전 규칙은 계속
`docs/agent-rules/git.md`가 소유하고, 설정 문서는 두 도구의 기계적 차이를 설명한다.

**Tech Stack:** Codex project `config.toml`, Codex experimental execpolicy rules (Starlark), Markdown documentation.

**상태(2026-07-23):** 완료. 실제 커밋 검증에서 발견한 `never` 정책 오류까지
`on-request`로 정정하고 관련 문서를 동기화했다.

## Global Constraints

- 설정 범위는 Trace 프로젝트뿐이다. `~/.codex/config.toml`과 전역 rules는 수정하지 않는다.
- `sandbox_mode = "danger-full-access"`는 사용하지 않는다.
- `approval_policy = "on-request"`는 보호된 쓰기를 자동 허용하지 않고 사용자 승인 경로만 연다.
- `git push`, 전체 스테이징, 훅 우회, 재귀 강제 삭제, hard reset은 명시적으로 금지한다.
- 최초 정책 구성 단계에서는 커밋·푸시를 하지 않는다. 실제 커밋 경로 검증은 사용자 요청을
  받은 Task 5에서만 수행하고, push는 계속 하지 않는다.

---

### Task 1: 현재 정책과 누락점 기록

**Files:**
- Modify: `docs/superpowers/plans/2026-07-23-codex-terminal-policy.md`

- [x] **Step 1: Claude와 Codex의 현재 터미널 정책을 대조한다**

확인 항목:

```text
Claude: permissions.deny + swiftlint allow
Codex: compact_prompt + history만 존재, project rule 없음
```

- [x] **Step 2: Codex 명령 규칙의 baseline 부재를 확인한다**

Run:

```bash
test ! -e .codex/rules/trace-safety.rules
```

Expected: exit status `0`.

### Task 2: 프로젝트 자동 실행 및 위험 명령 차단 구성

**Files:**
- Modify: `.codex/config.toml`
- Create: `.codex/rules/trace-safety.rules`

- [x] **Step 1: 프로젝트 기본 권한을 설정한다**

Add:

```toml
approval_policy = "on-request"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = false
```

- [x] **Step 2: Codex execpolicy 금지 규칙을 작성한다**

Create `trace-safety.rules` with `forbidden` prefix rules for `git push`, `git add -A` / `--all` / `.`, `git commit --no-verify` / `-n`, `git merge --no-verify`, `git reset --hard`, and `rm -rf` / `-fr` / `--recursive --force`.

Each rule includes `match` examples so Codex validates it when loading.

- [x] **Step 3: `.env` 보호를 공통 규칙으로 유지한다**

Do not add a fragile command-prefix rule for editors. Keep `.env` edit prohibition in `AGENTS.md`/Git safety guidance, where it applies to both tools and `apply_patch` as well as shell commands.

### Task 3: 문서에서 동작 경계 설명

**Files:**
- Modify: `docs/agent-rules/git.md`
- Modify: `docs/agent-rules/dual-tool.md`
- Modify: `docs/prompts/setup-codex.md`

- [x] **Step 1: Git 안전 문서의 Claude 전용 표현을 두 도구의 런타임 가드로 정정한다**

`git.md`에 Claude `deny`와 Codex `trace-safety.rules`가 같은 위험 명령을 각각 차단하며, 공통 원칙의 단일 소유자는 해당 문서라는 점을 적는다.

- [x] **Step 2: Dual-tool 문서에 권한 모델 차이를 기록한다**

Codex의 `workspace-write + on-request`는 일반 작업을 승인 없이 수행하면서 보호된 `.git`
쓰기는 사용자 승인을 요청할 수 있고, 전체 접근 bypass는 아니라는 점을 기록한다. Claude의
allow/deny JSON과 Codex rules가 문법적으로 다르다는 점도 함께 남긴다.

- [x] **Step 3: Codex setup 문서에 적용 효과와 예외를 적는다**

새 Codex 세션에서 설정이 적용되며, 외부 경로 읽기는 가능하지만 네트워크·워크스페이스 밖 쓰기·`.agents`/`.codex` 같은 보호 경로 쓰기에는 자동 승인이 아닌 제한이 적용된다는 점을 적는다.

### Task 4: 규칙과 설정 검증

**Files:**
- Modify: `docs/superpowers/plans/2026-07-23-codex-terminal-policy.md`

- [x] **Step 1: 위험 명령이 `forbidden`인지 execpolicy로 확인한다**

Run:

```bash
codex execpolicy check --pretty --rules .codex/rules/trace-safety.rules -- git push origin main
codex execpolicy check --pretty --rules .codex/rules/trace-safety.rules -- git add -A
codex execpolicy check --pretty --rules .codex/rules/trace-safety.rules -- git reset --hard
codex execpolicy check --pretty --rules .codex/rules/trace-safety.rules -- rm -rf temp
```

Expected: each result reports `forbidden`.

- [x] **Step 2: 안전한 명시 경로 스테이징은 막히지 않는지 확인한다**

Run:

```bash
codex execpolicy check --pretty --rules .codex/rules/trace-safety.rules -- git add Trace/App.swift
```

Expected: no matching `forbidden` rule.

- [x] **Step 3: TOML·문서 공백과 Git diff를 확인한다**

Run:

```bash
git diff --check
codex --version
```

Expected: both exit with status `0`.

### Task 5: 실제 커밋 경로 검증 후 승인 정책 정정

**Files:**
- Modify: `.codex/config.toml`
- Modify: `docs/agent-rules/git.md`
- Modify: `docs/agent-rules/dual-tool.md`
- Modify: `docs/prompts/setup-codex.md`
- Modify: `docs/superpowers/plans/2026-07-23-codex-terminal-policy.md`

- [x] **Step 1: `never`에서 사용자 요청 커밋이 막히는 원인을 확인한다**

`workspace-write`는 일반 파일 편집을 허용하지만 `.git/index`·객체·ref 같은 보호된 Git
메타데이터 쓰기는 승인 상승이 필요하다. `approval_policy = "never"`는 그 승인 요청 자체를
막아, 사용자가 커밋을 명시적으로 요청해도 실행할 경로가 없었다.

- [x] **Step 2: 승인 정책만 `on-request`로 바꾸고 안전 경계는 유지한다**

`workspace-write`, `network_access = false`, 위험 명령 `forbidden` 규칙은 그대로 둔다.
`on-request`는 보호 경로를 자동 허용하지 않고, 필요한 작업마다 사용자에게 승인받을 수 있게
한다.

- [x] **Step 3: 새 세션에서 실제 커밋으로 검증한다**

사용자 승인 뒤 `scripts/trace-commit.sh`로 커밋 `0784be1`과 `2f9d99d`를 생성했다.
`git push`는 실행하지 않았다. 설정값과 설명 문서도 최종 정책인 `on-request`로 맞춘다.
