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

    private var expandedSegmentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("구간")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Button {
                    isSegmentPanelExpanded = false
                } label: {
                    Image(systemName: "chevron.up")
                }
                .accessibilityIdentifier("coursePlanner.segmentPanel.collapse")
            }

            ForEach(Array((viewModel.course?.segments ?? []).enumerated()), id: \.offset) { index, segment in
                Button {
                    viewModel.selectSegment(at: index)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(uiColor: SegmentPalette.color(at: colorKey(at: index))))
                            .frame(width: 10, height: 10)
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.0fm", segment.distanceMeters))
                                .font(.caption)
                            Text(String(format: "누적 %.2fkm", cumulativeDistanceMeters(upTo: index) / 1000))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coursePlanner.segmentPanel.item.\(index)")
            }
        }
        .padding(12)
        .frame(minWidth: 220)
    }

    private func cumulativeDistanceMeters(upTo index: Int) -> Double {
        guard let segments = viewModel.course?.segments, index < segments.count else { return 0 }
        return segments.prefix(through: index).reduce(0) { $0 + $1.distanceMeters }
    }

    // segmentColorKeys는 attach 생성 순서(prepend에도 색상이 안정적으로 유지됨)
    private func colorKey(at index: Int) -> Int {
        let keys = viewModel.segmentColorKeys
        return index < keys.count ? keys[index] : index
    }
}
