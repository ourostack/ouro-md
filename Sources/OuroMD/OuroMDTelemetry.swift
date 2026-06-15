import Combine
import Foundation

enum OuroMDTelemetryValue: Encodable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        }
    }
}

struct OuroMDTelemetryConfiguration: Equatable, Sendable {
    static let defaultHost = "https://us.i.posthog.com"

    var apiKey: String
    var host: URL

    var captureURL: URL {
        let base = host.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)/i/v0/e/")!
    }

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> OuroMDTelemetryConfiguration? {
        if truthy(environment["OURO_MD_TELEMETRY_DISABLED"])
            || truthy(environment["VITE_POSTHOG_DISABLED"]) {
            return nil
        }

        _ = defaults

        let apiKey = firstNonEmpty(
            bundle.object(forInfoDictionaryKey: "OuroMDPostHogKey") as? String
        )
        guard let apiKey else { return nil }

        let hostValue = firstNonEmpty(
            bundle.object(forInfoDictionaryKey: "OuroMDPostHogHost") as? String,
            defaultHost
        ) ?? defaultHost
        guard let host = URL(string: hostValue), host.scheme != nil, host.host != nil else {
            return nil
        }

        return OuroMDTelemetryConfiguration(apiKey: apiKey, host: host)
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    static func truthy(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}

private let ouroMDDefaultTelemetrySender: (URLRequest) -> Void = { request in
    Task.detached(priority: .utility) {
        _ = try? await URLSession.shared.data(for: request)
    }
}

@MainActor
final class OuroMDTelemetry: ObservableObject {
    static let shared = OuroMDTelemetry()
    static let enabledDefaultsKey = "ouro.telemetry.enabled"
    static let distinctIDDefaultsKey = "ouro.telemetry.distinctID"

    @Published private(set) var isConfigured: Bool
    @Published private(set) var isEnabled: Bool

    private let defaults: UserDefaults
    private let configuration: OuroMDTelemetryConfiguration?
    private let sender: (URLRequest) -> Void
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        configuration: OuroMDTelemetryConfiguration? = OuroMDTelemetryConfiguration.load(),
        sender: @escaping (URLRequest) -> Void = ouroMDDefaultTelemetrySender,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.configuration = configuration
        self.sender = sender
        self.now = now
        self.isConfigured = configuration != nil
        self.isEnabled = configuration != nil
            && (defaults.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
        isEnabled = enabled && isConfigured
    }

    func capture(_ event: String, properties: [String: OuroMDTelemetryValue] = [:]) {
        guard isEnabled, let configuration else { return }
        let payload = Payload(
            apiKey: configuration.apiKey,
            event: event,
            distinctID: distinctID(),
            properties: standardProperties().merging(properties) { _, new in new },
            timestamp: Self.iso8601(now())
        )

        guard let body = try? JSONEncoder().encode(payload) else { return }
        var request = URLRequest(url: configuration.captureURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(OuroMDRelease.userAgent, forHTTPHeaderField: "User-Agent")
        sender(request)
    }

    private func distinctID() -> String {
        if let existing = defaults.string(forKey: Self.distinctIDDefaultsKey),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }
        let generated = "ouro-md-\(UUID().uuidString.lowercased())"
        defaults.set(generated, forKey: Self.distinctIDDefaultsKey)
        return generated
    }

    private func standardProperties() -> [String: OuroMDTelemetryValue] {
        [
            "$lib": .string("ouro-md-swift"),
            "$process_person_profile": .bool(false),
            "app_name": .string(OuroMDRelease.appName),
            "app_version": .string(OuroMDRelease.version),
            "bundle_id": .string(OuroMDRelease.bundleIdentifier),
            "os_version": .string(ProcessInfo.processInfo.operatingSystemVersionString),
            "architecture": .string(Self.architecture),
        ]
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private struct Payload: Encodable {
        var apiKey: String
        var event: String
        var distinctID: String
        var properties: [String: OuroMDTelemetryValue]
        var timestamp: String

        private enum CodingKeys: String, CodingKey {
            case apiKey = "api_key"
            case event
            case distinctID = "distinct_id"
            case properties
            case timestamp
        }
    }
}
