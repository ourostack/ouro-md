import XCTest
@testable import OuroMD
import OuroAppShellContract

final class OuroMDDistributionTests: XCTestCase {
    func testDefaultsToDeveloperIDDirectUpdates() {
        XCTAssertEqual(OuroMDDistribution.channel(infoDictionary: [:]), .developerID)
        XCTAssertTrue(OuroMDDistribution.allowsDirectUpdates(infoDictionary: [:]))
        XCTAssertEqual(OuroMDDistributionChannel.developerID.appShellDistributionChannel, .directDownload)
    }

    func testAppStoreDisablesDirectUpdates() {
        let info = [OuroMDDistribution.infoDictionaryKey: "app-store"]

        XCTAssertEqual(OuroMDDistribution.channel(infoDictionary: info), .appStore)
        XCTAssertFalse(OuroMDDistribution.allowsDirectUpdates(infoDictionary: info))
        XCTAssertEqual(OuroMDDistributionChannel.appStore.appShellDistributionChannel, .appStore)
    }

    func testLocalBuildsAllowDirectUpdates() {
        let info = [OuroMDDistribution.infoDictionaryKey: "local"]

        XCTAssertEqual(OuroMDDistribution.channel(infoDictionary: info), .local)
        XCTAssertTrue(OuroMDDistribution.allowsDirectUpdates(infoDictionary: info))
        XCTAssertEqual(OuroMDDistributionChannel.local.appShellDistributionChannel, .directDownload)
    }

    func testAppStoreManifestCarriesDistinctReviewMetadata() throws {
        let manifest = try appStoreManifest()
        let store = try XCTUnwrap(manifest["store"] as? [String: Any])

        XCTAssertEqual(store["category"] as? String, "DEVELOPER_TOOLS")
        XCTAssertEqual(store["subtitle"] as? String, "Local Markdown Workspace")

        let promotionalText = try nonEmptyString(store["promotionalText"], field: "promotionalText")
        XCTAssertLessThanOrEqual(promotionalText.count, 170)
        XCTAssertTrue(promotionalText.localizedCaseInsensitiveContains("local Markdown"))
        XCTAssertTrue(promotionalText.localizedCaseInsensitiveContains("command palette"))
        XCTAssertFalse(promotionalText.localizedCaseInsensitiveContains("quiet Markdown editor"))

        let description = try nonEmptyString(store["description"], field: "description")
        XCTAssertTrue(description.hasPrefix("Ouro MD is a local Markdown workspace"))
        XCTAssertTrue(description.localizedCaseInsensitiveContains("folder search"))
        XCTAssertTrue(description.localizedCaseInsensitiveContains("PDF"))
        XCTAssertFalse(description.localizedCaseInsensitiveContains("The Markdown App"))
        XCTAssertFalse(description.localizedCaseInsensitiveContains("quiet Markdown editor"))

        let keywords = try nonEmptyString(store["keywords"], field: "keywords")
        XCTAssertLessThanOrEqual(keywords.count, 100)
        for requiredKeyword in ["markdown", "local files", "folder search", "outline", "command palette", "pdf"] {
            XCTAssertTrue(
                keywords.localizedCaseInsensitiveContains(requiredKeyword),
                "Expected keywords to contain \(requiredKeyword)"
            )
        }

        let reviewNotes = try nonEmptyString(store["reviewNotes"], field: "reviewNotes")
        for requiredStep in ["Shift-Command-O", "File Tree", "Outline", "Search", "Command Palette", "PDF", "HTML", "No account"] {
            XCTAssertTrue(
                reviewNotes.localizedCaseInsensitiveContains(requiredStep),
                "Expected review notes to contain \(requiredStep)"
            )
        }

        let screenshots = try XCTUnwrap(store["screenshots"] as? [String])
        XCTAssertFalse(screenshots.isEmpty)
        XCTAssertTrue(screenshots.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        let privacy = try XCTUnwrap(store["privacy"] as? [String: Any])
        XCTAssertEqual(privacy["collectsData"] as? Bool, false)
        XCTAssertEqual(privacy["policyUrl"] as? String, "https://ouro.bot/privacy/")

        let exportCompliance = try XCTUnwrap(store["exportCompliance"] as? [String: Any])
        XCTAssertEqual(exportCompliance["usesEncryption"] as? Bool, true)
        XCTAssertEqual(exportCompliance["exempt"] as? Bool, true)
    }

    private func appStoreManifest() throws -> [String: Any] {
        let manifestURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("distribution/apple-distribution.json")
        let data = try Data(contentsOf: manifestURL)
        let object = try JSONSerialization.jsonObject(with: data)
        let manifest = try XCTUnwrap(object as? [String: Any])
        let channels = try XCTUnwrap(manifest["channels"] as? [[String: Any]])
        return try XCTUnwrap(channels.first { $0["id"] as? String == "mac-app-store" })
    }

    private func nonEmptyString(_ value: Any?, field: String) throws -> String {
        let string = try XCTUnwrap(value as? String, "\(field) must be a string")
        XCTAssertFalse(string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(field) must not be empty")
        return string
    }
}
