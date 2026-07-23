import SwiftUI

/// 기록 탭 루트 — 집계 대시보드 + 전체 목록.
/// 넷이 한 스크롤에 들어가고 고정 헤더는 없다(스펙 §6.1).
/// 상세는 push. 기간 세그먼트는 집계 숫자만 바꾸고 목록은 항상 전체다(스펙 §6).
struct HistoryPage: View {
    @State private var viewModel: HistoryPageViewModel
    private let isActive: Bool

    init(history: RunHistoryViewModel, isActive: Bool) {
        _viewModel = State(initialValue: HistoryPageViewModel(history: history))
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
                } else {
                    Section {
                        ForEach(viewModel.summaries) { summary in
                            NavigationLink(value: summary) {
                                HistoryRecordRow(summary: summary)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                        .onDelete { indexSet in
                            guard let first = indexSet.first else { return }
                            viewModel.history.requestDelete(viewModel.summaries[first])
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("기록")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SavedRunSummary.self) { summary in
                HistoryRecordDetailView(summary: summary, viewModel: viewModel.history)
            }
            .task(id: isActive) { await viewModel.loadWhenActivated(isActive) }
            .alert(
                "기록을 삭제할까요?",
                isPresented: Binding(
                    get: { viewModel.history.pendingDelete != nil },
                    set: { _ in }
                )
            ) {
                Button("삭제", role: .destructive) { Task { await viewModel.history.confirmPendingDelete() } }
                Button("취소", role: .cancel) { viewModel.history.cancelPendingDelete() }
            } message: {
                Text("삭제한 기록은 되돌릴 수 없습니다")
            }
            .alert("삭제하지 못했어요", isPresented: Bindable(viewModel.history).showsDeleteFailure) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("잠시 후 다시 시도해 주세요")
            }
        }
    }
}
