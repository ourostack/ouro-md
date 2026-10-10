import AppKit
import SwiftUI

/// The system design (Liquid Glass) seams, in one place. On macOS 26 and later,
/// with Ouro MD linked against the current SDK, floating controls use system
/// glass while a native background extension carries moving document imagery
/// beneath the native toolbar. Its header panel is glass, not a custom fade;
/// earlier systems keep the material look they had.
enum SystemDesign {
    static var usesGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

@available(macOS 26, *)
final class DocumentBackgroundExtensionView: NSBackgroundExtensionView {
    var headerInset: CGFloat = 0

    override func layout() {
        super.layout()
        contentView?.frame = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                                    height: max(0, bounds.height - headerInset))
    }
}

/// Covers the background extension's header band without changing document
/// layout. Keep the native window's foreground chrome system-owned.
struct DocumentHeaderBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view: NSView
        if #available(macOS 26, *) {
            let glass = DocumentHeaderGlassView()
            glass.style = .regular
            glass.cornerRadius = 0
            glass.contentView = NSView()
            view = glass
        } else {
            let material = DocumentHeaderMaterialView()
            material.material = .titlebar
            material.blendingMode = .withinWindow
            material.state = .followsWindowActiveState
            view = material
        }
        view.identifier = NSUserInterfaceItemIdentifier("OuroMDDocumentHeaderBackdrop")
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@available(macOS 26, *)
private final class DocumentHeaderGlassView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class DocumentHeaderMaterialView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
