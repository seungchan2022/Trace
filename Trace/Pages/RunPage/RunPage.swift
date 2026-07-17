import MapKit
import SwiftUI

struct RunPage: View {
    @State private var viewModel: RunPageViewModel
    @State private var historyViewModel: RunHistoryViewModel
    @State private var showsHistory = false

    init(session: RunSession, recordRepository: RunRecordRepositoryProtocol, announcer: VoiceAnnouncerProtocol) {
        _viewModel = State(initialValue: RunPageViewModel(session: session, announcer: announcer))
        _historyViewModel = State(initialValue: RunHistoryViewModel(repository: recordRepository))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            runMap
            controls
        }
        .onChange(of: viewModel.session.track.samples.count) {
            viewModel.refreshPolylineIfDue()
        }
        .alert("정확한 위치가 꺼져 있어요", isPresented: $viewModel.showsAccuracyAlert) {
            Button("설정 열기") { openSettings() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("러닝 경로를 기록하려면 설정 > 개인정보 보호 > 위치 서비스에서 정확한 위치를 켜 주세요.")
        }
        .alert("위치 권한이 필요해요", isPresented: $viewModel.showsPermissionAlert) {
            Button("설정 열기") { openSettings() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("러닝을 기록하려면 위치 접근을 허용해 주세요.")
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.session.state == .idle {
                Button { showsHistory = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(GlassIconButtonStyle())
                .padding(.trailing, DesignToken.Size.screenMargin)
                .accessibilityIdentifier("run.historyButton")
            }
        }
        .overlay {
            if let count = viewModel.countdown {
                countdownOverlay(count: count)
            }
        }
        .onChange(of: viewModel.countdown) { _, newValue in
            guard newValue != nil else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred() // 숫자마다 햅틱(스펙 §1.1)
        }
        .sheet(isPresented: $showsHistory) {
            RunHistorySheet(viewModel: historyViewModel)
        }
    }

    private func countdownOverlay(count: Int) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            Text("\(count)")
                .font(.system(size: 160, weight: .heavy, design: .rounded))
                .foregroundStyle(DesignToken.Color.accent)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: count)
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.cancelCountdown() } // 취소 = 화면 탭(스펙 §1.1)
        .accessibilityIdentifier("run.countdownOverlay")
    }

    private var runMap: some View {
        Map(position: $viewModel.cameraPosition) {
            UserAnnotation()
            if viewModel.displayedCoordinates.count >= 2 {
                MapPolyline(coordinates: viewModel.displayedCoordinates)
                    .stroke(DesignToken.Color.accent, lineWidth: 5)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.session.state {
        case .idle:
            startControls
        case .acquiring:
            acquiringPanel
        case .tracking, .paused:
            RunStatsPanel(viewModel: viewModel)
        case .summary:
            RunSummaryPanel(viewModel: viewModel)
        }
    }

    private var startControls: some View {
        VStack(spacing: 16) {
            goalPicker
            startButton
        }
    }

    private var goalPicker: some View {
        VStack(spacing: 10) {
            Picker("목표", selection: $viewModel.goalMode) {
                ForEach(RunGoalMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            switch viewModel.goalMode {
            case .open:
                EmptyView()
            case .distance:
                Picker("목표 거리", selection: $viewModel.goalDistanceKm) {
                    ForEach(1...42, id: \.self) { km in
                        Text("\(km) km").tag(km)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 96)
            case .time:
                Picker("목표 시간", selection: $viewModel.goalTimeMinutes) {
                    ForEach(Array(stride(from: 5, through: 180, by: 5)), id: \.self) { minutes in
                        Text("\(minutes)분").tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 96)
            }
        }
        .padding(DesignToken.Size.sheetPadding)
        .background(DesignToken.Color.surface, in: RoundedRectangle(cornerRadius: DesignToken.Corner.chrome))
        .padding(.horizontal, DesignToken.Size.screenMargin)
        .accessibilityIdentifier("run.goalPicker")
    }

    private var startButton: some View {
        Button {
            Task { await viewModel.startTapped() }
        } label: {
            Text("시작")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(DesignToken.Color.accentInk)
                .frame(width: 96, height: 96)
                .background(DesignToken.Color.accent, in: Circle())
        }
        .padding(.bottom, 40)
    }

    private var acquiringPanel: some View {
        VStack(spacing: 10) {
            if viewModel.session.isSignalWeak {
                Text("GPS 신호 약함")
                    .font(DesignToken.Typography.chip)
                    .foregroundStyle(DesignToken.Color.danger)
            }
            HStack(spacing: 10) {
                ProgressView()
                Text("GPS 신호 찾는 중…")
                    .font(DesignToken.Typography.subtitle)
                    .foregroundStyle(DesignToken.Color.ink)
                Button("취소") { viewModel.cancelAcquiring() }
                    .font(DesignToken.Typography.chip)
            }
        }
        .padding(DesignToken.Size.sheetPadding)
        .background(DesignToken.Color.surface, in: RoundedRectangle(cornerRadius: DesignToken.Corner.chrome))
        .padding(.bottom, 40)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
