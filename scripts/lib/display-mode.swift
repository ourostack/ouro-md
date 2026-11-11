// Prints the main display's modes and, with --best W H, switches this session to the sharpest mode whose size in
// points is at least W x H: a 2x (HiDPI) mode if the display offers one, otherwise the largest. Store scenes run it
// on a disposable hosted Mac before photographing, so a Retina mode gives 2880x1800 scenes. It never runs on an
// operator's Mac: the caller checks GITHUB_ACTIONS.
import CoreGraphics
import Foundation

let display = CGMainDisplayID()
let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []).filter { $0.isUsableForDesktopGUI() }
func describe(_ mode: CGDisplayMode) -> String {
    "\(mode.width)x\(mode.height) pt, \(mode.pixelWidth)x\(mode.pixelHeight) px, \(mode.pixelWidth / max(mode.width, 1))x"
}
if let current = CGDisplayCopyDisplayMode(display) { print("current: \(describe(current))") }
for mode in modes { print("mode: \(describe(mode))") }

let args = CommandLine.arguments
if let index = args.firstIndex(of: "--best"), args.count > index + 2, let w = Int(args[index + 1]), let h = Int(args[index + 2]) {
    let big = modes.filter { $0.width >= w && $0.height >= h }
    let pick = big.filter { $0.pixelWidth >= 2 * $0.width }.min { $0.width < $1.width }
        ?? big.min { $0.width < $1.width }
        ?? modes.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
    guard let pick else { print("no usable mode"); exit(0) }
    var config: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&config)
    CGConfigureDisplayWithDisplayMode(config, display, pick, nil)
    let status = CGCompleteDisplayConfiguration(config, .forSession)
    print("switch to \(describe(pick)): \(status == .success ? "ok" : "error \(status.rawValue)")")
    Thread.sleep(forTimeInterval: 2)
    if let now = CGDisplayCopyDisplayMode(display) { print("now: \(describe(now))") }
}
