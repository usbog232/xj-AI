import SwiftUI

enum AppTheme {
    static let root = Color(red: 0.067, green: 0.082, blue: 0.098)
    static let canvas = Color(red: 0.082, green: 0.102, blue: 0.122)
    static let control = Color.white.opacity(0.055)
    static let controlHover = Color.white.opacity(0.09)
    static let hairline = Color.white.opacity(0.09)
    static let muted = Color(red: 0.60, green: 0.65, blue: 0.70)
    static let recording = Color(red: 1.0, green: 0.35, blue: 0.31)
    static let live = Color(red: 0.34, green: 0.85, blue: 0.96)
    static let success = Color(red: 0.27, green: 0.79, blue: 0.42)
    static let warning = Color(red: 0.98, green: 0.70, blue: 0.28)
}

extension View {
    func xjControlSurface() -> some View {
        self
            .background(AppTheme.control)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            }
    }
}
