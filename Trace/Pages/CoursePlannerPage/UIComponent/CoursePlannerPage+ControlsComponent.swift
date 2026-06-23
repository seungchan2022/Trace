import SwiftUI

extension CoursePlannerPage {
    var controls: some View {
        HStack(spacing: 12) {
            Button(viewModel.isDrawingMode ? "그리기 종료" : "그리기") {
                viewModel.toggleDrawingMode()
            }
            .accessibilityIdentifier("coursePlanner.drawToggle")

            Button("되돌리기") { Task { await viewModel.undoLastStroke() } }
                .disabled(viewModel.drawnStrokes.isEmpty)
                .accessibilityIdentifier("coursePlanner.undo")

            Button("초기화") { viewModel.clear() }
                .disabled(
                    viewModel.startCoordinate == nil
                    && viewModel.drawnStrokes.isEmpty
                )
                .accessibilityIdentifier("coursePlanner.clear")
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
}
