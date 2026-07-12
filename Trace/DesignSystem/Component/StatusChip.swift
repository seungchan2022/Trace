import SwiftUI

enum StatusChipKind: Equatable {
    case calculating
    case error(String)
    case route(segmentLabel: String)
}

struct StatusChip: View {
    let kind: StatusChipKind

    var body: some View {
        HStack(spacing: 6) {
            switch kind {
            case .calculating:
                // 기본 크기의 ProgressView는 13pt 텍스트 한 줄보다 살짝 커서, 이 칩만 다른
                // variant보다 캡슐이 미세하게 높아진다 — 헤더가 이 칩을 포함하는 순간(계산 시작)
                // 시트 전체 높이가 같이 늘어나 FAB(뒤로가기 등)를 살짝 가리는 원인이었다(2026-07-12,
                // 사용자 실기기 스크린샷). 텍스트 줄 높이 안에 들어가도록 명시적으로 눌러준다.
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
                Text("계산 중")
            case .error(let message):
                Text(message)
            case .route(let segmentLabel):
                Text(segmentLabel)
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .font(isError ? DesignToken.Typography.chipError : DesignToken.Typography.chip)
        .foregroundStyle(isError ? .white : DesignToken.Color.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(isError ? DesignToken.Color.danger : DesignToken.Color.surface2))
    }

    private var isError: Bool {
        if case .error = kind { return true }
        return false
    }
}
