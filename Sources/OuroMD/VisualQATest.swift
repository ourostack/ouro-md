import AppKit
import WebKit

/// Headless `--visualqatest`: loads a dogfood-shaped document that is broader
/// than table-only fixtures and fails on obvious visual regressions: document
/// overflow, escaped headings/images, missing callouts, collapsed table cells,
/// and sparse-table imbalance.
final class VisualQATester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let markdownPath: String?
    private let viewportWidth: CGFloat
    private let viewportHeight: CGFloat
    private let theme: Theme
    private let zoom: Double

    init(markdownPath: String? = nil, viewportWidth: CGFloat = 720, viewportHeight: CGFloat = 900, themeID: String = "quartz", zoom: Double = 1.0) {
        self.zoom = zoom
        self.markdownPath = markdownPath
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.theme = ThemeStore.shared.theme(id: themeID)
    }

    func run() -> Never {
        let app = NSApplication.shared
        HeadlessHarness.configure()

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let frame = NSRect(x: 0, y: 0, width: viewportWidth, height: viewportHeight)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        EditorZoom.apply(zoom, to: webView)
        guard let indexURL = OuroResources.web("index", "html") else {
            FileHandle.standardError.write(Data("visualqatest: index.html not found\n".utf8)); exit(1)
        }
        HeadlessHarness.offscreenHost(webView, size: frame.size)

        webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 24) {
            FileHandle.standardError.write(Data("visualqatest: timed out\n".utf8)); exit(1)
        }
        app.run()
        exit(0)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
            webView.evaluateJavaScript("window.ouro.setTheme(\(jsLiteral(theme.uiMode)),\(jsLiteral(theme.editorCSS)),\(jsLiteral(codeTheme)),\(jsLiteral(theme.backgroundHex)))", completionHandler: nil)
            webView.evaluateJavaScript("window.ouro.setDocBase(\(jsLiteral(markdownBasePath)))", completionHandler: nil)
            webView.evaluateJavaScript("window.ouro.setValue(\(jsLiteral(markdown)))", completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.webView.evaluateJavaScript(Self.measureScript, completionHandler: nil)
            }
        } else if type == "visualqa" {
            let pageOverflow = (body["pageOverflow"] as? Double) ?? .infinity
            let headingCount = (body["headingCount"] as? Int) ?? 0
            let longHeadingCount = (body["longHeadingCount"] as? Int) ?? 0
            let escapedHeadingCount = (body["escapedHeadingCount"] as? Int) ?? .max
            let imageCount = (body["imageCount"] as? Int) ?? 0
            let unloadedImageCount = (body["unloadedImageCount"] as? Int) ?? .max
            let escapedImageCount = (body["escapedImageCount"] as? Int) ?? .max
            let nestedListCount = (body["nestedListCount"] as? Int) ?? 0
            let alertCount = (body["alertCount"] as? Int) ?? 0
            let tableCount = (body["tableCount"] as? Int) ?? 0
            let tableOverflowCount = (body["tableOverflowCount"] as? Int) ?? .max
            let collapsedCellCount = (body["collapsedCellCount"] as? Int) ?? .max
            let imbalancedTableCount = (body["imbalancedTableCount"] as? Int) ?? .max
            let layoutWidth = (body["layoutWidth"] as? Double) ?? 0
            let columnSkew = (body["columnSkew"] as? Double) ?? .infinity
            let nativeMarkerCount = (body["nativeMarkerCount"] as? Int) ?? .max
            let listItemCount = (body["listItemCount"] as? Int) ?? 0

            let pageOK = pageOverflow <= 2
            let headingOK = headingCount >= 2 && longHeadingCount >= 1 && escapedHeadingCount == 0
            let imageOK = imageCount >= 1 && unloadedImageCount == 0 && escapedImageCount == 0
            let listOK = nestedListCount >= 2
            let alertOK = alertCount >= 2
            let tableOK = tableCount >= 2 && tableOverflowCount == 0 && collapsedCellCount == 0 && imbalancedTableCount == 0
            // Text size must reflow the page (layout width shrinks by the zoom
            // factor) and keep the column centered, not magnify a full-width page.
            let expectedLayoutWidth = Double(viewportWidth) / zoom
            let zoomOK = abs(layoutWidth - expectedLayoutWidth) <= 2 && columnSkew <= 2
            // Native ::marker boxes paint seams in a selection; every list item
            // except task items must use the generated marker instead.
            let markerOK = listItemCount >= 1 && nativeMarkerCount == 0

            print(String(format: "page horizontal overflow: %.1fpx %@", pageOverflow, pageOK ? "✓" : "✗"))
            print("headings: \(headingCount), long: \(longHeadingCount), escaped: \(escapedHeadingCount) \(headingOK ? "✓" : "✗")")
            print("images: \(imageCount), unloaded: \(unloadedImageCount), escaped: \(escapedImageCount) \(imageOK ? "✓" : "✗")")
            print("nested list items: \(nestedListCount) \(listOK ? "✓" : "✗")")
            print("callouts: \(alertCount) \(alertOK ? "✓" : "✗")")
            print("tables: \(tableCount), escaped: \(tableOverflowCount), collapsed cells: \(collapsedCellCount), imbalanced: \(imbalancedTableCount) \(tableOK ? "✓" : "✗")")
            print(String(format: "zoom %.2f: layout width %.1fpx (expected %.1fpx), column skew %.1fpx %@", zoom, layoutWidth, expectedLayoutWidth, columnSkew, zoomOK ? "✓" : "✗"))
            print("list items: \(listItemCount), with native markers: \(nativeMarkerCount) \(markerOK ? "✓" : "✗")")
            exit(pageOK && headingOK && imageOK && listOK && alertOK && tableOK && zoomOK && markerOK ? 0 : 1)
        }
    }

    private var markdown: String {
        if let markdownPath {
            let url = URL(fileURLWithPath: markdownPath)
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                FileHandle.standardError.write(Data("visualqatest: could not read \(markdownPath): \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        return Self.fallbackMarkdown
    }

    private var markdownBasePath: String {
        guard let markdownPath else { return "" }
        return URL(fileURLWithPath: markdownPath).deletingLastPathComponent().path
    }

    private static let fallbackMarkdown = """
    # Visual QA Fallback With A Very Long Heading That Must Wrap Beautifully Without Pushing The Whole Document Sideways

    ## Mixed Surface Fallback Targets

    ![Small fixture image](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l1n1ywAAAABJRU5ErkJggg==)

    - Parent
      - Child
        - Grandchild

    > [!NOTE]
    > A note callout should keep its body visible.

    > [!WARNING]
    > A warning callout should keep its body visible too.

    | Surface | Evidence | Code |
    | - | - | - |
    | Long prose | The table should be readable without collapsing into ribbons, while the page itself remains stable. | `Sources/OuroMD/VisualQATest.swift` |

    | Sparse | Wide |
    | - | - |
    | `/Users/example/Projects/ouro-md/tasks/2026-06-20-visual-surface-fixture.md` | This sparse row must not create a ridiculous empty column or force document-level scroll. |
    """

    private static let measureScript = #"""
    (function () {
      var de = document.documentElement;
      var viewportWidth = de.clientWidth;
      var pageOverflow = Math.max(de.scrollWidth, document.body.scrollWidth) - viewportWidth;
      var root = document.getElementById("editor") || document.body;
      function escapes(el) {
        var rect = el.getBoundingClientRect();
        return rect.left < -2 || rect.right > viewportWidth + 2;
      }
      var headings = Array.prototype.slice.call(root.querySelectorAll("h1,h2,h3,h4,h5,h6"));
      var longHeadings = headings.filter(function (h) { return (h.textContent || "").length > 70; });
      var escapedHeadingCount = headings.filter(escapes).length;
      var images = Array.prototype.slice.call(root.querySelectorAll("img"));
      var unloadedImageCount = images.filter(function (img) { return !img.complete || img.naturalWidth <= 0 || img.naturalHeight <= 0; }).length;
      var escapedImageCount = images.filter(escapes).length;
      var nestedListCount = root.querySelectorAll("li li").length;
      var alertCount = root.querySelectorAll("blockquote.ouro-alert").length;
      var tables = Array.prototype.slice.call(root.querySelectorAll("table"));
      var tableOverflowCount = 0;
      var collapsedCellCount = 0;
      var imbalancedTableCount = 0;
      // Column widths of a table, taken from its widest row.
      function columnWidthsOf(table) {
        var columnWidths = [];
        Array.prototype.slice.call(table.querySelectorAll("tr")).forEach(function (row) {
          var widths = Array.prototype.slice.call(row.children || []).map(function (cell) {
            return cell.getBoundingClientRect().width;
          });
          if (widths.length > columnWidths.length) { columnWidths = widths; }
        });
        return columnWidths;
      }
      // Natural column widths: the same table laid out with no width cap, so
      // each column takes the width its content asks for (cells keep their own
      // max-width, so long prose still wraps at its readable measure).
      function naturalColumnWidthsOf(table) {
        var clone = table.cloneNode(true);
        ["position:absolute", "visibility:hidden", "left:0", "top:0", "width:max-content", "max-width:none"].forEach(function (rule) {
          var parts = rule.split(":");
          clone.style.setProperty(parts[0], parts[1], "important");
        });
        table.parentNode.appendChild(clone);
        var widths = columnWidthsOf(clone);
        clone.parentNode.removeChild(clone);
        return widths;
      }
      tables.forEach(function (table) {
        if (escapes(table)) { tableOverflowCount += 1; }
        Array.prototype.slice.call(table.querySelectorAll("th,td")).forEach(function (cell) {
          var text = (cell.textContent || "").trim();
          var width = cell.getBoundingClientRect().width;
          if ((text.length >= 24 || cell.querySelector("code")) && width < 120) { collapsedCellCount += 1; }
        });
        // Sparse-table imbalance means a column stretched well past what its
        // content needs, leaving a wide empty band. A large ratio between the
        // widest and narrowest column is not enough on its own: WebKit shares a
        // capped table's width in proportion to each column's natural width, so
        // a short label column next to prose stays near its minimum while the
        // prose columns grow with the window. Columns squeezed into ribbons are
        // caught by the collapsed-cell check above.
        var columnWidths = columnWidthsOf(table);
        var naturalWidths = naturalColumnWidthsOf(table);
        if (naturalWidths.length !== columnWidths.length) { imbalancedTableCount += 1; return; }
        var stretched = columnWidths.some(function (width, index) {
          var natural = naturalWidths[index];
          return width > natural + 24 && width > natural * 1.25;
        });
        if (stretched) { imbalancedTableCount += 1; }
      });
      var column = root.querySelector(".vditor-ir .vditor-reset") || root.querySelector(".vditor-reset");
      var columnRect = column ? column.getBoundingClientRect() : { left: 0, right: viewportWidth };
      var columnSkew = Math.abs(columnRect.left - (viewportWidth - columnRect.right));
      var listItems = Array.prototype.slice.call(root.querySelectorAll(".vditor-reset li:not(.vditor-task)"));
      var nativeMarkerCount = listItems.filter(function (li) {
        return getComputedStyle(li).listStyleType !== "none" || getComputedStyle(li, "::before").content === "none";
      }).length;
      window.webkit.messageHandlers.ouro.postMessage({
        type: "visualqa",
        layoutWidth: window.innerWidth,
        columnSkew: columnSkew,
        listItemCount: listItems.length,
        nativeMarkerCount: nativeMarkerCount,
        pageOverflow: pageOverflow,
        headingCount: headings.length,
        longHeadingCount: longHeadings.length,
        escapedHeadingCount: escapedHeadingCount,
        imageCount: images.length,
        unloadedImageCount: unloadedImageCount,
        escapedImageCount: escapedImageCount,
        nestedListCount: nestedListCount,
        alertCount: alertCount,
        tableCount: tables.length,
        tableOverflowCount: tableOverflowCount,
        collapsedCellCount: collapsedCellCount,
        imbalancedTableCount: imbalancedTableCount
      });
    })();
    """#

    private func jsLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let json = String(data: data, encoding: .utf8) {
            return String(json.dropFirst().dropLast())
        }
        return "\"\""
    }
}
