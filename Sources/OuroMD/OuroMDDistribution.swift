import Foundation
import OuroAppShellContract

enum OuroMDDistributionChannel: String, Sendable {
    case developerID = "developer-id"
    case appStore = "app-store"
    case local

    var allowsDirectUpdates: Bool {
        switch self {
        case .developerID, .local:
            return true
        case .appStore:
            return false
        }
    }

    var appShellDistributionChannel: DistributionChannel {
        switch self {
        case .developerID, .local:
            return .directDownload
        case .appStore:
            return .appStore
        }
    }
}

enum OuroMDDistribution {
    static let infoDictionaryKey = "OuroMDDistributionChannel"

    static func channel(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> OuroMDDistributionChannel {
        guard let raw = infoDictionary?[infoDictionaryKey] as? String,
              let channel = OuroMDDistributionChannel(rawValue: raw) else {
            return .developerID
        }
        return channel
    }

    static func allowsDirectUpdates(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> Bool {
        channel(infoDictionary: infoDictionary).allowsDirectUpdates
    }
}
