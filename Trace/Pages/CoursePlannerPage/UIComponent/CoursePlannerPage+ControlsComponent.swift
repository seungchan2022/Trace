import SwiftUI

extension CoursePlannerPage {
    var controls: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleDrawingMode()
            } label: {
                Label(
                    viewModel.isDrawingMode ? "경로 찍기" : "그리기",
                    systemImage: viewModel.isDrawingMode ? "mappin.and.ellipse" : "pencil.tip"
                )
            }
            .accessibilityIdentifier("coursePlanner.drawToggle")

            if viewModel.isDrawingMode {
                Button("되돌리기") { Task { await viewModel.undoLastStroke() } }
                    .disabled(viewModel.drawnStrokes.isEmpty)
                    .accessibilityIdentifier("coursePlanner.undo")
            }

            Button("초기화") { viewModel.clear() }
                .disabled(viewModel.course == nil && viewModel.startCoordinate == nil)
                .accessibilityIdentifier("coursePlanner.clear")
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .frame(maxWidth: .infinity)
        .background(viewModel.isDrawingMode ? Color.orange.opacity(0.15) : Color.clear)
    }
}
