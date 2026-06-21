import AppKit
import WebKit

/// Headless `--tablewraptest`: loads the live editor in a deliberately narrow
/// window, applies the real theme, renders dogfood-shaped tables, and fails if
/// tables drag the whole document horizontally or collapse long/code cells into
/// unreadable slivers. Truly wide tables should scroll inside their own table
/// box. The theme stylesheet is applied the same way the app does — via
/// `window.ouro.setTheme` — so this exercises the shipped CSS, not Vditor's
/// defaults.
final class TableWrapTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let markdownPath: String?
    private let viewportWidth: CGFloat
    private let viewportHeight: CGFloat
    // Narrow on purpose: wide tables cannot fit here unless their own scroll
    // container absorbs the overflow.
    private let theme = ThemeStore.shared.defaultTheme

    init(markdownPath: String? = nil, viewportWidth: CGFloat = 480, viewportHeight: CGFloat = 640) {
        self.markdownPath = markdownPath
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
    }

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let frame = NSRect(x: 0, y: 0, width: viewportWidth, height: viewportHeight)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("tablewraptest: index.html not found\n".utf8)); exit(1)
        }
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 22) {
            FileHandle.standardError.write(Data("tablewraptest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
            webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)))", completionHandler: nil)
            webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(markdown)))", completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.webView.evaluateJavaScript(Self.measureScript, completionHandler: nil)
            }
        } else if type == "tablewrap" {
            let tableCount = (body["tableCount"] as? Int) ?? 0
            let pageOverflow = (body["pageOverflow"] as? Double) ?? .infinity
            let clippedCount = (body["clippedCount"] as? Int) ?? .max
            let collapsedLongCellCount = (body["collapsedLongCellCount"] as? Int) ?? .max
            let collapsedCodeCellCount = (body["collapsedCodeCellCount"] as? Int) ?? .max
            let imbalancedTableCount = (body["imbalancedTableCount"] as? Int) ?? .max
            let overlappingCodeCount = (body["overlappingCodeCount"] as? Int) ?? .max
            let initialScrolledCount = (body["initialScrolledCount"] as? Int) ?? .max
            let scrollableCount = (body["scrollableCount"] as? Int) ?? 0
            let tableDetails = (body["tableDetails"] as? [[String: Any]]) ?? []
            // Allow a couple of px for sub-pixel rounding.
            let tolerance = 2.0
            let pageOK = pageOverflow <= tolerance
            let tableCountOK = tableCount >= 8
            let clippedOK = clippedCount == 0
            let longCellsOK = collapsedLongCellCount == 0
            let codeCellsOK = collapsedCodeCellCount == 0
            let balanceOK = imbalancedTableCount == 0
            let overlapOK = overlappingCodeCount == 0
            let initialScrollOK = initialScrolledCount == 0
            let scrollRequired = viewportWidth <= 800
            let scrollOK = !scrollRequired || scrollableCount > 0
            print("tables present: \(tableCount) \(tableCountOK ? "✓" : "✗ (expected at least 8)")")
            print(String(format: "page horizontal overflow: %.1fpx %@", pageOverflow, pageOK ? "✓" : "✗ (table escaped its own scroll)"))
            print("tables clipped by viewport: \(clippedCount) \(clippedOK ? "✓" : "✗")")
            let scrollFailure = scrollRequired ? "✗ (wide tables were squeezed instead)" : "✗"
            print("tables with own horizontal scroll: \(scrollableCount) \(scrollOK ? "✓" : scrollFailure)")
            print("tables initially scrolled sideways: \(initialScrolledCount) \(initialScrollOK ? "✓" : "✗")")
            print("collapsed long cells: \(collapsedLongCellCount) \(longCellsOK ? "✓" : "✗")")
            print("collapsed code cells: \(collapsedCodeCellCount) \(codeCellsOK ? "✓" : "✗")")
            print("imbalanced sparse tables: \(imbalancedTableCount) \(balanceOK ? "✓" : "✗")")
            print("code spilling across cells: \(overlappingCodeCount) \(overlapOK ? "✓" : "✗")")
            for detail in tableDetails {
                let index = (detail["index"] as? Int) ?? -1
                let width = (detail["clientWidth"] as? Double) ?? 0
                let scroll = (detail["scrollOverflow"] as? Double) ?? 0
                let scrollLeft = (detail["scrollLeft"] as? Double) ?? 0
                let minLong = (detail["minLongCellWidth"] as? Double) ?? 0
                let minCode = (detail["minCodeCellWidth"] as? Double) ?? 0
                let columnRatio = (detail["columnRatio"] as? Double) ?? 0
                print(String(format: "table %02d width %.1fpx scroll %.1fpx left %.1fpx min-long %.1fpx min-code %.1fpx column-ratio %.2f",
                             index + 1, width, scroll, scrollLeft, minLong, minCode, columnRatio))
            }
            exit(tableCountOK && pageOK && clippedOK && scrollOK && initialScrollOK && longCellsOK && codeCellsOK && balanceOK && overlapOK ? 0 : 1)
        }
    }

    private var markdown: String {
        if let markdownPath,
           let text = try? String(contentsOf: URL(fileURLWithPath: markdownPath), encoding: .utf8) {
            return text
        }
        return Self.dogfoodShapedMarkdown
    }

    private static let dogfoodShapedMarkdown = """
    # Dogfood Tables

    | Unit | Worker-owned tests/checks | Orchestrator-only integration | Notes |
    | - | - | - | - |
    | 1 | `Tests/SpoonjoyCoreTests/NativeAPIExpansionTests.swift` | Project membership, scenario metadata | Ownership table with medium path cells. |
    | 2 | `Tests/SpoonjoyCoreTests/APITransportTests.swift` | Shared app state wiring | Transport surface. |

    | Endpoint | Contract |
    | - | - |
    | `/api/native/siri/full-access/session/start` | Starts a full-access session and returns enough metadata for native callers. |
    | `/api/native/siri/full-access/session/finish` | Commits queued state, returns conflict markers, and keeps idempotency metadata stable. |

    | Artifact | Repository | Producer | Verification consumer |
    | - | - | - | - |
    | `/Users/example/Projects/spoonjoy-apple/tasks/2026-06-16-1754-planning-siri-full-access-parity/web-product-surface-audit.md` | spoonjoy-apple | Planning pass before doing conversion | Unit 0 baseline must verify the file exists. |

    | Source | Destination | Safety |
    | - | - | - |
    | `Sources/SpoonjoyCore/AppState/NativeLiveStore.swift` | `Sources/SpoonjoyApp/AppShell/SessionCoordinator.swift` | Keep shell coordination thin and prove every store mutation is covered by unit tests. |

    | Case | Native client | Web/product parity | Verification notes |
    | - | - | - | - |
    | Full-access session recovery | The native client should recover from an interrupted session by reading persisted operation metadata and replaying only the safe subset of queued work. | The web workflow already treats committed-but-incomplete state as recoverable and must not generate duplicate side effects. | This row is intentionally prose-heavy so a beautiful table wraps normal language while keeping the table itself wider than the editor column when useful. |
    | Conflict handling | The client must preserve local edits, expose conflict summaries, and avoid deleting user-entered text when the server reports a stale revision. | The current product copy emphasizes explicit conflict handling over silent replacement. | Another long prose cell exercises multi-column wrapping without shrinking each column into a vertical ribbon. |

    | Long code path | Consumer |
    | - | - |
    | `Sources/SpoonjoyCoreTests/NativeFullAccessSessionRecoveryAndConflictProjectionTests.swift` | `scripts/capture-native-screenshot-simulator.sh`, `scripts/smoke-macos.sh`, screenshot blocker/design-review artifact contract |

    | Question | Answer |
    | - | - |
    | Should a gigantic two-column prose table force the entire document sideways? | No. The table should use as much viewport width as it can, then provide its own horizontal scroll while surrounding prose keeps the document stable and readable. This is deliberately long enough to expose table layout policies that look fine for tiny examples but fail under real doing-doc pressure. |

    | Final audit | Evidence |
    | - | - |
    | Read-only dogfood file | The live doing document has eight tables with very different shapes, so this fallback fixture mirrors those shapes when the external dogfood file is unavailable. |
    """

    private static let measureScript = #"""
    (function () {
      var de = document.documentElement;
      var viewportWidth = de.clientWidth;
      var pageOverflow = Math.max(de.scrollWidth, document.body.scrollWidth) - viewportWidth;
      var tables = Array.prototype.slice.call(document.querySelectorAll("#editor table"));
      var collapsedLongCellCount = 0;
      var collapsedCodeCellCount = 0;
      var initialScrolledCount = 0;
      var clippedCount = 0;
      var scrollableCount = 0;
      var imbalancedTableCount = 0;
      var overlappingCodeCount = 0;
      var tableDetails = tables.map(function (table, index) {
        var rect = table.getBoundingClientRect();
        var scrollOverflow = table.scrollWidth - table.clientWidth;
        var scrollLeft = table.scrollLeft || 0;
        var rows = Array.prototype.slice.call(table.querySelectorAll("tr"));
        var columnWidths = [];
        for (var r = 0; r < rows.length; r++) {
          var rowCells = Array.prototype.slice.call(rows[r].children || []);
          if (rowCells.length > columnWidths.length) {
            columnWidths = rowCells.map(function (cell) { return cell.getBoundingClientRect().width; });
          }
        }
        var columnCount = columnWidths.length;
        var minColumnWidth = columnWidths.length ? Math.min.apply(Math, columnWidths) : 0;
        var maxColumnWidth = columnWidths.length ? Math.max.apply(Math, columnWidths) : 0;
        var columnRatio = minColumnWidth > 0 ? maxColumnWidth / minColumnWidth : 0;
        var cells = Array.prototype.slice.call(table.querySelectorAll("th,td"));
        var longWidths = [];
        var codeWidths = [];
        cells.forEach(function (cell) {
          var text = (cell.textContent || "").trim();
          var width = cell.getBoundingClientRect().width;
          if (text.length >= 24) { longWidths.push(width); }
          if (cell.querySelector("code")) { codeWidths.push(width); }
          var cellRect = cell.getBoundingClientRect();
          Array.prototype.slice.call(cell.querySelectorAll("code")).forEach(function (code) {
            var codeRect = code.getBoundingClientRect();
            if (codeRect.left < cellRect.left - 2 || codeRect.right > cellRect.right + 2) {
              overlappingCodeCount += 1;
            }
          });
        });
        var minLongCellWidth = longWidths.length ? Math.min.apply(Math, longWidths) : 0;
        var minCodeCellWidth = codeWidths.length ? Math.min.apply(Math, codeWidths) : 0;
        var clipped = rect.left < -2 || rect.right > viewportWidth + 2;
        if (clipped) { clippedCount += 1; }
        if (scrollOverflow > 2) { scrollableCount += 1; }
        if (scrollLeft > 1) { initialScrolledCount += 1; }
        if (minLongCellWidth > 0 && minLongCellWidth < 120) { collapsedLongCellCount += 1; }
        if (minCodeCellWidth > 0 && minCodeCellWidth < 140) { collapsedCodeCellCount += 1; }
        if (scrollOverflow <= 2 && columnCount >= 2 && columnCount <= 4 && table.clientWidth >= Math.min(900, viewportWidth - 24) && columnRatio > 3) {
          imbalancedTableCount += 1;
        }
        return {
          index: index,
          left: rect.left,
          right: rect.right,
          clientWidth: table.clientWidth,
          scrollWidth: table.scrollWidth,
          scrollOverflow: scrollOverflow,
          scrollLeft: scrollLeft,
          minLongCellWidth: minLongCellWidth,
          minCodeCellWidth: minCodeCellWidth,
          columnCount: columnCount,
          columnRatio: columnRatio
        };
      });
      window.webkit.messageHandlers.ouro.postMessage({
        type: "tablewrap",
        tableCount: tables.length,
        pageOverflow: pageOverflow,
        clippedCount: clippedCount,
        collapsedLongCellCount: collapsedLongCellCount,
        collapsedCodeCellCount: collapsedCodeCellCount,
        imbalancedTableCount: imbalancedTableCount,
        overlappingCodeCount: overlappingCodeCount,
        initialScrolledCount: initialScrolledCount,
        scrollableCount: scrollableCount,
        tableDetails: tableDetails
      });
    })();
    """#
}

private func jsLiteral(_ value: String) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: [value]),
       let json = String(data: data, encoding: .utf8) {
        return String(json.dropFirst().dropLast())
    }
    return "\"\""
}
