import Foundation

@MainActor
enum TerminationSaveCoordinator {
    typealias SaveOperation = (@escaping (Bool) -> Void) -> Void

    static func saveAll(
        _ saveOperations: [SaveOperation],
        timeout: TimeInterval? = 4,
        onCancel: @escaping @MainActor () -> Void = {},
        reply: @escaping @MainActor (Bool) -> Void
    ) {
        guard !saveOperations.isEmpty else {
            reply(true)
            return
        }

        var remaining = saveOperations.count
        var didReply = false

        func finish(_ ok: Bool) {
            guard !didReply else { return }
            didReply = true
            if !ok { onCancel() }
            reply(ok)
        }

        for save in saveOperations {
            save { ok in
                Task { @MainActor in
                    guard !didReply else { return }
                    guard ok else {
                        finish(false)
                        return
                    }
                    remaining -= 1
                    if remaining == 0 {
                        finish(true)
                    }
                }
            }
        }

        if let timeout {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                Task { @MainActor in
                    finish(false)
                }
            }
        }
    }
}
