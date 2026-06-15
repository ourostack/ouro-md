import Foundation
import XCTest
@testable import OuroMD

@MainActor
final class OuroMDTelemetryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OuroMDTelemetryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testConfigurationLoadsPostHogEnvironment() {
        defaults.set("phc_test", forKey: "ouro.telemetry.posthogKey")
        defaults.set("https://eu.i.posthog.com", forKey: "ouro.telemetry.posthogHost")

        let config = OuroMDTelemetryConfiguration.load(
            bundle: Bundle(for: Self.self),
            environment: [:],
            defaults: defaults
        )

        XCTAssertEqual(config?.apiKey, "phc_test")
        XCTAssertEqual(config?.host.absoluteString, "https://eu.i.posthog.com")
        XCTAssertEqual(config?.captureURL.absoluteString, "https://eu.i.posthog.com/i/v0/e/")
    }

    func testConfigurationIgnoresAmbientPostHogKeyEnvironmentAndSupportsDisableFlag() {
        let ambientEnvironmentConfig = OuroMDTelemetryConfiguration.load(
            bundle: Bundle(for: Self.self),
            environment: [
                "OURO_MD_POSTHOG_KEY": "phc_ambient",
                "VITE_POSTHOG_KEY": "phc_spoonjoy",
                "VITE_POSTHOG_HOST": "https://eu.i.posthog.com",
            ],
            defaults: defaults
        )

        XCTAssertNil(ambientEnvironmentConfig)

        defaults.set("phc_spoonjoy", forKey: "ouro.telemetry.posthogKey")

        let disabled = OuroMDTelemetryConfiguration.load(
            bundle: Bundle(for: Self.self),
            environment: [
                "VITE_POSTHOG_DISABLED": "true",
            ],
            defaults: defaults
        )
        XCTAssertNil(disabled)
    }

    func testCaptureSendsAnonymousPostHogPayload() throws {
        let config = OuroMDTelemetryConfiguration(
            apiKey: "phc_test",
            host: URL(string: "https://us.i.posthog.com")!
        )
        var requests: [URLRequest] = []
        let telemetry = OuroMDTelemetry(
            defaults: defaults,
            configuration: config,
            sender: { requests.append($0) },
            now: { Date(timeIntervalSince1970: 0) }
        )

        telemetry.capture("ouro_md_test_event", properties: ["answer": .int(42), "ok": .bool(true)])

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://us.i.posthog.com/i/v0/e/")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(requests[0].httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let properties = try XCTUnwrap(json["properties"] as? [String: Any])

        XCTAssertEqual(json["api_key"] as? String, "phc_test")
        XCTAssertEqual(json["event"] as? String, "ouro_md_test_event")
        XCTAssertTrue((json["distinct_id"] as? String)?.hasPrefix("ouro-md-") == true)
        XCTAssertEqual(json["timestamp"] as? String, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(properties["$process_person_profile"] as? Bool, false)
        XCTAssertEqual(properties["app_name"] as? String, "Ouro MD")
        XCTAssertEqual(properties["answer"] as? Int, 42)
        XCTAssertEqual(properties["ok"] as? Bool, true)
    }

    func testOptOutSuppressesCaptureAndPersists() {
        let config = OuroMDTelemetryConfiguration(
            apiKey: "phc_test",
            host: URL(string: "https://us.i.posthog.com")!
        )
        var requests: [URLRequest] = []
        let telemetry = OuroMDTelemetry(
            defaults: defaults,
            configuration: config,
            sender: { requests.append($0) }
        )

        XCTAssertTrue(telemetry.isEnabled)
        telemetry.setEnabled(false)
        telemetry.capture("ouro_md_test_event")

        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(defaults.object(forKey: OuroMDTelemetry.enabledDefaultsKey) as? Bool, false)

        let restored = OuroMDTelemetry(
            defaults: defaults,
            configuration: config,
            sender: { requests.append($0) }
        )
        XCTAssertFalse(restored.isEnabled)
    }
}
