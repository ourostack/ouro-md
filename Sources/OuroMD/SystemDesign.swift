import AppKit
import SwiftUI

/// On macOS 26+, system glass covers a real editor backdrop with a native obscured viewport inset; earlier systems retain their material.
enum SystemDesign {
    static var usesGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

/// Covers real scrolling content without reflecting its top edge; foreground chrome stays system-owned.
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
    private var fullscreenObservers: [NSObjectProtocol] = []
    private var fullscreenBackdrop: NSView?
    private var fullscreenActive = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeFullscreenBackdrop()
        fullscreenObservers.forEach(NotificationCenter.default.removeObserver)
        fullscreenObservers.removeAll()
        fullscreenActive = false
        guard let window else { return }
        fullscreenObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                if let window {
                    self?.fullscreenActive = true
                    self?.installFullscreenBackdrop(for: window)
                }
            }
        })
        fullscreenObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fullscreenActive = false
                self?.removeFullscreenBackdrop()
            }
        })
        fullscreenObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: nil, queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                if self?.fullscreenActive == true, let window {
                    self?.installFullscreenBackdrop(for: window)
                }
            }
        })
        fullscreenObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fullscreenActive = false
                self?.removeFullscreenBackdrop()
            }
        })
        if window.styleMask.contains(.fullScreen) {
            fullscreenActive = true
            installFullscreenBackdrop(for: window)
        }
    }

    private func installFullscreenBackdrop(for document: NSWindow) {
        guard let anchor = document.toolbar?.items.compactMap(\.view).first,
              let toolbarWindow = anchor.window, toolbarWindow !== document,
              let toolbarContent = toolbarWindow.contentView else {
            removeFullscreenBackdrop()
            return
        }
        var foreground = anchor
        while foreground.bounds.width < toolbarContent.bounds.width - 1,
              let parent = foreground.superview {
            foreground = parent
        }
        guard let host = foreground.superview,
              foreground.bounds.width >= toolbarContent.bounds.width - 1,
              host.bounds.height > 0,
              host.bounds.height <= toolbarContent.bounds.height + 1 else {
            removeFullscreenBackdrop()
            return
        }
        if fullscreenBackdrop?.superview === host { return }
        removeFullscreenBackdrop()
        let panel = FullscreenHeaderBackdropView(frame: host.bounds)
        host.addSubview(panel, positioned: .below, relativeTo: foreground)
        fullscreenBackdrop = panel
    }

    private func removeFullscreenBackdrop() {
        fullscreenBackdrop?.removeFromSuperview()
        fullscreenBackdrop = nil
    }

    deinit {
        fullscreenObservers.forEach(NotificationCenter.default.removeObserver)
        fullscreenBackdrop?.removeFromSuperview()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// AppKit moves native toolbar controls to a separate fullscreen window. A
/// within-window glass panel there has no document to sample. Native
/// behind-window material supplies that backdrop, below the unchanged controls.
@available(macOS 26, *)
private final class FullscreenHeaderBackdropView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("OuroMDFullscreenHeaderBackdrop")
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
        let material = NSVisualEffectView(frame: bounds)
        material.material = .titlebar
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        material.autoresizingMask = [.width, .height]
        addSubview(material)
        let glass = NSGlassEffectView(frame: bounds)
        glass.style = .regular
        glass.cornerRadius = 0
        glass.contentView = NSView()
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
    }

    required init?(coder: NSCoder) { nil }
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
