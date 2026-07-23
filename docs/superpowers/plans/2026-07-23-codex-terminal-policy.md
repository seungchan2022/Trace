# Codex 터미널 정책 동기화 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trace에서 Codex가 일반 프로젝트 작업을 승인 없이 수행하되, Claude Code가 막던 위험 터미널 명령은 Codex에서도 프로젝트 규칙으로 차단한다.

**Architecture:** `.codex/config.toml`은 프로젝트 범위의 `workspace-write` 샌드박스와 `never` 승인 정책을 제공한다. `.codex/rules/trace-safety.rules`는 위험한 명령 접두사를 `forbidden`으로 차단한다. 공통 Git 안전 규칙은 계속 `docs/agent-rules/git.md`가 소유하고, 설정 문서는 두 도구의 기계적 차이를 설명한다.

**Tech Stack:** Codex project `config.toml`, Codex experimental execpolicy rules (Starlark), Markdown documentation.

## Global Constraints

- 설정 범위는 Trace 프로젝트뿐이다. `~/.codex/config.toml`과 전역 rules는 수정하지 않는다.
- `sandbox_mode = "danger-full-access"`는 사용하지 않는다.
- `approval_policy = "never"`는 승인 창을 없애지만, 워크스페이스 밖 쓰기·네트워크·보호 경로 쓰기를 허용하지 않는다.
- `git push`, 전체 스테이징, 훅 우회, 재귀 강제 삭제, hard reset은 명시적으로 금지한다.
- 커밋·푸시는 하지 않는다.

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
approval_policy = "never"
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

Codex의 `workspace-write + never`는 승인 없이 작업하지만 전체 접근 bypass가 아니라는 점과, Claude의 allow/deny JSON과 Codex rules가 문법적으로 다르다는 점을 기록한다.

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
