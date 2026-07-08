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

            Button("되돌리기") { Task { await viewModel.undo() } }
                .disabled(!viewModel.canUndo)
                .accessibilityIdentifier("coursePlanner.undo")

            Button("앞으로") { viewModel.redo() }
                .disabled(!viewModel.canRedo)
                .accessibilityIdentifier("coursePlanner.redo")

            Button("초기화") { viewModel.clear() }
                .disabled(viewModel.course == nil && viewModel.pendingTapStart == nil)
                .accessibilityIdentifier("coursePlanner.clear")

            Button {
                viewModel.isSavePromptPresented = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .disabled(!viewModel.canSaveCourse)
            .accessibilityIdentifier("coursePlanner.saveCourse")

            Button {
                Task { await viewModel.presentCourseList() }
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityIdentifier("coursePlanner.courseList")

            Button {
                viewModel.insertWholeCourseRoundTrip()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .disabled(!viewModel.canInsertWholeCourseRoundTrip)
            .accessibilityIdentifier("coursePlanner.wholeCourseRoundTrip")
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .frame(maxWidth: .infinity)
        .background(viewModel.isDrawingMode ? Color.orange.opacity(0.15) : Color.clear)
    }
}
