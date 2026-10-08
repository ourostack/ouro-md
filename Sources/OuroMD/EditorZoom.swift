import WebKit

/// Applies the app's text size to an editor web view.
///
/// Uses `pageZoom` (CSS zoom with reflow, like Safari's Zoom In) rather than
/// `magnification` (a pinch-style scale of the already laid-out page). With
/// `magnification`, a text size above 100% scaled a page laid out for the full
/// window, so the window showed only its top-left corner: the column sat off
/// center and the side padding never adapted to the window width.
enum EditorZoom {
    static func apply(_ factor: Double, to webView: WKWebView) {
        webView.magnification = 1
        webView.pageZoom = CGFloat(factor)
    }
}
