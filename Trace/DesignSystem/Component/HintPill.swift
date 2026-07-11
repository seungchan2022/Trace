import SwiftUI

struct HintPill: View {
    static let autoDismissDelay: TimeInterval = 2.6

    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(DesignToken.Typography.chip)
            .foregroundStyle(isError ? .white : DesignToken.Color.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                if isError {
                    Capsule().fill(DesignToken.Color.danger)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
    }
}
