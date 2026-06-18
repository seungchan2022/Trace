#!/bin/sh
# trace-commit.sh
#
# 분할 커밋을 안전하게 만드는 헬퍼.
# 커밋 직전 staged 영역을 먼저 비운 뒤(이전 시도의 잔여 누적 방지),
# 지정한 경로만 정확히 stage하고 그 경로만으로 커밋한다.
#
# 이렇게 "한 커밋 = 내가 지정한 경로뿐"을 강제해서,
# git commit이 staged 전체를 담는 탓에 무관한 변경이 엉뚱한 커밋에 섞이는 사고를 막는다.
#
# 정책:
# - main에서는 커밋하지 않는다(pre-commit 훅과 동일 정책).
# - push는 하지 않는다. 최종 push는 사용자가 직접 수행한다.
# - git add -A / git add . 를 쓰지 않는다. 경로를 명시해서만 stage한다.
#
# 주의:
# - 시작 시 git reset으로 staged를 비운다. 의도적으로 미리 stage해 둔 것이 있다면
#   이 헬퍼를 쓰지 말고 직접 커밋하거나, 그 경로도 인자로 함께 넘긴다.
# - 커밋 메시지 본문은 비어 있지 않은 3~4줄이어야 한다(commit-msg 훅 요건).
#
# 사용법:
#   scripts/trace-commit.sh -m "tag: 한국어 제목
#
#   - 본문 1
#   - 본문 2
#   - 본문 3" -- <path>...
#
#   예:
#   scripts/trace-commit.sh -m "docs: 하루 회고 아카이브
#
#   - 2026-06-17 회고 마크다운과 HTML을 history에 추가한다
#   - 의사결정과 교훈을 다음 세션이 참고하도록 남긴다
#   - 인포그래픽으로 하루 흐름을 함께 정리한다" -- history/260617_daily_retro.md history/260617_daily_retro.html

set -eu

if [ "${1:-}" != "-m" ] || [ -z "${2:-}" ]; then
  echo "usage: scripts/trace-commit.sh -m \"메시지\" [--] <path>..." >&2
  exit 1
fi
msg="$2"
shift 2

# 선택적 -- 구분자
if [ "${1:-}" = "--" ]; then
  shift
fi

if [ "$#" -eq 0 ]; then
  echo "trace-commit: 커밋할 경로를 하나 이상 지정하세요." >&2
  exit 1
fi

branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [ "$branch" = "main" ]; then
  echo "trace-commit: main에서는 커밋하지 않습니다. feature 브랜치를 먼저 파세요." >&2
  exit 1
fi

# 1) staged 비우기 — 이전 잔여가 이 커밋에 섞이지 않게 한다(워킹트리는 보존).
git reset -q

# 2) 지정한 경로만 stage (삭제·이름변경 포함).
git add -- "$@"

# 3) 실제로 stage된 변경이 있는지 확인.
if git diff --cached --quiet; then
  echo "trace-commit: 지정한 경로에 staged 변경이 없습니다: $*" >&2
  exit 1
fi

echo "이 커밋에 담길 변경:"
git diff --cached --name-status

# 4) 커밋. 메시지 형식은 commit-msg 훅이 검증한다.
git commit -m "$msg"
