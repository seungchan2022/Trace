# Trace 현재 기능 전수 문서 작성 계획

> **상태: 실행 준비 완료**
> 이 문서는 MVP 밖 문서 정비 작업의 실행 정본이다. 다음 세션은 방향을 다시 논의하거나 별도 계획을 만들지 않고 이 체크리스트를 순서대로 수행한다.

🔴 **다음 세션 선행 작업:** 이 계획을 바로 실행해 `docs/current-features.md`를 작성한다.

## 목표

현재 checkout에서 사용자가 실제로 이용할 수 있는 기능을 사용자 시나리오 순서로 정리해
`docs/current-features.md`를 만든다. 이 문서는 제품 이해·관리와 포트폴리오 근거를 연결하는 사실 원본이며,
채용 담당자에게 바로 제출하는 최종 포트폴리오 문구는 아니다.

## 확정된 방향

| 항목 | 결정 |
|---|---|
| 주 독자와 용도 | 사용자와 다음 에이전트가 현재 제품을 이해하고, 이후 포트폴리오 사례를 뽑는 사실 원본으로 사용한다. |
| 구성 단위 | 상위 절은 사용자 시나리오·흐름으로 나누고, 각 흐름 안에서 사용자가 얻는 기능과 가치를 적는다. |
| 포함 범위 | 현재 제공 기능과 조건부·실험 기능을 포함하되 상태를 명확히 구분한다. 교체·삭제된 기능은 목록에 넣지 않고 관련 회고로 연결한다. |
| 기능별 정보 | 사용자 장면, 사용자가 할 수 있는 일과 가치, 현재 상태, 확인 근거, 관련 결정·회고 링크를 남긴다. |
| 파일 위치 | `docs/current-features.md` |
| 갱신 시점 | 마일스톤 실기기 QA 결과를 사용자가 수용했을 때 갱신하고, MVP 아카이빙 때 누락 여부를 마지막으로 확인한다. |

## 새 세션의 시작과 종료

1. Codex는 `$trace-init`, Claude Code는 `/trace-init`을 실행한다.
2. `trace-init`이 이 계획을 재개 작업으로 보여주면, 이 파일을 읽고 아래 체크리스트를 사용자 재승인 없이 끝까지 수행한다.
3. `docs/current-features.md` 작성과 문서 검증, 계획 체크박스 갱신, 한 작업 단위 커밋까지 마치고 세션을 종료한다.
4. 같은 세션에서 다음 MVP를 고르거나 개발을 시작하지 않는다. push와 `main` 통합도 하지 않는다.

새 세션에 붙여넣을 권장 요청은 다음 한 줄이다.

> `$trace-init`을 실행하고 현재 기능 전수 문서 계획을 그대로 수행해 `docs/current-features.md` 작성과 검증, 커밋까지 완료해줘. 다음 MVP 개발은 시작하지 마.

## 이 작업에서 사용하는 스킬

- 시작: `trace-init` — 현재 브랜치와 재개 지점을 읽기 전용으로 복원한다.
- 완료 직전: `superpowers:verification-before-completion` — 아래 문서 검증 결과를 직접 확인한다.

방향과 계획은 이미 확정됐으므로 이 작업에서는 `brainstorming`, `writing-plans`,
`subagent-driven-development`, `executing-plans`, `trace-study`, `milestone-retro`, `trace-archive`,
`ce-doc-review`, Xcode 빌드·테스트 전용 스킬을 호출하지 않는다. 예상하지 못한 스킬이 필요해 보여도 자동으로
추가하지 않는다. 사실 확인이 부족한 기능은 작업을 넓히는 대신 문서에서 `확인 필요`로 표시한다.

## 근거 우선순위

1. 현재 checkout의 `Trace/App/`, `Trace/Pages/`, `Trace/Application/`, `Trace/Domain/`, `Trace/Infrastructure/`
2. 현재 checkout의 `TraceTests/`, `TraceUITests/`
3. `docs/product-baseline.md`, `docs/current-mvp.md`, `docs/roadmap.md`
4. `history/INDEX.md`와 관련 MVP의 설계·계획·실기기 QA·완료 회고

과거 문서는 기능의 배경과 결정 근거로만 사용한다. 과거 문서에 있다는 이유만으로 현재 제공 기능이라고
단정하지 않는다. 코드·테스트에서 현재 경로를 찾지 못한 기능은 `확인 필요`로 표시하거나 제외한다.

## `current-features.md` 형식

문서 머리에는 목적, 기준 checkout·작성일, 아래 상태 범례를 둔다.

