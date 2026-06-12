import XCTest
@testable import OuroMD

final class OutlineTreeTests: XCTestCase {
    private func items(_ levels: [(Int, String)]) -> [OutlineItem] {
        levels.enumerated().map { OutlineItem(index: $0.offset, level: $0.element.0, text: $0.element.1) }
    }

    func testNestsByLevel() {
        // h1 / h2 / h3 / h2 / h1
        let tree = OutlineNode.build(from: items([(1, "A"), (2, "A1"), (3, "A1a"), (2, "A2"), (1, "B")]))
        XCTAssertEqual(tree.map(\.item.text), ["A", "B"])
        XCTAssertEqual(tree[0].children?.map(\.item.text), ["A1", "A2"])
        XCTAssertEqual(tree[0].children?[0].children?.map(\.item.text), ["A1a"])
        XCTAssertNil(tree[1].children)
    }

    func testHandlesLeadingDeepHeading() {
        // starts at h3 — should still produce roots without crashing
        let tree = OutlineNode.build(from: items([(3, "deep"), (1, "top")]))
        XCTAssertEqual(tree.map(\.item.text), ["deep", "top"])
    }
}
