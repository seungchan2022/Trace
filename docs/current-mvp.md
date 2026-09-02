# 현재 MVP 현황판

> 사용자용 진행 현황판이다. 구현 정본은 spec·plan·roadmap이며, 내용이 충돌하면 구현 정본을 따른다.

## 현재 상태

**진행 중인 MVP 없음.** 대신 **MVP 밖 독립 사이클 `pace-display`가 진행 중**이다.
백로그 착수 순서 1순위인 「페이스 표시·계산」 축(5건)을 다루며, 마일스톤 2개라 MVP 기준(2~5개)에
미달해 MVP 절차를 씌우지 않는다. 정본은 [로드맵](roadmap.md)이다.

- **현재 단계**: 마일스톤 `pace-definition`(작은 기능) — 설계 완료, 스펙 리뷰 대기
- **사용자가 결정한 것**
  - 잠금화면은 현재 페이스를 유지하고 라벨을 「현재 페이스」로 바꾼다 — 러닝 중 속도 조절이 목적이다
  - 트래킹 화면 보조 행에도 현재 페이스를 넣어 평균과 나란히 본다
  - 발화는 평균 페이스 그대로 둔다
  - 현재 페이스 창을 30초에서 줄인다(10초가 출발점)
- **아직 확인할 것**: 창의 최종값과 보조 행 세 항목 레이아웃 — 둘 다 실기기·시뮬레이터에서 정한다
- **다음 사용자 확인**: [설계 문서](superpowers/specs/2026-09-02-pace-definition-design.md) 리뷰

다음 마일스톤 `pace-dedup`(정비)은 이 마일스톤의 결정이 범위를 정하므로 뒤에 착수한다.

## 다음에 볼 곳

- 제품 전체 방향: [제품 기준선](product-baseline.md)
- 지금 앱이 제공하는 기능: [현재 기능 전수](current-features.md)
- 마지막 완료 MVP: [MVP17 — 러닝 기록 관리 + 대기 화면 보강](../history/mvp17/260727_mvp17_completion_retro.md)
- 다음 MVP 후보 선택: [백로그](backlog.md)

마지막 갱신: 2026-09-02
근거: [로드맵의 진행 중 / 예정 상태](roadmap.md#진행-중--예정) · [pace-definition 설계](superpowers/specs/2026-09-02-pace-definition-design.md) · [MVP17 완료 회고](../history/mvp17/260727_mvp17_completion_retro.md) · [현재 기능 전수](current-features.md)
