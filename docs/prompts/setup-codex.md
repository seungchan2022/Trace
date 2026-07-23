# Codex 설정 복사용 스니펫

> **Codex 전용 셋업.** Claude Code 셋업은 같은 폴더의 `setup-claude.md`를 본다.
> Trace 공용 **스킬**은 `.agents/skills/`에 두고 Codex가 프로젝트에서 직접 읽는다. 별도 복사나 전역 등록은 하지 않는다.
> 아래 config 스니펫은 `~/.codex/config.toml`(전역) 또는 프로젝트 `.codex/config.toml`에 복사한다.
> ⚠️ `~/.codex/config.toml`은 **모든 Codex 프로젝트에 적용**된다. Trace에만 적용하려면 프로젝트 단위 config를 쓴다.

---

## 1. Trace 공용 스킬

각 스킬은 `.agents/skills/<name>/SKILL.md` 한 곳에서 관리한다. Codex는 프로젝트를 신뢰한 새 대화에서 자동 발견한다.

| 용도 | Codex 호출 |
|---|---|
| 새 세션 상태 복원 | `$trace-init` |
| 하루 회고 | `$daily-retro` 또는 `$daily-retro 260615` |
| 완료 MVP 아카이빙 | `$trace-archive` 또는 `$trace-archive MVP1` |
| 완료 MVP 학습 정리 | `$trace-study` 또는 `$trace-study MVP1` |
| 외부 영상/콘텐츠 팁 검토 | `$trace-video-review` |

`~/.codex/prompts/`로 이 스킬들을 복사하지 않는다. 이전 전역 복사본이 있다면 새 호출을 검증한 뒤에만 삭제한다.
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

## 3. 터미널 승인과 안전 경계

Trace 프로젝트의 `.codex/config.toml`은 다음 기본값을 제공한다.

```toml
approval_policy = "never"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = false
```

- 일반 프로젝트 파일 작업, 빌드, 테스트, `swiftlint`는 매번 사용자 승인 없이 실행한다.
- 사용자 계정이 읽을 수 있는 프로젝트 밖 경로는 경로를 알려 주면 분석할 수 있다.
- 네트워크, 워크스페이스 밖 쓰기, 그리고 `.agents`·`.codex`처럼 Codex가 보호하는 경로 쓰기는 이 설정으로 자동 허용되지 않는다.
- `git push`, 전체 스테이징, `--no-verify`, `rm -rf`, `git reset --hard`는 `.codex/rules/trace-safety.rules`에서 별도로 차단한다.
- 이 설정은 프로젝트를 신뢰한 **새 Codex 세션**부터 적용된다. 전체 시스템 접근이 필요한 일회성 작업은 이 프로젝트 기본값을 낮추지 말고, 사용자가 그때 권한을 명시적으로 바꾼다.

---

## 4. MCP 서버 추가 (daily-retro 품질 강화 — 선택)

Codex는 전용 `codex mcp add` 명령이 없고 **config.toml 직접 편집**으로 추가한다.
형식: `[mcp_servers.<id>]` + `command` / `args` / `env` / `enabled`.

### 4-1. playwright — HTML 회고 시각 검증 (스크린샷)

```toml
[mcp_servers.playwright]
command = "npx"
args = ["-y", "@playwright/mcp@latest"]
enabled = true
# startup_timeout_sec = 20   # 첫 실행 시 브라우저 설치로 느리면 상향
```

### 4-2. sequential-thinking — 의사결정 추출 추론 보조

```toml
[mcp_servers.sequential_thinking]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-sequential-thinking"]
enabled = true
```

### 4-3. mermaid (선택)

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
