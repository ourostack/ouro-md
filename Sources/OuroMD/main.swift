import Foundation
import AppKit

// Entry point. Command-line flags are handled first and exit before any window
// is created; otherwise the GUI editor launches.

let rawArgs = Array(CommandLine.arguments.dropFirst())

func argValue(_ flag: String) -> String? {
    if let i = rawArgs.firstIndex(of: flag), i + 1 < rawArgs.count {
        return rawArgs[i + 1]
    }
    return nil
}

func hasFlag(_ flag: String) -> Bool { rawArgs.contains(flag) }

if hasFlag("--help") || hasFlag("-h") {
    print(OuroCLI.helpText)
    exit(0)
}
if hasFlag("--version") {
    print("ouro-md \(OuroCLI.version)")
    exit(0)
}
if hasFlag("--list-themes") {
    for theme in ThemeStore.shared.themes {
        print("\(theme.id)\t\(theme.displayName)")
    }
    exit(0)
}
if hasFlag("--render") {
    guard let path = argValue("--render") else {
        FileHandle.standardError.write(Data("ouro-md: --render requires a FILE path\n".utf8))
        exit(2)
    }
    OuroCLI.render(path: path, themeId: argValue("--theme") ?? ThemeStore.shared.defaultTheme.id)
}

if hasFlag("--roundtrip") {
    guard let path = argValue("--roundtrip") else {
        FileHandle.standardError.write(Data("ouro-md: --roundtrip requires a FILE path\n".utf8))
        exit(2)
    }
    let out = argValue("--out").map { URL(fileURLWithPath: $0) }
    RoundTripper(fileURL: URL(fileURLWithPath: path), outURL: out).run()
}

if hasFlag("--shoot") {
    guard let path = argValue("--shoot") else {
        FileHandle.standardError.write(Data("ouro-md: --shoot requires a FILE path\n".utf8))
        exit(2)
    }
    let out = argValue("--out") ?? "/tmp/ouro-shot.png"
    let themeID = argValue("--theme") ?? ThemeStore.shared.defaultTheme.id
    let width = Double(argValue("--width") ?? "") ?? 1000
    let height = Double(argValue("--height") ?? "") ?? 1300
    Snapshotter(fileURL: URL(fileURLWithPath: path),
                outURL: URL(fileURLWithPath: out),
                themeID: themeID,
                size: NSSize(width: width, height: height)).run()
}

// GUI launch.
let appDelegate = AppDelegate()
if let firstFile = rawArgs.first(where: { !$0.hasPrefix("-") }) {
    appDelegate.initialFilePath = firstFile
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
application.delegate = appDelegate
MenuBuilder.install(into: application, target: appDelegate)
application.run()
