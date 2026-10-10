import SwiftUI

extension View {
    func appGlassCard(cornerRadius: CGFloat = 12) -> some View {
        background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    func appGlassChrome(cornerRadius: CGFloat = 8) -> some View {
        background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    func appGlassButton(prominent: Bool = false) -> some View {
        buttonStyle(AppGlassButtonStyle(prominent: prominent))
    }
}

private struct AppGlassButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(prominent ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.16), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
