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

enum AppGlassButtonLook {
    static func opacity(isEnabled: Bool, isPressed: Bool) -> Double {
        if !isEnabled { return 0.4 }
        if isPressed { return 0.72 }
        return 1
    }

    static func strokeIsAccent(isEnabled: Bool, prominent: Bool) -> Bool {
        isEnabled && prominent
    }
}

private struct AppGlassButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let accent = AppGlassButtonLook.strokeIsAccent(isEnabled: isEnabled, prominent: prominent)
        let stroke = accent ? Color.accentColor.opacity(0.95) : Color.secondary.opacity(isEnabled ? 0.55 : 0.28)
        configuration.label
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(stroke, lineWidth: accent ? 1.5 : 1)
            )
            .opacity(AppGlassButtonLook.opacity(isEnabled: isEnabled, isPressed: configuration.isPressed))
    }
}
