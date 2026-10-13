import AppKit
import CoreGraphics
import Foundation
import PDFKit

struct PrintLayoutMetrics: Equatable, Sendable {
    struct EndnoteLink: Equatable, Sendable {
        var url: String
        var pageIndex: Int
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    var contentWidth: Double
    var contentHeight: Double
    var pageGap: Double
    var pageStride: Double
    var totalWidth: Double
    var pageCount: Int
    var fragmentedProofIDs: [String]
    var endnoteLinks: [EndnoteLink]
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
        pageLinks: [[PrintLayoutMetrics.EndnoteLink]]
    ) throws -> Data {
        _ = margins
        let document = PDFDocument()
        for (index, pageData) in sourcePages.enumerated() {
            guard let sourceDocument = PDFDocument(data: pageData),
                  let page = sourceDocument.page(at: 0) else {
                throw PaginationError.unreadableSource
            }
            document.insert(page, at: index)
        }
        guard let combined = document.dataRepresentation() else {
            throw PaginationError.contextCreationFailed
        }
        return try addEndnoteAnnotations(to: combined, paperSize: paperSize, margins: margins, pageLinks: pageLinks)
    }

    private static func addEndnoteAnnotations(
        to data: Data,
        paperSize: NSSize,
        margins: PrintPageMargins,
        pageLinks: [[PrintLayoutMetrics.EndnoteLink]]
    ) throws -> Data {
        guard let document = PDFDocument(data: data) else {
            throw PaginationError.unreadableOutput
        }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                page.removeAnnotation(annotation)
            }
        }
        for (pageIndex, links) in pageLinks.enumerated() {
            guard let page = document.page(at: pageIndex) else { continue }
            for link in links {
                guard let url = URL(string: link.url) else { continue }
                let bounds = CGRect(
                    x: margins.left + link.x,
                    y: paperSize.height - margins.top - link.y - link.height,
                    width: link.width,
                    height: link.height
                ).intersection(page.bounds(for: .mediaBox))
                guard !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
                annotation.url = url
                page.addAnnotation(annotation)
            }
        }
        guard let annotated = document.dataRepresentation() else {
            throw PaginationError.unreadableOutput
        }
        return annotated
    }
}
