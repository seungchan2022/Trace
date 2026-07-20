import SwiftUI

struct RunPage: View {
    @State private var viewModel: RunPageViewModel
    @State private var historyViewModel: RunHistoryViewModel
    @State private var showsHistory = false
    @FocusState private var goalFieldFocused: Bool

    init(session: RunSession, recordRepository: RunRecordRepositoryProtocol, announcer: VoiceAnnouncerProtocol) {
        _viewModel = State(initialValue: RunPageViewModel(session: session, announcer: announcer))
        _historyViewModel = State(initialValue: RunHistoryViewModel(repository: recordRepository))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DesignToken.Color.surface2.ignoresSafeArea() // 지도 제거 — 러닝 탭은 Surface 배경(킥오프 §2.3)
            controls
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
        .onChange(of: viewModel.countdown) { _, newValue in
            guard newValue != nil else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred() // 숫자마다 햅틱(스펙 §1.1)
        }
        .sheet(isPresented: $showsHistory) {
            RunHistorySheet(viewModel: historyViewModel)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.session.state {
        case .idle:
            startControls
        case .countingDown:
            RunCountdownScreen(count: viewModel.countdown) { viewModel.cancelCountdown() }
        case .acquiring:
            acquiringPanel
        case .tracking, .paused:
            RunStatsPanel(viewModel: viewModel)
        case .summary:
            RunSummaryPanel(viewModel: viewModel)
        }
    }

    private var startControls: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { showsHistory = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(GlassIconButtonStyle())
                .accessibilityLabel("러닝 기록")
                .accessibilityIdentifier("run.historyButton")
            }
            .padding(.horizontal, DesignToken.Size.screenMargin)

            Spacer()
            goalPicker
            Spacer()
            startButton
            Spacer()
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                goalInputField(
                    text: $viewModel.goalDistanceInput, unit: "km", placeholder: "5.0", keyboard: .decimalPad
                )
            case .time:
                goalInputField(
                    text: $viewModel.goalTimeInput, unit: "분", placeholder: "30", keyboard: .numberPad
                )
            }
            if let error = viewModel.goalInputErrorText {
                Text(error)
                    .font(DesignToken.Typography.chipError)
                    .foregroundStyle(DesignToken.Color.danger)
            }
        }
        .padding(DesignToken.Size.sheetPadding)
        .background(DesignToken.Color.surface, in: RoundedRectangle(cornerRadius: DesignToken.Corner.chrome))
        .padding(.horizontal, DesignToken.Size.screenMargin)
        .accessibilityIdentifier("run.goalPicker")
    }

    private func goalInputField(
        text: Binding<String>, unit: String, placeholder: String, keyboard: UIKeyboardType
    ) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .focused($goalFieldFocused)
                .multilineTextAlignment(.trailing)
                .font(DesignToken.Typography.runSecondaryStat)
                .frame(maxWidth: 140)
            Text(unit) // 단위 상시 표시(스펙 §1.4, 사용자 요구)
                .font(DesignToken.Typography.subtitle)
                .foregroundStyle(DesignToken.Color.ink2)
        }
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { goalFieldFocused = false } // 명시적 dismiss(스펙 §1.4)
            }
        }
    }

    private var startButton: some View {
        Button {
            goalFieldFocused = false
            Task { await viewModel.startTapped() }
        } label: {
            Text("시작")
                .font(DesignToken.Typography.runStartButton)
                .foregroundStyle(DesignToken.Color.accentInk)
                .frame(width: 132, height: 132) // 화면 주인공 — 지도가 사라진 만큼 키운다(ui-direction §4)
                .background(DesignToken.Color.accent, in: Circle())
        }
        .disabled(viewModel.isGoalInputValid == false)
        .opacity(viewModel.isGoalInputValid ? 1 : 0.5)
        .accessibilityIdentifier("run.startButton")
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
