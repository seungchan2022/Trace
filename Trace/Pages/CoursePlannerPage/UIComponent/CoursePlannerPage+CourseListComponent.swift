import SwiftUI

extension CoursePlannerPage {
    var courseListSheet: some View {
        NavigationStack {
            Group {
                if viewModel.savedCourses.isEmpty {
                    ContentUnavailableView(
                        "저장된 코스가 없습니다",
                        systemImage: "map",
                        description: Text("코스를 만들고 저장 버튼을 눌러보세요")
                    )
                } else {
                    savedCourseList
                }
            }
            .navigationTitle("저장된 코스")
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
                .accessibilityIdentifier("coursePlanner.savedCourse.\(course.name)")
            }
            .onDelete { indexSet in
                // 즉시 삭제하지 않고 확인 알럿을 띄운다 (스펙 §3)
                guard let first = indexSet.first else { return }
                viewModel.requestDelete(viewModel.savedCourses[first])
            }
        }
        .alert(
            "코스를 삭제할까요?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteCourse != nil },
                // 의도된 no-op: 삭제/취소 버튼 탭 모두에서 SwiftUI가 이 setter를 먼저 호출하므로,
                // 여기서 상태를 지우면 confirmPendingDelete()의 Task가 읽기 전에 값이 사라지는
                // 경쟁 상태가 재발한다. 상태 정리는 버튼 액션(confirmPendingDelete/cancelPendingDelete)에서만.
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.body.weight(.semibold))
                Text(course.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.2f km", course.distanceMeters / 1000))
                .font(.callout.monospacedDigit())
        }
        .contentShape(Rectangle())
    }
}
