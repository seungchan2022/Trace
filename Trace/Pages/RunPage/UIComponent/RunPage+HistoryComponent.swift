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
    @State private var pendingWaypointDeleteIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            detailMap
            ScrollView {
                statsGrid
                    .padding(DesignToken.Size.sheetPadding)
                if let loadedRun, let goalLabel = RunGoalFormatter.label(loadedRun.goal) {
                    Label(goalLabel, systemImage: "target")
                        .font(DesignToken.Typography.chip)
                        .foregroundStyle(DesignToken.Color.ink2)
                        .padding(.bottom, 8)
                }
                if let loadedRun {
                    RunSplitsSection(result: RunSplitCalculator.splits(
                        samples: loadedRun.samples, pauses: loadedRun.pauses,
                        sessionStart: loadedRun.summary.startedAt, totalActiveSeconds: loadedRun.summary.duration
                    ))
                }
                if let loadedRun, loadedRun.waypoints.isEmpty == false {
                    RunWaypointsSection(
                        run: loadedRun,
                        segments: RunWaypointSegmentsCalculator.segments(
                            waypoints: loadedRun.waypoints,
                            totalDistanceMeters: loadedRun.summary.distanceMeters
                        ),
                        onDeleteWaypoint: { pendingWaypointDeleteIndex = $0 }
                    )
                }
            }
        }
        .navigationTitle(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadedRun = await viewModel.loadRun(id: summary.id)
            loadFinished = true
        }
        .alert(
            "포인트 \((pendingWaypointDeleteIndex ?? 0) + 1)번을 삭제할까요?",
            isPresented: Binding(
                get: { pendingWaypointDeleteIndex != nil },
                set: { if $0 == false { pendingWaypointDeleteIndex = nil } }
            )
        ) {
            Button("삭제", role: .destructive) {
                guard let index = pendingWaypointDeleteIndex, let run = loadedRun else { return }
                pendingWaypointDeleteIndex = nil
                Task {
                    if let updated = await viewModel.deleteWaypoint(from: run, at: index) {
                        loadedRun = updated // 구간 표·마커 재계산은 body가 파생(스펙 §2.5)
                    }
                }
            }
            Button("취소", role: .cancel) { pendingWaypointDeleteIndex = nil }
        } message: {
            Text("구간 거리는 앞뒤 구간에 합쳐집니다")
        }
        .alert("포인트를 삭제하지 못했어요", isPresented: Bindable(viewModel).showsWaypointDeleteFailure) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("잠시 후 다시 시도해 주세요")
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
                ForEach(Array(loadedRun.waypoints.enumerated()), id: \.offset) { index, waypoint in
                    Annotation("", coordinate: CLLocationCoordinate2D(
                        latitude: waypoint.latitude, longitude: waypoint.longitude
                    )) {
                        WaypointMarkerBadge(number: index + 1)
                    }
                }
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

/// 지도 궤적 위 포인트 번호 마커(스펙 §2.5)
struct WaypointMarkerBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(DesignToken.Color.accent, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}

/// 포인트 구간 표(스펙 §2.5) — km 스플릿 표와 별도 섹션, 포인트 없는 기록은 섹션 자체가 숨는다.
/// 비-final 행의 삭제 버튼 = 그 행의 끝 포인트 삭제(다음 구간과 병합) — 오탭 복구 경로
private struct RunWaypointsSection: View {
    let run: SavedRun
    let segments: [RunWaypointSegment]
    let onDeleteWaypoint: (Int) -> Void // 인자: 삭제할 포인트의 0-기반 인덱스

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("포인트 구간")
                .font(DesignToken.Typography.sectionLabel)
                .foregroundStyle(DesignToken.Color.ink2)
            ForEach(segments, id: \.index) { segment in
                HStack {
                    Text(Self.label(for: segment))
                        .font(DesignToken.Typography.segmentRowTitle)
                        .foregroundStyle(DesignToken.Color.ink)
                    Spacer()
                    Text(String(format: "%.2f km", segment.distanceMeters / 1000))
                        .font(DesignToken.Typography.segmentRowDistance)
                        .monospacedDigit()
                        .foregroundStyle(DesignToken.Color.ink)
                    if segment.endsAtFinish == false {
                        Button {
                            onDeleteWaypoint(segment.index - 1) // 행의 끝 포인트(1-기반 → 0-기반)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(DesignToken.Color.ink2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("run.deleteWaypoint.\(segment.index)")
                    } else {
                        // final 행은 버튼 없이 폭만 맞춘다(정렬 유지)
                        Image(systemName: "xmark.circle.fill").opacity(0)
                    }
                }
            }
        }
        .padding(.horizontal, DesignToken.Size.sheetPadding)
        .padding(.bottom, DesignToken.Size.sheetPadding)
    }

    /// "시작 → ①" / "① → ②" / "③ → 종료"
    static func label(for segment: RunWaypointSegment) -> String {
        let from = segment.index == 1 ? "시작" : circled(segment.index - 1)
        let to = segment.endsAtFinish ? "종료" : circled(segment.index)
        return "\(from) → \(to)"
    }

    /// 1 → "①" … 20 → "⑳" (유니코드 원문자 범위 밖이면 일반 숫자)
    static func circled(_ number: Int) -> String {
        guard (1...20).contains(number),
              let scalar = Unicode.Scalar(0x2460 + number - 1) else { return "\(number)" }
        return String(Character(scalar))
    }
}
