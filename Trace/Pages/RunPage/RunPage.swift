import MapKit
import SwiftUI

struct RunPage: View {
    @State private var viewModel: RunPageViewModel

    init(session: RunSession) {
        _viewModel = State(initialValue: RunPageViewModel(session: session))
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
            startButton
        case .acquiring:
            acquiringPanel
        case .tracking:
            RunStatsPanel(viewModel: viewModel)
        case .summary:
            RunSummaryPanel(viewModel: viewModel)
        }
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
        HStack(spacing: 10) {
            ProgressView()
            Text("GPS 신호 찾는 중…")
                .font(DesignToken.Typography.subtitle)
                .foregroundStyle(DesignToken.Color.ink)
            Button("취소") { viewModel.cancelAcquiring() }
                .font(DesignToken.Typography.chip)
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
