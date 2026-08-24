import XCTest
@testable import OuroMD

final class RoundTripTests: XCTestCase {
    func testStrictRawRoundTripRequiresBothEditorValuesToMatchOriginalBytes() {
        let original = "# Heading\n\nBody\n"

        XCTAssertTrue(RoundTripper.strictRawRoundTripMatches(
            original: original,
            raw: original,
            bridge: original
        ))
        XCTAssertFalse(RoundTripper.strictRawRoundTripMatches(
            original: original,
            raw: "# Heading\nBody\n",
            bridge: original
        ))
        XCTAssertFalse(RoundTripper.strictRawRoundTripMatches(
            original: original,
            raw: original,
            bridge: "# Heading\nBody\n"
        ))
    }
}
