import AppKit
import SwiftUI

/// The system design (Liquid Glass) seams, in one place. On macOS 26 and later,
/// with Ouro MD linked against the current SDK, floating controls use system
/// glass and the editor runs edge to edge under the toolbar; earlier systems
/// keep the material look they had.
enum SystemDesign {
    static var usesGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

private struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.quaternary, lineWidth: 1))
                .shadow(radius: elevated ? 10 : 0)
        }
    }
}

extension View {
    /// A floating control surface: system glass on macOS 26+, material before.
    func glassSurface(cornerRadius: CGFloat, elevated: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, elevated: elevated))
    }
}
