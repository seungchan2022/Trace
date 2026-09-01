# Trace 제품 기준선

Trace가 지금 어떤 문제를 다루고 어떤 경험을 약속하는지 설명하는 제품 방향의 정본이다. 구현 요구사항과 진행 상태는 각각 spec·plan·roadmap을, 현재 진행 상황은 [현재 MVP 현황판](current-mvp.md)을 따른다.

## 시작 배경과 현재 문제

Trace의 기록상 최초 약속은 **"달리기 전에 오늘 어디를 뛸지 정한다"**였다. 지도 위 두 지점을 고르면 물·건물·하천을 가로지르는 직선이 아니라 실제로 걸을 수 있는 경로와 거리를 확인하게 하려는 출발점이었다. 초기 MVP는 이 경험만 검증했으며, 검색·저장·기록·계정·동기화는 의도적으로 범위 밖이었다. [MVP1 코스 계획 설계](../history/mvp1/2026-06-17-route-planner-mvp-design.md) · [MVP1 완료 회고](../history/mvp1/260622_mvp1_completion_retro.md)

현재 Trace가 다루는 문제는 달리기 전의 선택과 달리면서 남는 경험을 서로 종속시키지 않고 지원하는 것이다. 코스와 실제 러닝이 다시 만나는 경험은 후속 질문으로 남아 있다. [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md)

## 현재 제품 약속: 두 독립 기둥

- **코스 계획:** 달리기 전에 갈 경로와 거리를 정하고, 필요하면 직접 표현한 경로를 실제 보행 경로에 맞춘다. [MVP1 코스 계획 설계](../history/mvp1/2026-06-17-route-planner-mvp-design.md) · [그리기·스냅 설계](../history/mvp1/2026-06-20-marker-draw-snap-mvp-design.md)
- **러닝·기록:** 코스를 고르지 않아도 바로 달리고, GPS 기반 러닝 경험을 남겨 나중에 돌아볼 수 있다. 이 기둥은 코스 계획의 부속 단계가 아니라 독립 경험으로 결정됐다. [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md) · [MVP13 완료 회고](../history/mvp13/260715_mvp13_completion_retro.md)

## 제품 원칙

- 두 기둥은 각각만으로도 완결되어야 하며, 코스를 골라 달리거나 계획과 실제를 비교하는 연동은 그 위에 별도로 결정한다. [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md)
- 실제 사용과 실기기 확인에서 드러난 문제는 화면 장식으로 덮지 않고 경험의 목적을 다시 점검한다. 러닝 탭의 요약 줄은 그 목적을 설명하지 못한다는 확인 뒤, "오늘의 러닝 → 목표 설정 → 시작" 흐름으로 다시 정리됐다. [MVP17 완료 회고](../history/mvp17/260727_mvp17_completion_retro.md)
- 제품 약속은 기능 목록이 아니라 사용자가 달리기 전·중·후에 무엇을 선택하고 이해하는지로 판단한다. 초기 코스 계획도 가장 작은 선택→경로→거리 경험만 먼저 검증했다. [MVP1 코스 계획 설계](../history/mvp1/2026-06-17-route-planner-mvp-design.md)

## 사용자와 AI의 역할

- **사용자:** 실제 사용에서 불편과 우선순위를 판단하고, 제품 방향·범위·완료 수용을 결정한다. MVP17의 화면 보강도 실사용 관찰과 사용자 수용을 근거로 조정됐다. [MVP17 완료 회고](../history/mvp17/260727_mvp17_completion_retro.md)
- **AI:** 설계·구현·검증·기록 작업을 돕되, 사용자의 동기나 제품 결정을 대신 확정하지 않는다. 현재 근거에는 최종 사용자에게 제공되는 AI 기능이나 조언 역할이 정의돼 있지 않다. 이 구분은 제품 기능의 부재가 아니라 기록된 근거의 범위다. [초기 일일 회고](../history/daily-retro/260616_daily_retro.md) · [MVP17 완료 회고](../history/mvp17/260727_mvp17_completion_retro.md)

## 주요 방향 전환

1. **코스 계획의 최소 검증에서 직접 표현으로:** 두 지점의 실제 경로 확인으로 시작한 뒤, 사용자가 그린 경로를 도로에 맞추는 방식으로 계획 표현을 넓혔다. [MVP1 코스 계획 설계](../history/mvp1/2026-06-17-route-planner-mvp-design.md) · [그리기·스냅 설계](../history/mvp1/2026-06-20-marker-draw-snap-mvp-design.md)
2. **"계획 뒤에 기록"에서 두 기둥으로:** 러닝은 계획의 다음 단계가 아니라 코스 없이도 시작할 수 있는 독립 경험으로 재정의했다. [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md)
3. **정보를 더하는 처방에서 시작 경험의 재검토로:** MVP17은 기록을 보는 맥락과 지금 시작하는 맥락을 분리했고, 러닝 탭의 임시 요약 처방을 실기기 확인 뒤 철회했다. [MVP17 킥오프 결정](../history/mvp17/2026-07-21-mvp17-run-history-kickoff-design.md) · [MVP17 완료 회고](../history/mvp17/260727_mvp17_completion_retro.md)

## 현재 한계와 열린 질문

- 기록된 문서만으로는 사용자의 최종 동기, 목표 사용자상, 또는 장기 제품 포지셔닝을 확정할 수 없다. 이 기준선은 확인된 결정의 요약이며, 그 표현이 맞는지는 사용자의 검토가 필요하다. [초기 일일 회고](../history/daily-retro/260616_daily_retro.md) · [MVP1 완료 회고](../history/mvp1/260622_mvp1_completion_retro.md)
- 코스 연동과 계획 대비 실제 비교는 두 기둥 위의 후속 경험으로 남아 있으며, 다음 MVP로 확정된 범위는 아니다. [MVP13 러닝 트래킹 설계](../history/mvp13/2026-07-13-run-tracking-design.md) · [MVP17 완료 회고](../history/mvp17/260727_mvp17_completion_retro.md)
- MVP17이 다룬 "러닝 탭이 초라하다"는 관찰은 완전 해소가 아니라 조건부 통과로 남아 있어, 앞으로의 실사용에서 다시 확인해야 한다. [MVP17 완료 회고](../history/mvp17/260727_mvp17_completion_retro.md)
