import SwiftUI

struct GlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = DesignToken.Size.topBarButton
    var isProminent = false
    var isDisabled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background {
                if isProminent {
                    Circle().fill(DesignToken.Color.accent)
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().strokeBorder(DesignToken.Color.glassBorder, lineWidth: 1))
                }
            }
            .foregroundStyle(isProminent ? DesignToken.Color.accentInk : DesignToken.Color.ink)
            .opacity(isDisabled ? 0.4 : (configuration.isPressed ? 0.7 : 1))
    }
}

extension ButtonStyle where Self == GlassIconButtonStyle {
    static var glassIcon: GlassIconButtonStyle { GlassIconButtonStyle() }

    static func glassIcon(prominent: Bool = false, disabled: Bool = false) -> GlassIconButtonStyle {
        GlassIconButtonStyle(isProminent: prominent, isDisabled: disabled)
    }
}
