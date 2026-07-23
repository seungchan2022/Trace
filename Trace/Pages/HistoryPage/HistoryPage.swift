import SwiftUI

/// 기록 탭 루트 — 집계 대시보드 + 전체 목록. 목록·상세는 Task 5에서 이관된다(스펙 §5).
/// 넷이 한 스크롤에 들어가고 고정 헤더는 없다(스펙 §6.1).
struct HistoryPage: View {
    @State private var viewModel: HistoryPageViewModel
    private let isActive: Bool

    init(repository: RunRecordRepositoryProtocol, isActive: Bool) {
        _viewModel = State(initialValue: HistoryPageViewModel(repository: repository))
        self.isActive = isActive
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HistoryDashboard(viewModel: viewModel)
                        .listRowInsets(
                            EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                // Task 5에서 기록 목록 섹션이 여기 들어온다.
                if viewModel.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "아직 기록이 없어요",
                            systemImage: "figure.run",
                            description: Text("러닝을 마치면 기록이 자동으로 저장돼요")
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("기록")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: isActive) {
                guard isActive else { return }
                await viewModel.load()
            }
        }
    }
}
