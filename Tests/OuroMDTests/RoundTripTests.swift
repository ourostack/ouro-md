import XCTest
@testable import OuroMD

final class RoundTripTests: XCTestCase {
    func testStrictRawRoundTripRequiresBothEditorValuesToMatchOriginalBytes() {
        let original = "# Heading\n\nBody\n"
        let originalBytes = Data(original.utf8)

        XCTAssertTrue(RoundTripper.strictRawRoundTripMatches(
            original: originalBytes,
            raw: original,
            bridge: original
        ))
        XCTAssertFalse(RoundTripper.strictRawRoundTripMatches(
            original: originalBytes,
            raw: "# Heading\nBody\n",
            bridge: original
        ))
        XCTAssertFalse(RoundTripper.strictRawRoundTripMatches(
            original: originalBytes,
            raw: original,
            bridge: "# Heading\nBody\n"
        ))
    }

    func testStrictRawRoundTripRejectsCanonicalUnicodeNormalization() {
        let composed = Data("é".utf8)
        let decomposed = "e\u{301}"

        XCTAssertFalse(RoundTripper.strictRawRoundTripMatches(
            original: composed,
            raw: decomposed,
            bridge: decomposed
        ))
    }

    func testStrictRawRoundTripRejectsDroppedUTF8BOM() {
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("# Heading\n".utf8)

        XCTAssertFalse(RoundTripper.strictRawRoundTripMatches(
            original: original,
            raw: "# Heading\n",
            bridge: "# Heading\n"
        ))
    }
}
