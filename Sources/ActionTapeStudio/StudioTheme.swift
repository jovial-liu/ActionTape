import SwiftUI

enum StudioTheme {
    static let accent = Color(red: 1.0, green: 0.31, blue: 0.20)
    static let warm = Color(red: 1.0, green: 0.64, blue: 0.16)
    static let violet = Color(red: 0.48, green: 0.37, blue: 1.0)
    static let success = Color(red: 0.20, green: 0.72, blue: 0.50)
    static let warning = Color(red: 0.96, green: 0.62, blue: 0.18)
    static let failure = Color(red: 0.92, green: 0.25, blue: 0.30)

    static let accentGradient = LinearGradient(
        colors: [accent, warm],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func tapePanel() -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
    }
}
