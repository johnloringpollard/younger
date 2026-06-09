import SwiftUI

enum YoungerTheme {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.075)
    static let surface = Color(red: 0.075, green: 0.10, blue: 0.12)
    static let raised = Color(red: 0.105, green: 0.135, blue: 0.155)
    static let mint = Color(red: 0.33, green: 0.93, blue: 0.67)
    static let coral = Color(red: 1.0, green: 0.38, blue: 0.36)
    static let gold = Color(red: 1.0, green: 0.73, blue: 0.30)
    static let sky = Color(red: 0.37, green: 0.72, blue: 1.0)
    static let secondaryText = Color.white.opacity(0.62)
    static let divider = Color.white.opacity(0.08)
}

struct YoungerBackground: View {
    var body: some View {
        ZStack {
            YoungerTheme.background
            RadialGradient(
                colors: [YoungerTheme.mint.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(YoungerTheme.surface.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func youngerCard() -> some View {
        modifier(GlassCardModifier())
    }
}
