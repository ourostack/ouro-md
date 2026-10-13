import AppKit
import CoreGraphics
import Foundation

enum PrintPDFPaginator {
    enum PaginationError: LocalizedError {
        case unreadableSource
        case missingPage
        case contextCreationFailed

        var errorDescription: String? {
            switch self {
            case .unreadableSource:
                return "The print source PDF could not be read."
            case .missingPage:
                return "The print source PDF did not contain a first page."
            case .contextCreationFailed:
                return "The paginated PDF context could not be created."
            }
        }
    }

    static func paginate(sourcePDF: Data, paperSize: NSSize, margins: PrintPageMargins) throws -> Data {
        guard let provider = CGDataProvider(data: sourcePDF as CFData),
              let sourceDocument = CGPDFDocument(provider) else {
            throw PaginationError.unreadableSource
        }
        guard let page = sourceDocument.page(at: 1) else {
            throw PaginationError.missingPage
        }

        let sourceRect = page.getBoxRect(.mediaBox)
        let printableRect = CGRect(
            x: margins.left,
            y: margins.bottom,
            width: max(72, paperSize.width - margins.left - margins.right),
            height: max(72, paperSize.height - margins.top - margins.bottom)
        )
        let scale = printableRect.width / max(1, sourceRect.width)
        let sliceHeight = printableRect.height / max(scale, 0.0001)
        let pageCount = max(1, Int(ceil(sourceRect.height / sliceHeight)))

        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: paperSize)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PaginationError.contextCreationFailed
        }

        for index in 0..<pageCount {
            let consumedHeight = CGFloat(index) * sliceHeight
            let remainingHeight = max(0, sourceRect.height - consumedHeight)
            let sourceSliceHeight = min(sliceHeight, remainingHeight)
            let sourceMinY = max(0, sourceRect.height - consumedHeight - sourceSliceHeight)
            let targetHeight = sourceSliceHeight * scale
            let targetRect = CGRect(
                x: printableRect.minX,
                y: printableRect.maxY - targetHeight,
                width: printableRect.width,
                height: targetHeight
            )

            context.beginPDFPage(nil)
            context.saveGState()
            context.clip(to: targetRect)
            context.translateBy(
                x: targetRect.minX - sourceRect.minX * scale,
                y: targetRect.minY - sourceMinY * scale
            )
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(page)
            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return output as Data
    }
}
