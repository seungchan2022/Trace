import SwiftUI

extension CoursePlannerPage {
    var segmentPanel: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if isSegmentPanelExpanded {
                expandedSegmentList
            } else {
                collapsedSegmentChip
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
        .accessibilityIdentifier("coursePlanner.segmentPanel")
    }

    private var collapsedSegmentChip: some View {
        Button {
            isSegmentPanelExpanded = true
        } label: {
            Text(viewModel.distanceText ?? "0.00 km")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
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

    private var expandedSegmentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("구간")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Button {
                    // 접기 전, 지금 보던 위치가 최신 근처였는지 기록 — 재펼침 시 이 값으로
                    // "옛 위치 복원" vs "최신 계속 따라가기"를 가른다 (autoScrollIfNearLatest와 동일 판정 로직).
                    let keys = viewModel.segmentColorKeys
                    let anchorIndex = panelAnchorColorKey.flatMap { keys.firstIndex(of: $0) }
                    let latestIndex = SegmentPanelLogic.latestIndex(colorKeys: keys)
                    panelWasNearLatestAtCollapse = SegmentPanelLogic.shouldAutoScroll(
                        anchorIndex: anchorIndex, previousLatestIndex: latestIndex
                    )
                    isSegmentPanelExpanded = false
                } label: {
                    Image(systemName: "chevron.up")
                }
                .accessibilityIdentifier("coursePlanner.segmentPanel.collapse")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

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
        Button {
            viewModel.selectSegment(at: row.index)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(uiColor: SegmentPalette.color(at: row.colorKey)))
                    .frame(width: 10, height: 10)
                Text("\(row.index + 1)")
                    .font(.caption.weight(.semibold))
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
