import Foundation

enum PrintPreviewPhase: Equatable {
    case extractingHTML
    case loadingHTML
    case paginating
    case capturingPages(completed: Int, total: Int)
    case assemblingPDF
    case ready
    case failed

    var code: String {
        switch self {
        case .extractingHTML: return "extracting_html"
        case .loadingHTML: return "loading_html"
        case .paginating: return "paginating"
        case .capturingPages: return "capturing_pages"
        case .assemblingPDF: return "assembling_pdf"
        case .ready: return "ready"
        case .failed: return "failed"
        }
    }
}

@MainActor
final class PrintPreviewTrace {
    private let started = ProcessInfo.processInfo.systemUptime
    private(set) var events: [[String: Any]] = []

    var elapsedSeconds: Double { ProcessInfo.processInfo.systemUptime - started }

    func record(_ phase: PrintPreviewPhase) {
        var event: [String: Any] = ["phase": phase.code, "seconds": elapsedSeconds]
        if case .capturingPages(let completed, let total) = phase {
            event["completed"] = completed
            event["total"] = total
        }
        events.append(event)
    }
}
