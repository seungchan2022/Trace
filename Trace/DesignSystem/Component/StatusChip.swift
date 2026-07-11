import SwiftUI

enum StatusChipKind: Equatable {
    case calculating
    case error(String)
    case startSet
    case route(segmentLabel: String)
}

struct StatusChip: View {
    let kind: StatusChipKind

    var body: some View {
        HStack(spacing: 6) {
            switch kind {
            case .calculating:
                ProgressView().controlSize(.small)
                Text("계산 중")
            case .error(let message):
                Text(message)
            case .startSet:
                Circle().fill(DesignToken.Color.accent).frame(width: 6, height: 6)
                Text("출발 지정됨")
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
