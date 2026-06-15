import Foundation

/// Locates the bundled `web/` resources (Vditor, index.html, bridge.js) robustly
/// across every way Ouro MD runs.
///
/// Why this exists: SwiftPM's generated `Bundle.module` accessor resolves the
/// resource bundle relative to `Bundle.main.bundleURL`. For a packaged `.app`
/// that's the **app root** (`Ouro MD.app/`), but the bundle actually ships in
/// `Contents/Resources/` — so the accessor never finds it there and falls back to
/// a path hardcoded at build time (`/Users/<builder>/.../.build/...`). That path
/// only exists on the machine that built the release, so every *other* machine
/// crashed at launch with a `Bundle.module` fatalError. This resolver checks the
/// locations where the bundle actually lives, in order, and only uses
/// `Bundle.module` as a last-resort dev fallback (where it works).
enum OuroResources {
    static let bundle: Bundle = {
        let name = "ouro-md_OuroMD.bundle"
        var candidates: [URL] = []
        // Packaged .app: Contents/Resources/ouro-md_OuroMD.bundle
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent(name))
        }
        // Bare SwiftPM executable: the bundle sits next to the binary.
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(exeDir.appendingPathComponent(name))
        }
        // App root (matches SwiftPM's own accessor expectation, just in case).
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(name))

        for url in candidates {
            if let bundle = Bundle(url: url) { return bundle }
        }
        // Dev fallback (`swift run`, `swift test`): the generated accessor works
        // here because the build path is the current machine's.
        return Bundle.module
    }()

    /// URL of a resource inside the bundled `web/` directory.
    static func web(_ resource: String, _ ext: String) -> URL? {
        bundle.url(forResource: resource, withExtension: ext, subdirectory: "web")
    }
}
