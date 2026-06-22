# Codex 설정 복사용 스니펫

> **Codex 전용 셋업.** Claude Code 셋업은 같은 폴더의 `setup-claude.md`를 본다.
> 공용 프롬프트(`trace-init.md`, `daily-retro.md`)는 도구 중립이며, Codex는 `~/.codex/prompts/`로 **복사**해야 호출된다
> (Claude Code는 `.claude/commands/` 심볼릭으로 자동 인식 — 복사 불필요).
> 아래 config 스니펫은 `~/.codex/config.toml`(전역) 또는 프로젝트 `.codex/config.toml`에 복사한다.
> ⚠️ `~/.codex/config.toml`은 **모든 Codex 프로젝트에 적용**된다. Trace에만 적용하려면 프로젝트 단위 config를 쓴다.

---

## 1. daily-retro 프롬프트 등록

이 폴더의 `daily-retro.md`를 복사:

```bash
cp docs/prompts/daily-retro.md ~/.codex/prompts/daily-retro.md
```

→ 이후 Codex에서 `/daily-retro` 또는 `/daily-retro 260615`로 호출.

## 1-1. trace-init 프롬프트 등록

내장 `/init`과 이름 충돌을 피하기 위해 `trace-init.md`로 복사:

```bash
cp docs/prompts/trace-init.md ~/.codex/prompts/trace-init.md
```

→ 이후 Codex에서 `/trace-init`으로 호출.

## 1-2. trace-archive · trace-study 프롬프트 등록

MVP 완료 후 아카이빙·학습 정리 커맨드:

```bash
cp docs/prompts/trace-archive.md ~/.codex/prompts/trace-archive.md
cp docs/prompts/trace-study.md   ~/.codex/prompts/trace-study.md
```

→ 이후 Codex에서 `/trace-archive`, `/trace-study`로 호출.
단위·흐름 규칙은 `docs/agent-rules/workflow.md` 참고.

---

## 2. 컨텍스트 보존 (컴팩션)

frank의 `compactPrompt` + 트랜스크립트 백업을 Codex 방식으로 옮긴 것.

```toml
# 컴팩션 시 보존할 항목 지시 (frank compactPrompt의 범용 버전)
compact_prompt = """
컴팩션 시 반드시 보존:
1. 현재 작업의 목표와 진행 단계
2. 수정한 파일 경로 목록
3. 사용자가 준 피드백과 수정 지시
4. 실패한 접근법과 그 이유
요약 가능: 도구 호출 출력(결론만), 읽은 파일 내용(발견사항만)
"""

# 세션 트랜스크립트 네이티브 저장 (frank PreCompact 백업 훅의 동기를 대체)
[history]
persistence = "save-all"

# (선택) 자동 컴팩션 트리거 토큰 임계값. 미설정 시 모델 기본값(컨텍스트의 ~90%).
# model_auto_compact_token_limit = 167000
```

> 참고: Codex v0.42.0에서 "변경분이 클 때 자동 compact 미작동" 이슈 보고됨
> (https://github.com/openai/codex/issues/4363). 버전 확인 권장.
> `history.persistence = "save-all"`만으로도 대화 유실 방지는 충족되므로
> 별도 백업 훅은 불필요.

---

## 3. MCP 서버 추가 (daily-retro 품질 강화 — 선택)

Codex는 전용 `codex mcp add` 명령이 없고 **config.toml 직접 편집**으로 추가한다.
형식: `[mcp_servers.<id>]` + `command` / `args` / `env` / `enabled`.

### 3-1. playwright — HTML 회고 시각 검증 (스크린샷)

```toml
[mcp_servers.playwright]
command = "npx"
args = ["-y", "@playwright/mcp@latest"]
enabled = true
# startup_timeout_sec = 20   # 첫 실행 시 브라우저 설치로 느리면 상향
```

### 3-2. sequential-thinking — 의사결정 추출 추론 보조

```toml
[mcp_servers.sequential_thinking]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-sequential-thinking"]
enabled = true
```

### 3-3. mermaid (선택)

회고의 다이어그램은 **MCP 없이 CDN 임베드로 이미 렌더**되므로 필수 아님.
서버사이드 검증/PNG 변환을 원하면 mermaid MCP 패키지를 찾아 같은 형식으로 추가
(패키지명은 직접 확인 — 생태계에 여러 구현 존재).

```toml
# 예시 (실제 패키지명 확인 후 교체)
# [mcp_servers.mermaid]
# command = "npx"
# args = ["-y", "<mermaid-mcp-package>"]
# enabled = true
```

---

## 적용 후 확인

- MCP 설정 변경 후 **Codex 재시작** 필요 (서버 툴이 로드됨).
- `[mcp_servers.*]`에 등록된 서버 목록으로 어떤 도구가 켜졌는지 확인.
- 켜진 MCP가 없어도 `daily-retro`는 정상 동작 (자동 대체).