- `현재 제공`: 현재 코드에서 진입 경로와 동작 근거를 확인했다.
- `조건부·실험`: 특정 권한·환경·실험 플래그·제한된 진입 조건에서만 쓸 수 있다.
- `확인 필요`: 코드나 테스트만으로 실제 제공 여부를 확정하지 못했다.

본문은 화면 파일 목록이 아니라 다음과 같은 사용자 흐름 순서로 구성한다. 현재 앱에서 확인한 사실에 맞춰
제목을 합치거나 나눌 수 있지만, 기술 레이어 기준으로 바꾸지 않는다.

1. 앱에 들어와 목적을 고른다.
2. 달리기 전 코스를 계획하고 관리한다.
3. 코스 없이 러닝을 준비하고 기록한다.
4. 지난 러닝을 돌아보고 관리한다.
5. 권한·저장·위젯·인텐트처럼 주 흐름을 보조하는 조건부 경험을 사용한다.

각 흐름은 아래 열을 가진 표로 작성한다.

| 사용자 장면 | 사용자가 할 수 있는 일과 가치 | 상태 | 확인 근거 | 관련 결정·회고 |
|---|---|---|---|---|

`확인 근거`에는 함수·타입을 장황하게 설명하지 않고 현재 화면·테스트·저장소 경로를 링크한다.
`관련 결정·회고`에는 바뀐 이유를 복사하지 않고 해당 history 문서를 링크한다. 삭제·교체된 기능의 연대기는
`current-features.md`에 다시 쓰지 않는다.

## 실행 체크리스트

- [ ] `Trace/App/RootView.swift`와 `Trace/App/AppTab.swift`에서 현재 탭과 사용자 진입 흐름을 확인한다.
- [ ] `Trace/Pages/`를 기준으로 각 흐름에서 사용자가 수행할 수 있는 행동을 수집한다.
- [ ] `TraceTests/`와 `TraceUITests/`에서 주요 행동의 현재 동작 근거와 조건부 기능을 대조한다.
- [ ] `history/INDEX.md`와 관련 완료 회고에서 제품 결정·방향 전환 링크만 연결한다.
- [ ] 현재 제공 / 조건부·실험 / 확인 필요로 분류하고, 교체·삭제 기능을 현재 목록에서 분리한다.
- [ ] 위 형식으로 `docs/current-features.md`를 작성한다.
- [ ] `docs/product-baseline.md`의 도입부에서 현재 기능 전수 문서를 찾을 수 있게 링크한다.
- [ ] 아래 검증을 실행하고 결과를 직접 확인한다.
- [ ] 이 계획의 체크박스를 모두 완료로 갱신하고 관련 문서만 명시적으로 스테이징해 한 번 커밋한다.

## 완료 검증

먼저 문서 자체를 다음 명령으로 확인한다.

```bash
test -f docs/current-features.md
rg -n '^## ' docs/current-features.md
rg -n '현재 제공|조건부·실험|확인 필요' docs/current-features.md
rg -n 'current-features.md' docs/product-baseline.md docs/agent-rules/product-visibility.md
git diff --check
git status --short
git diff -- docs/current-features.md docs/product-baseline.md docs/superpowers/plans/2026-09-01-current-feature-inventory.md
```

커밋 전에는 문서 변경이어도 저장소의 공통 정책을 따라 `docs/agent-rules/testing.md`의 Baseline
build·test·lint를 모두 실행한다. 명령은 계획에 복사하지 않고 해당 정본을 따른다. 하나라도 실패하면
완료나 커밋을 주장하지 말고 실패 근거를 보고한다.

완료 조건:

- 모든 현재 기능 주장에 현재 checkout 근거가 있거나 `확인 필요` 표시가 있다.
- 기능이 사용자 흐름 순서로 읽히고 코드 파일·함수 목록처럼 보이지 않는다.
- 조건부·실험 기능이 일반 제공 기능과 섞이지 않는다.
- 과거 변경 이유는 중복 서술하지 않고 history 링크로 연결한다.
- 새 MVP 범위, 포트폴리오 최종 문구, 광범위한 코드 학습이 추가되지 않는다.

## 커밋 범위

한 문서 작업 단위로 다음 파일만 커밋한다.

- `docs/current-features.md`
- `docs/product-baseline.md`
- `docs/superpowers/plans/2026-09-01-current-feature-inventory.md`

다른 파일 변경이 발견되면 섞지 않는다. 커밋 후 push하거나 `main`에 통합하지 않는다.
