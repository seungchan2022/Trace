import SwiftUI

// 그래버·헤더·리스트가 공유하는 시트 이동 제스처 모음. 원래 CoursePlannerPage+BottomSheetComponent.swift에
// 있었으나, 리스트 인계 제스처(listHandoffGesture)를 추가하며 그 파일이 SwiftLint file_length(500줄)
// 상한을 넘어 이 파일로 분리했다(2026-07-26) — 내용은 그대로이고 위치와 접근 수준(private → internal,
// 다른 파일의 grabberHandle/sheetHeader/expandedSheetBody에서 참조해야 하므로)만 바뀌었다.
extension CoursePlannerPage {
    // 그래버(38x5, 상하 10pt 패딩)만으로는 손가락으로 잡기엔 너무 좁다는 실기기 피드백(2026-07-12)
    // — sheetHeader 영역 전체에서도 드래그가 되도록 이 제스처를 sheetHeader의 배경(뒷면 레이어)에도
    // 건다. 배경은 foreground(버튼들)와 별개 형제 레이어라 히트테스트가 경쟁하지 않는다 — sheetHeader나
    // 시트 전체에 *직접* 걸면(래핑) 그 안의 Button들이 전부 먹통이 되는 회귀가 실제로 있었다
    // (2026-07-12, bottomSheet 배경 히트테스트 백스톱 작업 중 확인). 그래버 자체에도 남겨 시각적
    // 어포던스가 있는 곳에서도 그대로 동작하게 한다.
    // 그래버·헤더·리스트가 공유하는 단일 이동 규칙 — 40pt를 넘게 끌면 그 방향으로 한 단계.
    // 한 번의 드래그는 아무리 길어도 한 단계만 움직인다(2026-07-26 사용자 확정: 시트는
    // 기본↔중간↔풀을 한 칸씩 지나간다). 진입점은 늘리되 규칙은 하나로 둔다.
    func detentAfterDrag(translationHeight: CGFloat) -> SheetDetent? {
        let threshold: CGFloat = 40
        guard abs(translationHeight) > threshold else { return nil }
        return translationHeight < 0 ? sheetDetent.steppedUp : sheetDetent.steppedDown
    }

    var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                // 탭 토글도 경로 유무와 무관하게 기본↔중간을 오가므로, 드래그도 똑같이 경로
                // 유무와 무관하게 단계를 이동한다 — 둘의 동작이 다르면 안 된다는 사용자 확인
                // (2026-07-12: "빈 경로일 때 버튼을 누르면 시트가 올라가는데 드래그로는 안돼").
                guard let nextDetent = detentAfterDrag(translationHeight: value.translation.height) else { return }
                // Gesture의 onEnded는 Button 액션과 달리 SwiftUI가 안전하게 지연 디스패치하지
                // 않는다 — 여기서 곧바로 @State를 쓰면 "Modifying state during view update"
                // 경고가 발생한다(2026-07-12 실기기 콘솔 로그로 재현·확정, 탭 토글에서는 없음).
                // 다음 런루프로 한 틱 미뤄 현재 진행 중인 뷰 업데이트 트랜잭션 밖에서 쓰게 한다.
                DispatchQueue.main.async {
                    setSheetDetent(nextDetent)
                }
            }
    }

    // 리스트가 스크롤 끝에 붙어 있는 동안의 드래그를 시트로 넘기는 게이트.
    //
    // 동시 인식(simultaneous)이라 ScrollView의 스크롤 소유권을 뺏지 않는다. 그래버·헤더에서
    // 쓴 "배경 레이어에 걸기" 우회는 여기서 못 쓴다 — 배경은 스크롤 콘텐츠 뒤에 있어 터치가
    // 닿지 않는다. 최소 이동 거리 8pt라 탭에는 발동하지 않으므로, 제스처로 뷰를 감쌌다가
    // 안쪽 버튼이 전부 먹통이 됐던 2026-07-12 회귀의 경로는 타지 않는다.
    // 래치가 남는 경우(제스처 취소, 백그라운드 전환, 인계로 리스트 자체가 사라짐)에 대비해
    // Step 6에서 .onDisappear와 sheetDetent 변화에도 비운다. 남더라도 **더 허용적이 되지는
    // 않는다** — 다음 드래그의 첫 콜백에서 곧바로 현재 상태와 교집합을 취하므로, 최악이
    // "인계가 한 번 씹힘"이지 "안 해야 할 인계를 함"이 아니다. 그래도 씹힘은 감각 문제로
    // 오인되기 쉬워 명시적으로 비운다.
    var listHandoffGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { _ in
                // 드래그 내내 유지된 끝 접촉만 인계 자격이 있다(ScrollEdgeState.intersected 주석 참고).
                listDragEdge = listDragEdge?.intersected(with: listScrollEdge) ?? listScrollEdge
            }
            .onEnded { value in
                let maintainedEdge = listDragEdge
                listDragEdge = nil
                guard let maintainedEdge,
                      let nextDetent = detentAfterDrag(translationHeight: value.translation.height)
                else { return }
                // 그 끝을 벗어나는 방향으로 끌었을 때만 넘긴다. 맨 위에서 아래로 = 축소,
                // 맨 아래에서 위로 = 확대. 반대 방향은 갈 곳이 남아 있으므로 그냥 스크롤이다.
                let goingUp = value.translation.height < 0
                guard goingUp ? maintainedEdge.isAtBottom : maintainedEdge.isAtTop else { return }
                DispatchQueue.main.async {
                    setSheetDetent(nextDetent)
                }
            }
    }
}
