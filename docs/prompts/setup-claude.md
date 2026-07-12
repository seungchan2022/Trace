# Claude Code 설정

> **Claude Code 전용 셋업.** Codex 셋업은 같은 폴더의 `setup-codex.md`를 본다.
> 핵심: 룰 매뉴얼(`docs/agent-rules/*.md`)과 공용 프롬프트(`docs/prompts/*.md`)는 **도구 중립**이라 손대지 않는다.
> Claude Code용으로 필요한 건 "진입 파일"과 "슬래시 커맨드 서랍" 두 개의 얇은 어댑터뿐이며, 둘 다 **리포에 심볼릭으로 포함**돼 있어 클론만 하면 자동 적용된다.

---

## 무엇이 이미 배선돼 있나 (리포에 커밋됨)

| 항목 | 실체 | 효과 |
|---|---|---|
| 진입 파일 | `CLAUDE.md` → `AGENTS.md` 심볼릭 | Claude Code가 세션 시작 시 `CLAUDE.md`를 자동 로드 → Codex와 **완전히 동일한 룰**을 본다. AGENTS.md만 고치면 양쪽 반영. |
| `/trace-init` | `.claude/commands/trace-init.md` → `../../docs/prompts/trace-init.md` 심볼릭 | 세션 상태 복원 프롬프트. 복사 불필요. |
| `/daily-retro` | `.claude/commands/daily-retro.md` → `../../docs/prompts/daily-retro.md` 심볼릭 | 하루 회고 프롬프트. 복사 불필요. |
| `/trace-archive` | `.claude/commands/trace-archive.md` → `../../docs/prompts/trace-archive.md` 심볼릭 | MVP 아카이빙 프롬프트. 복사 불필요. |
| `/trace-study` | `.claude/commands/trace-study.md` → `../../docs/prompts/trace-study.md` 심볼릭 | MVP 학습 정리 프롬프트. 복사 불필요. |
| `/trace-video-review` | `.claude/commands/trace-video-review.md` → `../../docs/prompts/trace-video-review.md` 심볼릭 | 외부 영상/콘텐츠 팁 리뷰 프롬프트. 복사 불필요. |

→ 즉 **추가 설치 단계가 없다.** 새 머신에서 클론하면 그대로 동작한다.

## 첫 세션에서 1회 검증

심볼릭이 의도대로 풀리는지 새 채팅에서 확인한다:

1. 새 세션을 열고 — Claude가 `AGENTS.md`의 git 안전 규칙을 인지하는지(예: "main에서 커밋 금지") 물어 본다.
   진입 파일이 literal `CLAUDE.md` 텍스트가 아니라 **AGENTS.md 내용**으로 로드됐는지 확인하는 것.
2. `/trace-init` 입력 → 세션 상태 요약이 나오는지 확인.
3. 안 되면: 심볼릭이 깨졌는지 `ls -la CLAUDE.md .claude/commands/` 로 점검하고 재생성:
   ```bash
   ln -sf AGENTS.md CLAUDE.md
   ln -sf ../../docs/prompts/trace-init.md .claude/commands/trace-init.md
   ln -sf ../../docs/prompts/daily-retro.md .claude/commands/daily-retro.md
   ln -sf ../../docs/prompts/trace-archive.md .claude/commands/trace-archive.md
   ln -sf ../../docs/prompts/trace-study.md .claude/commands/trace-study.md
   ln -sf ../../docs/prompts/trace-video-review.md .claude/commands/trace-video-review.md
   ```

## 설치된 워크플로 플러그인 / MCP (2026-06-17 기준)

Codex와 같은 능력(기획·플랜·TDD·리뷰·iOS 빌드)을 Claude Code에서도 쓰도록 아래를 설치했다.
플러그인/MCP 자체는 보조 도구이며, 핵심 세팅(룰·프롬프트·플랜)은 리포에 이미 공유돼 있다.

