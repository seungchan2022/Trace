import SwiftUI

extension CoursePlannerPage {
    var topBar: some View {
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

            Spacer()

            Button {
                Task { await viewModel.presentCourseList() }
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityIdentifier("coursePlanner.courseList")
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .frame(maxWidth: .infinity)
        .background(viewModel.isDrawingMode ? Color.orange.opacity(0.15) : Color.clear)
    }
}
