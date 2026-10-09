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

/// The soft scroll edge under the toolbar. WebKit keeps the page clear of the
/// toolbar through obscured content insets but leaves covering that area to
/// the app ("should be covered by UI elements managed by the client", in
/// WKWebView.h), and AppKit's automatic scroll edge effect only covers
/// NSScrollView. Without it, text scrolled under the toolbar sits right behind
/// the traffic lights, sidebar button and title. This blurs it with the bar
/// material and fades into the page, like the system's soft edge.
struct ScrollEdgeCover: View {
    let height: CGFloat
    /// How far below the toolbar the fade reaches.
    static let fade: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.bar)
                .frame(height: height + Self.fade)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: height / (height + Self.fade)),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Spacer(minLength: 0)
        }
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
