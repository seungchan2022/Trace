#!/bin/sh
# trace-integrate.sh
#
# 작업 브랜치를 main 위로 rebase한 뒤 fast-forward로 통합하고,
# 통합이 끝난 브랜치를 즉시 삭제한다.
#
# 이렇게 통합 루프를 한 번에 닫아서 "통합했지만 삭제하지 않은 브랜치"가
# 그래프에 갈래로 남는 일을 막는다.
#
# 정책:
# - push는 하지 않는다. 최종 push는 사용자가 직접 수행한다.
# - main 직접 rebase는 하지 않는다. 작업 브랜치를 main 위로 rebase한다.
#
# 사용법:
#   scripts/trace-integrate.sh [work-branch]
#   (인자를 생략하면 현재 체크아웃된 브랜치를 통합한다)

set -eu

MAIN="main"

work="${1:-$(git symbolic-ref --quiet --short HEAD || true)}"

if [ -z "$work" ]; then
  echo "integrate: 통합할 브랜치를 알 수 없습니다 (detached HEAD?)." >&2
  echo "사용법: scripts/trace-integrate.sh <work-branch>" >&2
  exit 1
fi

if [ "$work" = "$MAIN" ]; then
  echo "integrate: '$MAIN' 은 통합 대상이 아닙니다. 작업 브랜치명을 지정하세요." >&2
  exit 1
fi

if ! git show-ref --verify --quiet "refs/heads/$work"; then
  echo "integrate: 브랜치가 존재하지 않습니다: $work" >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "integrate: 커밋되지 않은 변경이 있습니다. 먼저 커밋하거나 정리하세요." >&2
  exit 1
fi

echo "==> '$work' 를 '$MAIN' 위로 rebase"
git switch "$work"
git rebase "$MAIN"

echo "==> '$MAIN' 으로 fast-forward 통합"
git switch "$MAIN"
ALLOW_MAIN_MERGE=1 git merge --ff-only "$work"

echo "==> 통합이 끝난 '$work' 삭제"
git branch -d "$work"

echo ""
echo "완료: '$MAIN' 가 $(git rev-parse --short HEAD) 로 통합되었습니다."
echo "push는 정책상 사용자가 직접 수행합니다:"
echo "  ALLOW_PUSH=1 git push origin $MAIN"
