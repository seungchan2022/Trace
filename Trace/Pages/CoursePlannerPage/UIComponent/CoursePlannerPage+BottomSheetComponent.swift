import SwiftUI

extension CoursePlannerPage {
    var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
            if isBottomSheetExpanded {
                expandedSheetBody
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
        .accessibilityIdentifier("coursePlanner.segmentPanel")
    }

    // 기존 statusPanel 내용을 그대로 흡수 — 헤더는 항상 보이고, 탭하면 구간 리스트가 펼쳐진다.
    private var sheetHeader: some View {
        Button {
            isBottomSheetExpanded.toggle()
            // 펼침 시엔 expandedSheetBody의 ScrollViewReader.onAppear(restoreScrollPosition)가
            // 위치 복원을 전담하므로 여기선 접힘(collapse) 케이스만 기록한다.
            if !isBottomSheetExpanded {
                let keys = viewModel.segmentColorKeys
                let anchorIndex = panelAnchorColorKey.flatMap { keys.firstIndex(of: $0) }
                let latestIndex = SegmentPanelLogic.latestIndex(colorKeys: keys)
                panelWasNearLatestAtCollapse = SegmentPanelLogic.shouldAutoScroll(
                    anchorIndex: anchorIndex, previousLatestIndex: latestIndex
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isLoading {
                    Text("경로 계산 중")
                        .accessibilityIdentifier("coursePlanner.loading")
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("coursePlanner.error")
                } else if let infoMessage = viewModel.infoMessage {
                    Text(infoMessage)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("coursePlanner.info")
                } else if let distanceText = viewModel.distanceText {
                    HStack(spacing: 6) {
                        Text(distanceText)
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("coursePlanner.distance")
                        if viewModel.roundTripHintVisible {
                            Text("· 출발핀을 탭하면 왕복 완성")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("coursePlanner.roundTripHint")
                        }
                    }
                } else {
                    Text(viewModel.isDrawingMode ? "경로를 그려주세요" : "지도에서 출발지를 선택하세요")
                        .accessibilityIdentifier("coursePlanner.prompt")
                }

                HStack(spacing: 12) {
                    Button { viewModel.isSavePromptPresented = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(!viewModel.canSaveCourse)
                    .accessibilityIdentifier("coursePlanner.saveCourse")

                    Button { viewModel.insertWholeCourseRoundTrip() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!viewModel.canInsertWholeCourseRoundTrip)
                    .accessibilityIdentifier("coursePlanner.wholeCourseRoundTrip")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coursePlanner.segmentPanel.collapsed")
    }

    // 행 identity는 colorKey(생성 순번) — prepend로 인덱스가 밀려도 행 정체성과
    // scrollTo 대상이 안정적으로 유지된다 (MVP7 colorKey와 같은 원리).
    private struct PanelRow: Identifiable {
        let index: Int
        let colorKey: Int
        let segment: CourseSegment
        var id: Int { colorKey }
    }

    private var panelRows: [PanelRow] {
        let segments = viewModel.course?.segments ?? []
        let keys = viewModel.segmentColorKeys
        return segments.enumerated().map { index, segment in
            PanelRow(index: index, colorKey: index < keys.count ? keys[index] : index, segment: segment)
        }
    }

    private var expandedSheetBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(panelRows) { row in
                            segmentRow(row)
                        }
                    }
                    .scrollTargetLayout()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        panelContentHeight = height
                    }
                }
                // ScrollView는 greedy — 내용이 적으면 내용 높이만큼, 많으면 지도 높이 40% 상한
                .frame(height: min(panelContentHeight, panelMaxListHeight))
                // 콘텐츠 여백만 12pt로 주고 스크롤 인디케이터는 기본 여백(에지에 붙게) 유지 —
                // .padding()으로 ScrollView 전체를 감싸면 인디케이터까지 같이 밀려 보인다 (실기기 QA 발견).
                .contentMargins(.horizontal, 12, for: .scrollContent)
                .contentMargins(.bottom, 12, for: .scrollContent)
                .scrollPosition(id: $panelAnchorColorKey, anchor: .center)
                .onAppear {
                    restoreScrollPosition(proxy)
                }
                .onChange(of: viewModel.segmentColorKeys.max()) { oldMax, newMax in
                    // 증가(새 구간)일 때만 — undo/clear로 줄어들 때는 보던 위치 유지 (스펙)
                    guard let newMax, newMax > (oldMax ?? Int.min) else { return }
                    autoScrollIfNearLatest(proxy, previousMaxKey: oldMax)
                }
            }
        }
        .frame(minWidth: 220)
    }

    private func segmentRow(_ row: PanelRow) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.selectSegment(at: row.index)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(uiColor: SegmentPalette.color(at: row.colorKey)))
                        .frame(width: 10, height: 10)
                    Text("\(row.index + 1)")
                        .font(.caption.weight(.semibold))
                    if row.segment.isRoundTrip {
                        // 왕복 구간 표식 — 저장·불러오기를 통과해도 유지된다 (스펙 §4)
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("왕복 구간")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0fm", row.segment.distanceMeters))
                            .font(.caption)
                        Text(String(format: "누적 %.2fkm", cumulativeDistanceMeters(upTo: row.index) / 1000))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coursePlanner.segmentPanel.item.\(row.index)")

            // 왕복 추가: 이 구간 뒤에 "갔다 되돌아오기" 삽입 (스펙 §4)
            Button {
                viewModel.insertRoundTrip(afterColorKey: row.colorKey)
            } label: {
                Image(systemName: "arrow.uturn.down.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canInsertRoundTrip(afterColorKey: row.colorKey))
            .accessibilityIdentifier("coursePlanner.segmentPanel.roundTrip.\(row.index)")
        }
    }

    // 새 구간 추가 시: 직전 최신 구간 근처를 보고 있을 때만 최신으로 스크롤 (채팅 앱 방식)
    private func autoScrollIfNearLatest(_ proxy: ScrollViewProxy, previousMaxKey: Int?) {
        let keys = viewModel.segmentColorKeys
        guard let maxKey = keys.max() else { return }
        let anchorIndex = panelAnchorColorKey.flatMap { keys.firstIndex(of: $0) }
        let previousLatestIndex = previousMaxKey.flatMap { keys.firstIndex(of: $0) }
        guard SegmentPanelLogic.shouldAutoScroll(
            anchorIndex: anchorIndex, previousLatestIndex: previousLatestIndex
        ) else { return }
        withAnimation {
            proxy.scrollTo(maxKey, anchor: .bottom)
        }
    }

    // 재펼침 시: 접기 직전 최신 근처였다면 최신을 계속 따라간다(접혀 있는 동안 구간이
    // 늘었을 수 있으므로 "그때의 최신"이 아니라 "지금의 최신"). 그렇지 않으면 보던 위치를
    // 복원하고, 없으면(첫 펼침/해당 행 삭제됨) 최신 구간으로 fallback.
    private func restoreScrollPosition(_ proxy: ScrollViewProxy) {
        let keys = viewModel.segmentColorKeys
        if panelWasNearLatestAtCollapse, let maxKey = keys.max() {
            proxy.scrollTo(maxKey, anchor: .bottom)
        } else if let anchor = panelAnchorColorKey, keys.contains(anchor) {
            proxy.scrollTo(anchor, anchor: .center)
        } else if let maxKey = keys.max() {
            proxy.scrollTo(maxKey, anchor: .bottom)
        }
    }

    private func cumulativeDistanceMeters(upTo index: Int) -> Double {
        guard let segments = viewModel.course?.segments, index < segments.count else { return 0 }
        return segments.prefix(through: index).reduce(0) { $0 + $1.distanceMeters }
    }
}
