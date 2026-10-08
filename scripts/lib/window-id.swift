// Prints the CGWindowID of the largest normal-layer window owned by process
// ID argv[1], or lists every window to stderr and exits 1 when there is none.
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments.dropFirst().first ?? "") ?? -1
let windows = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
let candidates = windows.compactMap { info -> (Int, Double)? in
    guard (info[kCGWindowOwnerPID as String] as? Int) == pid,
          (info[kCGWindowLayer as String] as? Int) == 0,
          let id = info[kCGWindowNumber as String] as? Int,
          let bounds = info[kCGWindowBounds as String] as? [String: Double] else { return nil }
    let area = (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
    return area > 10_000 ? (id, area) : nil
}
guard let best = candidates.max(by: { $0.1 < $1.1 }) else {
    for info in windows where (info[kCGWindowOwnerPID as String] as? Int) == pid {
        FileHandle.standardError.write(Data("window \(info)\n".utf8))
    }
    exit(1)
}
print(best.0)
