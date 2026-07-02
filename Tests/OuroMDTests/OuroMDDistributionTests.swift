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
}
