import CoreGraphics
import Foundation
import Vision

/// Text recognition for headless harnesses that check what a view actually
/// draws. Some machines (the Xcode 27 CI image) can't run it at all; callers
/// then fail, unless CI says another job runs the check
/// (`OURO_MD_RENDERED_TEXT_AUDIT_ELSEWHERE=1`). It is never silently skipped.
enum HeadlessTextRecognition {
    /// True when recognition is unavailable here and CI runs the rendered-text
    /// checks in its Rendered text audit job instead.
    static var deferredElsewhere: Bool {
        ProcessInfo.processInfo.environment["OURO_MD_RENDERED_TEXT_AUDIT_ELSEWHERE"] == "1"
    }

    /// The recognized lines, or nil when text recognition doesn't work here.
    static func recognize(in image: CGImage, harness: String) -> Set<String>? {
        // Lets the unavailable path be exercised where recognition works.
        if ProcessInfo.processInfo.environment["OURO_MD_AUDIT_WITHOUT_TEXT_RECOGNITION"] == "1" { return nil }
        var request = makeRequest(cpuOnly: false)
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            // Virtual machines without a Neural Engine can fail here; the CPU
            // path is slower but works on more machines.
            request = makeRequest(cpuOnly: true)
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch let cpuError {
                FileHandle.standardError.write(Data("\(harness): text recognition failed: \(error); on the CPU: \(cpuError)\n".utf8))
                return nil
            }
        }
        return Set((request.results ?? []).compactMap { $0.topCandidates(1).first?.string })
    }

    private static func makeRequest(cpuOnly: Bool) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        guard cpuOnly else { return request }
        if #available(macOS 14, *) {
            if let cpu = (try? request.supportedComputeStageDevices)?[.main]?.first(where: {
                if case .cpu = $0 { return true } else { return false }
            }) {
                request.setComputeDevice(cpu, for: .main)
            }
        } else {
            request.usesCPUOnly = true
        }
        return request
    }
}
