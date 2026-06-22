# 하루 회고 생성 (공용 프롬프트)

> 이 절차는 Codex와 Claude Code **양쪽에서 `/daily-retro`로 호출**된다.
> - Codex: 이 파일을 `~/.codex/prompts/daily-retro.md`에 복사해 등록 (`docs/prompts/setup-codex.md` 참고).
> - Claude Code: `.claude/commands/daily-retro.md`가 이 파일을 가리키므로 별도 복사 없이 인식된다.
> `/daily-retro` 또는 `/daily-retro YYMMDD` (인자 없으면 오늘 날짜).
> 독자: 개인 기록 + 멘토/면접관에게 보여줄 수준.

## 스타일

- 일기체 — 딱딱하지 않게, 설명하듯 자연스럽게.
- 핵심은 **의사결정의 "왜"** — 왜 그것을 골랐고, 다른 선택지와 비교해 어떤 근거로 결정했는지.
- 단순 기록이 아니라 **인사이트/교훈** 중심. 감정(힘들었던 점·뿌듯했던 점)도 포함.

## 사용할 도구 (MCP가 있으면 쓰고, 없으면 자동 대체)

이 프롬프트는 **MCP 0개로도 완전 동작**한다. 아래 MCP가 설정돼 있으면 품질이 올라간다:

- **sequential-thinking** (있으면): Phase 1의 의사결정 추출·분류를 이 도구로 단계적으로 추론.
  없으면 그냥 직접 추론한다.
- **playwright** (있으면): Phase 5에서 생성한 HTML을 `file://` 경로로 열어 스크린샷을 찍고,
  레이아웃/색상/모바일 폭을 육안 검증한 뒤 첨부. 없으면 이 단계는 건너뛴다.
- **mermaid 다이어그램**: MCP 불필요. 항상 CDN 임베드(`<pre class="mermaid">`)로 브라우저가 렌더한다.
  mermaid 검증용 MCP가 있다면 임베드 전에 문법만 점검해도 좋다.

> 어떤 MCP가 켜져 있는지는 도구의 MCP 설정에서 확인한다 (Codex `~/.codex/config.toml`의 `[mcp_servers.*]`,
> Claude Code `claude mcp list` 또는 설정). 추가 방법은 `docs/prompts/setup-codex.md` / `setup-claude.md` 참고.

## Phase 1 — 데이터 수집 (생략 금지, 추측 금지)

해당 날짜의 **실제 git 기록**을 읽고 파싱한다. (sequential-thinking 있으면 그걸로 정리)

```bash
git log --after="{날짜} 00:00" --before="{날짜} 23:59" --oneline
git diff {첫커밋}^..{마지막커밋} --stat
git show {커밋해시} --stat --format="%B"   # 주요 커밋: 무엇을·왜 바꿨는지
```

정리 결과(Phase 2 전에 내부적으로):
- 커밋별 핵심 변경 요약
- 의사결정 목록 (커밋 메시지·diff에서 추출)
- 미해결 이슈/TODO 목록

## Phase 2 — 분석 기반 인터뷰 (1문 1답, 필수)

Phase 1의 **실제 데이터로만** 선택지를 만든다. "오늘 뭐 했나요?" 같은 빈 질문 금지 —
이미 답을 아는 상태에서 확인·보충만 받는다.

1. 추출한 의사결정을 번호 목록으로 제시 → 포함할 번호를 선택받는다 (예: `1,3,5`).
2. 이어서 질문 최대 3개. 각 질문은 A/B/C/직접입력 + **추천 항목·추천 이유** 포함:
   - Q1. 가장 어려웠던 점
   - Q2. 인사이트·교훈
   - Q3. 내일 계획
3. **한 번에 하나씩** 묻는다. 응답을 받은 뒤 다음 질문으로. 답이 짧거나 "패스"도 허용.

## Phase 3 — 회고 초안 (markdown)

섹션 구조:
- 오늘 뭘 했나 (시간순/중요도순 서술)
- 핵심 의사결정과 이유 — 결정별: **상황 · 선택지 · 결정 · 왜 · 인사이트**
- 기획/설계 과정 (아이디어를 어떻게 좁혔는지)
- 인사이트 & 피드백 (다음에 같은 상황이면 어떻게 할지)
- 배운 것 (기술/프로세스)
- 느낀 점 (솔직한 감정)
- 내일 할 일

## Phase 4 — 인포그래픽

의사결정 흐름도 · 비교표 · 타임라인 · 아키텍처 중 **최소 1개**를 Mermaid로 생성한다.

## Phase 5 — HTML (Claude Sunset 테마)

모바일 최적화(`max-width: 480px`), 시스템 기본 폰트.

```css
--bg:#FDF6F0; --text:#2D2926; --accent:#D97706; --accent-light:#FEF3C7;
--heading:#92400E; --border:#E5D5C5; --code-bg:#FFF7ED; --card-bg:#FFFFFF;
```

Mermaid 임베드(MCP 불필요, 브라우저 렌더):

```html
<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
  mermaid.initialize({ startOnLoad: true, theme: 'base' });
</script>
<pre class="mermaid">graph TB ...</pre>
```

**playwright MCP가 있으면**: 생성한 HTML을 열어 스크린샷을 찍고 레이아웃·색상·폭을 검증한 뒤 보고에 첨부.

## Phase 6 — 반복 실수 → 기계화 (회고 → 규칙 루프)

회고에서 "반복될 수 있는 문제"를 식별해 반영을 제안한다 (A/B/C 선택지로):

| 문제 유형 | 반영 대상 (Trace 기준) |
|---|---|
| 반복적 실수 | `.githooks/` (pre-commit 등) |
| 워크플로우 이탈 | `docs/agent-rules/*.md` 수정 |
| 새 규칙 필요 | `docs/agent-rules/` 추가 |
| 도구 부족 | 도구의 MCP 설정에 추가 (`docs/prompts/setup-codex.md` / `setup-claude.md` 참고) |

원칙: **"같은 문제가 두 번 나면, 문서가 아니라 기계(hook/MCP)로 막는다."**

## Phase 7 — 저장 및 보고

- 마크다운: `history/daily-retro/{YYMMDD}_daily_retro.md`
- HTML: `history/daily-retro/{YYMMDD}_daily_retro.html`
- HTML 생성 후 반드시 브라우저로 연다:
  - 브라우저 도구(Codex Browser, Playwright MCP 등)가 있으면 `file://{절대경로}`로 열어 사용자에게 보이게 한다.
  - 없으면 OS 기본 브라우저로 열거나(`open {경로}`), 불가능한 이유와 직접 열 파일 경로를 보고한다.
- 파일 경로 안내 + 설정 반영 제안 항목 함께 보고.

## 출력 규칙

- 5개 이상 섹션으로 상세히, 인포그래픽 최소 1개.
- 코드 블록 최소화 → 다이어그램으로 대체.
- 한국어, 이모지 적절히 허용 (회고 문서이므로).
