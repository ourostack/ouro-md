import AppKit

/// An off-screen host window for the headless CLI harnesses. Borderless (so macOS
/// won't constrain it back on-screen the way it does titled windows), able to
/// become key/main (so first-responder and synthesized key-event routing work),
/// and it refuses the on-screen constraint so it stays parked far off-screen.
final class HeadlessHostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // Keep the harness window wherever we put it (off-screen); don't pull it back
    // onto a visible screen the way the default implementation would.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Shared setup for the headless CLI harnesses (`--tablewraptest`, `--undotest`,
/// `--renderprobe`, …). These drive a real WebKit surface for probing, not to show
/// UI — so they must never grab a Dock icon, pop a window onto the user's screen,
/// or steal keyboard focus from whatever the user is doing.
enum HeadlessHarness {
    /// No Dock icon, no forced activation. Call once at the top of `run()`.
    static func configure() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    /// Hosts `view` in an off-screen window so WebKit composites and renders it
    /// (and key-event / first-responder routing works) without the window ever
    /// appearing on screen or stealing focus. We never call
    /// `NSApp.activate(ignoringOtherApps:)`, so the user keeps their focus. Returns
    /// the window — retain it for the lifetime of the harness.
    @discardableResult
    static func offscreenHost(_ view: NSView, size: NSSize) -> NSWindow {
        let window = HeadlessHostWindow(contentRect: NSRect(origin: .zero, size: size),
                                        styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        return window
    }

    /// Like `offscreenHost`, but also activates the app. Harnesses that drive real
    /// key events or test focused-editable / window-active behavior (undo via
    /// cmd-z, paste, selection focus, …) need WebKit to grant the editable DOM
    /// focus, which only happens when the app is active. The host window is still
    /// off-screen so nothing visible appears — the app just briefly takes keyboard
    /// focus. Use ONLY for harnesses that genuinely need an active, focused editor.
    @discardableResult
    static func offscreenHostActive(_ view: NSView, size: NSSize) -> NSWindow {
        // WebKit only grants an editable DOM focus when its window is on a real
        // screen and the app is active, so this one can't be parked off-screen.
        // Instead it sits on-screen but fully transparent and click-through, so the
        // user never sees it and can't interact with it; only the app activation
        // (a brief keyboard-focus blip) is observable.
        let window = HeadlessHostWindow(contentRect: NSRect(origin: .zero, size: size),
                                        styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}
