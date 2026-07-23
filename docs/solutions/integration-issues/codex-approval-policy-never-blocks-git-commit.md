---
title: "Codex approval_policy never 설정으로 Git 커밋이 차단되는 문제"
date: 2026-07-23
category: integration-issues
module: Codex Git commit workflow
problem_type: integration_issue
component: tooling
severity: medium
symptoms:
  - "workspace-write 샌드박스에서 Git 커밋이 보호된 .git 메타데이터를 쓰지 못했다"
  - "approval_policy가 never여서 에이전트가 커밋에 필요한 권한 상승을 요청할 수 없었다"
root_cause: config_error
resolution_type: config_change
related_components:
  - "development_workflow"
tags:
  - "codex"
  - "git-commit"
  - "sandbox"
  - "approval-policy"
  - "permissions"
---

# Codex approval_policy never 설정으로 Git 커밋이 차단되는 문제

## Problem

Trace의 저장소 로컬 Codex 설정은 일반 작업 파일 수정은 허용했지만, 사용자가 명시적으로
요청한 Git 커밋을 완료할 수 없는 조합이었다. `workspace-write`가 보호된 `.git` 쓰기를
막는 상황에서 `approval_policy = "never"`가 승인 요청 자체도 차단했다.

## Symptoms

- 워크스페이스 안의 문서와 설정 파일은 정상적으로 수정할 수 있었다.
- 스테이징·커밋 단계에서는 보호된 `.git` 쓰기가 필요해 진행할 수 없었다.
- `approval_policy = "never"` 때문에 필요한 권한 상승을 사용자에게 요청할 수도 없었다.

## What Didn't Work

`workspace-write`와 `approval_policy = "never"`를 함께 유지하는 방식은 파일 편집에는
충분했지만 커밋 경로에는 충분하지 않았다. 일반 파일 편집 성공만으로 같은 저장소의
스테이징·커밋도 가능하다고 판단하면 이 차이를 놓친다.

## Solution

`.codex/config.toml`의 승인 정책만 `on-request`로 변경했다.

```toml
# Before
approval_policy = "never"
sandbox_mode = "workspace-write"

# After
approval_policy = "on-request"
sandbox_mode = "workspace-write"
```

`workspace-write`, `network_access = false`, `.codex/rules/trace-safety.rules`의 위험 명령
차단은 그대로 유지했다. 변경 뒤 프로젝트를 신뢰한 새 Codex 세션에서 사용자 승인을 받아
`scripts/trace-commit.sh`를 실행했고, 커밋 `0784be1`과 `2f9d99d`가 실제로 생성됐다.
`git push`는 실행하지 않았다.

## Why This Works

`on-request`는 보호된 작업을 자동 허용하지 않는다. 대신 `.git/index`·객체·ref 쓰기처럼
현재 샌드박스 범위를 벗어나는 작업이 필요할 때 Codex가 사용자 승인을 요청할 수 있게 한다.
따라서 일반 파일 작업은 계속 `workspace-write` 안에 제한되고, 네트워크와 위험 명령 제한도
유지하면서 사용자가 요청한 커밋만 명시적 승인 경로로 수행할 수 있다.

## Prevention

- Git 작업이 필요한 저장소에서는 `sandbox_mode`와 `approval_policy`를 따로 검토한다.
- 저장소 로컬 설정을 바꾼 뒤에는 새 세션에서 실제 스테이징·커밋으로 `.git` 쓰기 경로를
  확인한다.
- 승인 정책을 바꿔도 `workspace-write`, 네트워크 제한, 위험 명령 차단은 독립적으로 유지한다.
- 설정을 수정할 때는 정책 설명이 여러 문서에 남아 있지 않은지 검색해 함께 갱신한다.

```bash
rg -n 'approval_policy|sandbox_mode|network_access|never|on-request' \
  AGENTS.md .codex docs
```

## Related Issues

- [`docs/agent-rules/git.md`](../../agent-rules/git.md) — Trace의 Git 안전 규칙과 런타임 가드
- [`docs/prompts/setup-codex.md`](../../prompts/setup-codex.md) — 저장소 로컬 Codex 설정 안내
