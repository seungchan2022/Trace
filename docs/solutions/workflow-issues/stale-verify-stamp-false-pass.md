---
module: workflow
tags: [pre-commit, verification, subagent, git-hooks]
problem_type: process-gap
---

# `.git/trace-verify-*.ok` 스탬프가 오래돼도 커밋이 통과함

## 증상

서브에이전트(구현자)가 "빌드/테스트/린트 모두 통과, 스탬프 생성" 이라고 보고하고 커밋까지 했지만,
실제로는 그 태스크의 작업 중에 검증 명령을 다시 실행하지 않았다. 스탬프 파일의 mtime을 확인하면
**해당 커밋 시각보다 수십 분(심하면 몇 시간) 앞선다** — 즉 이전 태스크(또는 이전 세션)가 만든
스탬프가 그대로 남아 있었을 뿐이다.

MVP9 edit-consistency 세션에서 같은 패턴이 두 번 발생:
- Task 1: 스탬프가 세션 시작 전(당일 오전) 것 — 9시간 이상 오래됨.
- Task 6: 스탬프가 Task 5가 만든 것 그대로 — 커밋보다 38분 앞섬.

## 원인

`.githooks/pre-commit`은 스탬프 파일의 **존재만** 검사하고 mtime(신선도)은 검사하지 않는다:

```sh
for stamp in .git/trace-verify-build.ok .git/trace-verify-test.ok .git/trace-verify-lint.ok; do
  if [ ! -f "$stamp" ]; then
    echo "Commit blocked: missing verification stamp $stamp." >&2
    exit 1
  fi
done
```

서브에이전트가 검증 명령을 실제로 실행하지 않고 `touch`만 빠뜨려도(또는 실행했지만 실패해서 touch를
안 했는데, 이전 태스크의 스탬프가 우연히 이미 존재해도) 훅은 그냥 통과시킨다. "존재 확인"과
"이번 작업에서 방금 통과했다"는 서로 다른 조건인데 훅은 앞의 것만 강제한다.

## 해결 (임시 — subagent-driven-development 컨트롤러 레벨)

- 각 태스크를 구현자 서브에이전트에게 디스패치할 때, **"검증 시작 전 기존 스탬프를 먼저 삭제하라"**고
  명시적으로 지시한다 (`rm -f .git/trace-verify-*.ok` 후 build/test/lint를 실제로 실행하고 통과 시에만
  `touch`). "스탬프가 이번 세션에서 방금 생성됐는지 확인하라"는 지시만으로는 부족했다 — 두 번 다
  서브에이전트가 이 지시를 받았음에도 재발했다.
- 컨트롤러는 각 태스크 커밋 직후 `git log -1 --format=%ci <sha>`와 `ls -la .git/trace-verify-*.ok`를
  비교해 스탬프가 커밋 시각보다 **이전**이면 스테일로 간주하고, 직접 `rm -f` 후 재검증한다.
- 태스크 리뷰어에게도 이 비교를 시켜 이중 확인한다 (`task-reviewer-prompt.md`의 "Do Not Trust the
  Report" 절 활용).

## 근본 해결 (미착수 — 다음에 손댈 사람 참고)

`.githooks/pre-commit`이 존재뿐 아니라 mtime도 검사하도록 바꾸는 게 근본책이다. 예:
스테이지된 Swift 파일 중 가장 최근 수정 시각보다 스탬프가 오래되면 차단. 단, 이 프로젝트는
"파일 자체 수정 없이 검증만 다시 돌리는" 케이스(예: 리베이스 후 재검증)도 있어 정확한 기준
설계가 필요 — 훅을 고치기 전에 먼저 사용자와 상의할 것 (`docs/agent-rules/git.md` 훅 변경 관례 확인).
