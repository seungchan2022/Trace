import MapKit
import SwiftUI

/// 기록 목록 시트 — 러닝 탭 대기 화면에서 진입(스펙 §4). 행은 요약 컬럼만 사용한다.
struct RunHistorySheet: View {
    let viewModel: RunHistoryViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.summaries.isEmpty {
                    ContentUnavailableView(
                        "아직 기록이 없어요",
                        systemImage: "figure.run",
                        description: Text("러닝을 마치면 기록이 자동으로 저장돼요")
                    )
                } else {
                    historyList
                }
            }
            .navigationTitle("러닝 기록")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SavedRunSummary.self) { summary in
                RunRecordDetailView(summary: summary, viewModel: viewModel)
            }
        }
        .presentationDetents([.medium, .large])
        .task { await viewModel.load() }
    }

    private var historyList: some View {
        List {
            ForEach(viewModel.summaries) { summary in
                NavigationLink(value: summary) {
                    RunHistoryRow(summary: summary)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .onDelete { indexSet in
                guard let first = indexSet.first else { return }
                viewModel.requestDelete(viewModel.summaries[first])
            }
        }
        .listStyle(.plain)
        .alert(
            "기록을 삭제할까요?",
            isPresented: Binding(
                get: { viewModel.pendingDelete != nil },
                set: { _ in }
            )
        ) {
            Button("삭제", role: .destructive) { Task { await viewModel.confirmPendingDelete() } }
            Button("취소", role: .cancel) { viewModel.cancelPendingDelete() }
        } message: {
            Text("삭제한 기록은 되돌릴 수 없습니다")
        }
        .alert("삭제하지 못했어요", isPresented: Bindable(viewModel).showsDeleteFailure) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("잠시 후 다시 시도해 주세요")
        }
    }
}

private struct RunHistoryRow: View {
    let summary: SavedRunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(DesignToken.Typography.segmentRowTitle)
                .foregroundStyle(DesignToken.Color.ink)
            Text(
                "\(String(format: "%.2f", summary.distanceMeters / 1000))km · "
                + "\(RunDurationFormatter.string(seconds: summary.duration)) · "
                + "\(RunPaceFormatter.string(secondsPerKm: summary.averagePaceSecondsPerKm))"
            )
            .font(DesignToken.Typography.segmentRowSubtitle)
            .foregroundStyle(DesignToken.Color.ink2)
        }
        .padding(.vertical, 4)
    }
}

/// 기록 상세 — 단건 blob을 읽어 경로를 그린다. 해독 실패 시 숫자는 컬럼 값으로 유지하고
/// 지도 영역만 안내로 강등한다(스펙 §6).
struct RunRecordDetailView: View {
    let summary: SavedRunSummary
    let viewModel: RunHistoryViewModel
    @State private var loadedRun: SavedRun?
    @State private var loadFinished = false

    var body: some View {
        VStack(spacing: 0) {
            detailMap
            ScrollView {
                statsGrid
                    .padding(DesignToken.Size.sheetPadding)
                if let loadedRun {
                    RunSplitsSection(result: RunSplitCalculator.splits(
                        samples: loadedRun.samples, pauses: loadedRun.pauses
                    ))
                }
            }
        }
        .navigationTitle(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadedRun = await viewModel.loadRun(id: summary.id)
            loadFinished = true
        }
    }

    @ViewBuilder
    private var detailMap: some View {
        if let loadedRun, loadedRun.samples.count >= 2 {
            let coordinates = loadedRun.samples.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            Map(initialPosition: RunRecordDetailView.fittedPosition(for: coordinates)) {
                MapPolyline(coordinates: coordinates)
                    .stroke(DesignToken.Color.accent, lineWidth: 5)
            }
        } else if loadFinished {
            ContentUnavailableView(
                "경로를 불러올 수 없어요",
                systemImage: "map",
                description: Text("기록 데이터에 문제가 있어 경로 표시만 건너뜁니다")
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statsGrid: some View {
        Grid(horizontalSpacing: 28, verticalSpacing: 12) {
            GridRow {
                statItem(String(format: "%.2f km", summary.distanceMeters / 1000), "거리")
                statItem(RunDurationFormatter.string(seconds: summary.duration), "시간")
            }
            GridRow {
                statItem(RunPaceFormatter.string(secondsPerKm: summary.averagePaceSecondsPerKm), "평균 페이스")
                statItem(String(format: "%.0f m", summary.elevationGainMeters), "고도 상승")
            }
        }
    }

    private func statItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(DesignToken.Typography.segmentRowDistance).monospacedDigit()
            Text(label).font(DesignToken.Typography.sectionLabel)
                .foregroundStyle(DesignToken.Color.ink2)
        }
    }

    /// 경로 전체가 보이도록 카메라 핏 (RunPageViewModel.fittingRegion과 같은 계산)
    private static func fittedPosition(for coordinates: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard let first = coordinates.first else { return .automatic }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude); maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude); maxLon = max(maxLon, coordinate.longitude)
        }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
            )
        ))
    }
}

/// km 스플릿 표 — 완성 구간은 1km 페이스(=구간 시간), 마지막 미완성 구간은 실거리 환산 페이스(스펙 §3.2)
private struct RunSplitsSection: View {
    let result: RunSplitResult

    var body: some View {
        if result.completed.isEmpty == false || result.partial != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("킬로미터별 페이스")
                    .font(DesignToken.Typography.sectionLabel)
                    .foregroundStyle(DesignToken.Color.ink2)
                ForEach(result.completed, id: \.index) { split in
                    row(
                        label: "\(split.index) km",
                        pace: RunPaceFormatter.string(secondsPerKm: split.paceSecondsPerKm)
                    )
                }
                if let partial = result.partial {
                    row(
                        label: String(format: "%.2f km", partial.distanceMeters / 1000),
                        pace: RunPaceFormatter.string(secondsPerKm: partialPace(partial))
                    )
                }
            }
            .padding(.horizontal, DesignToken.Size.sheetPadding)
            .padding(.bottom, DesignToken.Size.sheetPadding)
        }
    }

    private func partialPace(_ partial: RunSplitPartial) -> Double? {
        guard partial.distanceMeters > 0 else { return nil }
        return partial.durationSeconds / (partial.distanceMeters / 1000)
    }

    private func row(label: String, pace: String) -> some View {
        HStack {
            Text(label)
                .font(DesignToken.Typography.segmentRowTitle)
                .foregroundStyle(DesignToken.Color.ink)
            Spacer()
            Text(pace)
                .font(DesignToken.Typography.segmentRowDistance)
                .monospacedDigit()
                .foregroundStyle(DesignToken.Color.ink)
        }
    }
}
