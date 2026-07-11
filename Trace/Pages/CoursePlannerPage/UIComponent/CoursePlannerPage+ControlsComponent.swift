import SwiftUI

extension CoursePlannerPage {
    var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(DesignToken.Color.accentInk)
                .frame(width: DesignToken.Size.topBarButton, height: DesignToken.Size.topBarButton)
                .background(Circle().fill(DesignToken.Color.accent))

            Spacer()

            HStack(spacing: 4) {
                segmentToggleButton(title: "경로 찍기", systemImage: "mappin.and.ellipse", isActive: !viewModel.isDrawingMode)
                segmentToggleButton(title: "그리기", systemImage: "pencil.tip", isActive: viewModel.isDrawingMode)
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(DesignToken.Color.glassBorder, lineWidth: 1))
            )

            Spacer()

            Button {
                Task { await viewModel.presentCourseList() }
            } label: {
                Image(systemName: "folder.fill")
            }
            .buttonStyle(.glassIcon)
            .accessibilityIdentifier("coursePlanner.courseList")
        }
        .padding(.horizontal, DesignToken.Size.screenMargin)
        .padding(.top, 8)
    }

    private func segmentToggleButton(title: String, systemImage: String, isActive: Bool) -> some View {
        Button {
            // toggleDrawingMode()는 상태를 뒤집는 순수 토글이라, 이미 활성인 세그먼트를 다시
            // 탭하면 반대 모드로 넘어가 버린다 — 세그먼트 컨트롤은 활성 항목 재탭이 no-op이어야 한다.
            guard !isActive else { return }
            Task { await viewModel.toggleDrawingMode() }
        } label: {
            Label(title, systemImage: systemImage)
                .font(DesignToken.Typography.chip)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isActive ? AnyShapeStyle(DesignToken.Color.accent) : AnyShapeStyle(.clear), in: Capsule())
                .foregroundStyle(isActive ? DesignToken.Color.accentInk : DesignToken.Color.ink)
        }
        .accessibilityIdentifier("coursePlanner.drawToggle")
    }
}
