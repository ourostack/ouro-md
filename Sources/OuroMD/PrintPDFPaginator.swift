import AppKit
import CoreGraphics
import Foundation
import PDFKit

struct PrintLayoutMetrics: Equatable, Sendable {
    struct Link: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var url: String?
        var destinationPageIndex: Int?
        var destinationX: Double?
        var destinationY: Double?
    }

    var contentWidth: Double
    var contentHeight: Double
    var pageGap: Double
    var pageStride: Double
    var totalWidth: Double
    var pageCount: Int
    var fragmentedProofIDs: [String]
    var links: [Link]
}

enum PrintPDFPaginator {
    enum PaginationError: LocalizedError {
        case unreadableSource
        case missingPage
        case contextCreationFailed
        case unreadableOutput

        var errorDescription: String? {
            switch self {
            case .unreadableSource:
                return "The print preview source PDF could not be read."
            case .missingPage:
                return "The print preview source PDF did not contain a page."
            case .contextCreationFailed:
                return "The paginated PDF context could not be created."
            case .unreadableOutput:
                return "The paginated PDF output could not be read back for link annotations."
            }
        }
    }

    static func paginate(
        sourcePages: [Data],
        paperSize: NSSize,
        margins: PrintPageMargins,
        pageLinks: [[PrintLayoutMetrics.Link]]
    ) throws -> Data {
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: paperSize)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PaginationError.contextCreationFailed
        }
        var destinations: [Int: [(String, CGPoint)]] = [:]
        for (sourceIndex, links) in pageLinks.enumerated() {
            for (linkIndex, link) in links.enumerated() {
                guard let target = link.destinationPageIndex, sourcePages.indices.contains(target) else { continue }
                let name = "ouro-destination-\(sourceIndex)-\(linkIndex)"
                let point = CGPoint(x: margins.left + (link.destinationX ?? 0), y: paperSize.height - margins.top - (link.destinationY ?? 0))
                destinations[target, default: []].append((name, point))
            }
        }
        for (index, pageData) in sourcePages.enumerated() {
            guard let provider = CGDataProvider(data: pageData as CFData),
                  let sourceDocument = CGPDFDocument(provider),
                  let page = sourceDocument.page(at: 1) else {
                throw PaginationError.unreadableSource
            }
            context.beginPDFPage(nil)
            context.drawPDFPage(page)
            for (name, point) in destinations[index] ?? [] {
                context.addDestination(name as CFString, at: point)
            }
            for (linkIndex, link) in (pageLinks.indices.contains(index) ? pageLinks[index] : []).enumerated() {
                let bounds = CGRect(
                    x: margins.left + link.x,
                    y: paperSize.height - margins.top - link.y - link.height,
                    width: link.width,
                    height: link.height
                ).intersection(mediaBox)
                guard !bounds.isEmpty else { continue }
                if let urlString = link.url, let url = URL(string: urlString) {
                    context.setURL(url as CFURL, for: bounds)
                } else if let target = link.destinationPageIndex, sourcePages.indices.contains(target) {
                    context.setDestination("ouro-destination-\(index)-\(linkIndex)" as CFString, for: bounds)
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
        let data = output as Data
        guard PDFDocument(data: data)?.pageCount == sourcePages.count else {
            throw PaginationError.unreadableOutput
        }
        return data
    }
}
