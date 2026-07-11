import SwiftUI

extension CoursePlannerPage {
    var courseListSheet: some View {
        NavigationStack {
            Group {
                if viewModel.savedCourses.isEmpty {
                    ContentUnavailableView(
                        "저장한 코스가 없어요",
                        systemImage: "map",
                        description: Text("코스를 만들고 저장 버튼을 눌러보세요")
                    )
                } else {
                    savedCourseList
                }
            }
            .navigationTitle("저장한 코스")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var savedCourseList: some View {
        List {
            ForEach(viewModel.savedCourses) { course in
                Button {
                    Task { await viewModel.requestLoad(course) }
                } label: {
                    savedCourseRow(course)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .accessibilityIdentifier("coursePlanner.savedCourse.\(course.name)")
            }
            .onDelete { indexSet in
                guard let first = indexSet.first else { return }
                viewModel.requestDelete(viewModel.savedCourses[first])
            }
        }
        .listStyle(.plain)
        .alert(
            "코스를 삭제할까요?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteCourse != nil },
                set: { _ in }
            )
        ) {
            Button("삭제", role: .destructive) { Task { await viewModel.confirmPendingDelete() } }
            Button("취소", role: .cancel) { viewModel.cancelPendingDelete() }
        } message: {
            Text(viewModel.pendingDeleteCourse.map { "'\($0.name)'은(는) 되돌릴 수 없습니다" } ?? "")
        }
    }

    private func savedCourseRow(_ course: SavedCourse) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(uiColor: SegmentPalette.color(at: 0)))
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(DesignToken.Typography.segmentRowTitle)
                    .foregroundStyle(DesignToken.Color.ink)
                Text(
                    "\(String(format: "%.2f", course.distanceMeters / 1000))km · "
                    + "\(course.createdAt.formatted(date: .abbreviated, time: .omitted))"
                )
                    .font(DesignToken.Typography.segmentRowSubtitle)
                    .foregroundStyle(DesignToken.Color.ink2)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: DesignToken.Corner.row).fill(Color.clear))
        .contentShape(Rectangle())
    }
}