| 항목 | 설치 형태 | 비고 |
|---|---|---|
| `superpowers` | 플러그인 (user scope) | `obra/superpowers-marketplace`. Codex와 같은 워크플로(brainstorming/plan/TDD/verify) |
| `compound-engineering` | 플러그인 (user scope) | `EveryInc/compound-engineering-plugin`. Codex `ce-*`와 **동일 소스** |
| `XcodeBuildMCP` | MCP (project scope, `.mcp.json`) | 시뮬레이터/UI 자동화/디버깅/로깅. `xcodebuild`로 못 덮는 부분 보강 |

재설치/재현이 필요하면:

```bash
claude plugin marketplace add obra/superpowers-marketplace
claude plugin install superpowers@superpowers-marketplace
claude plugin marketplace add EveryInc/compound-engineering-plugin
claude plugin install compound-engineering@compound-engineering-plugin
claude mcp add XcodeBuildMCP -s project \
  -e XCODEBUILDMCP_ENABLED_WORKFLOWS=simulator,ui-automation,debugging,logging \
  -- npx -y xcodebuildmcp@latest mcp
```

- 플러그인/MCP는 **설치한 다음 세션부터** 로드된다(현재 세션엔 즉시 반영 안 됨).
- `build-ios-apps`는 Codex 번들(`openai-curated`)이라 Claude 직접 대응이 불확실 → XcodeBuildMCP + `swift-lsp`로 대체.
- playwright/sequential-thinking MCP는 `daily-retro` 스크린샷 검증 등 실제 필요 시 `claude mcp add`로 추가.
- 토큰 비용: 스킬은 한 줄 설명만 상시 로드(호출 시 펼침), MCP 도구는 deferred(이름만, 사용 시 펼침)라 설치가 세션 수명을 의미 있게 깎지 않는다.

## 핸드오프 규율 (도구 전환 시 반드시)

두 도구를 번갈아 쓸 때의 상태 인계 규칙은 `docs/agent-rules/dual-tool.md`에 정의돼 있다. 요지:

- 인계 상태는 **git + `project-decisions.md` + 플랜 체크박스**에만 둔다. Claude/Codex **메모리는 상대가 못 보므로** 신뢰하지 않는다.
- 플랜 체크박스(`- [ ]` → `- [x]`)는 **작업 중 실시간 갱신**한다. 세션은 토큰 소진으로 갑자기 죽으므로 이게 유일한 인계 메모다.

## 컨텍스트 보존 (컴팩션)

Codex(`setup-codex.md` §2)와 달리 Claude Code는 컴팩션을 거의 설정하지 않는다 — 대부분 네이티브로 처리되기 때문이다.

- **자동 압축: 기본 ON** (`autoCompactEnabled`, 컨텍스트가 한계에 근접하면 자동 요약). 압축 시점을 바꾸는 임계값 설정은 없다(켜기/끄기만). 끄려면 `settings.json`에 `"autoCompactEnabled": false` 또는 env `DISABLE_AUTO_COMPACT`. Sonnet은 200K 창이라 Opus(1M)보다 압축이 자주 걸린다.
- **트랜스크립트: 네이티브 자동 저장**(`~/.claude/projects/...`, `--resume`/`--continue`로 복원). 별도 백업 훅 불필요 — frank의 PreCompact 백업 훅 동기는 이미 충족된다.
- **압축 시 보존 지시(Codex `compact_prompt` 대응): 네이티브 미지원.** settings의 `compactPrompt`는 공식 스키마에 없어 무시된다(오픈 이슈 #14160). frank에서 복사하지 말 것.
- 그래서 보존은 압축 요약에 기대지 않고 **상태 외부화**로 한다: 진행은 플랜 체크박스, 결정·피드백은 `project-decisions.md`, 현재 위치는 `docs/roadmap.md`. 압축/새 세션 후 `CLAUDE.md`가 재로드되고 `/trace-init`으로 복원한다. frank는 `active_*.txt` + UserPromptSubmit 훅으로 이 재진입을 자동화했으나, Trace는 그 훅 묶음을 의도적으로 버리고 `/trace-init` 수동 호출로 대체했다(`history`의 2026-06-22 회고). 상세 `docs/agent-rules/dual-tool.md`.
