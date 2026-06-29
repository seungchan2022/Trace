import SwiftUI

extension CoursePlannerPage {
    var controls: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.toggleDrawingMode() }
            } label: {
                Label(
                    viewModel.isDrawingMode ? "그리기" : "경로 찍기",
                    systemImage: viewModel.isDrawingMode ? "pencil.tip" : "mappin.and.ellipse"
                )
            }
            .accessibilityIdentifier("coursePlanner.drawToggle")

            if viewModel.isDrawingMode {
                Button("되돌리기") { Task { await viewModel.undoLastStroke() } }
                    .disabled(!viewModel.canUndo)
                    .accessibilityIdentifier("coursePlanner.undo")
            }

            Button("초기화") { viewModel.clear() }
                .disabled(viewModel.course == nil && viewModel.pendingTapStart == nil)
                .accessibilityIdentifier("coursePlanner.clear")
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .frame(maxWidth: .infinity)
        .background(viewModel.isDrawingMode ? Color.orange.opacity(0.15) : Color.clear)
    }
}
