// Prints the CGWindowID of the largest on-screen window owned by the process
// named in argv[1], or exits 1 when there is none.
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "ouro-md"
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
let candidates = windows.compactMap { info -> (Int, Double)? in
    guard (info[kCGWindowOwnerName as String] as? String) == owner,
          (info[kCGWindowLayer as String] as? Int) == 0,
          let id = info[kCGWindowNumber as String] as? Int,
          let bounds = info[kCGWindowBounds as String] as? [String: Double] else { return nil }
    return (id, (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0))
}
guard let best = candidates.max(by: { $0.1 < $1.1 }) else { exit(1) }
print(best.0)
