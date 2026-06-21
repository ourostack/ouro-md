import XCTest
@testable import OuroMD

final class FolderBrowserTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-folder-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try "# A".write(to: root.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8)
        try "# B".write(to: root.appendingPathComponent("beta.md"), atomically: true, encoding: .utf8)
        try "notes".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "# C".write(to: root.appendingPathComponent("sub/gamma.md"), atomically: true, encoding: .utf8)
        try "# hidden".write(to: root.appendingPathComponent(".secret.md"), atomically: true, encoding: .utf8)
        try "# dep".write(to: root.appendingPathComponent("node_modules/dep.md"), atomically: true, encoding: .utf8)
        try Data().write(to: root.appendingPathComponent("pic.png"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFlatListIncludesOnlyOpenableFiles() {
        let names = Set(FolderScanner.flatList(at: root, sort: .name).map(\.name))
        XCTAssertEqual(names, ["alpha.md", "beta.md", "gamma.md", "notes.txt"])
        XCTAssertFalse(names.contains(".secret.md"))   // dotfiles skipped
        XCTAssertFalse(names.contains("dep.md"))         // node_modules skipped
        XCTAssertFalse(names.contains("pic.png"))        // unsupported ext skipped
    }

    func testTreeGroupsDirsFirstAndPrunesEmpties() {
        let tree = FolderScanner.tree(at: root, sort: .name)
        XCTAssertEqual(tree.first?.name, "sub")          // dirs grouped before files
        XCTAssertTrue(tree.first?.isDirectory ?? false)
        XCTAssertEqual(tree.first?.children?.map(\.name), ["gamma.md"])
        XCTAssertFalse(tree.contains { $0.name == "node_modules" })  // empty-of-md dir pruned
    }

    func testNameSortIsNatural() {
        let names = FolderScanner.flatList(at: root, sort: .name).map(\.name)
        XCTAssertEqual(names, ["alpha.md", "beta.md", "gamma.md", "notes.txt"])
    }

    func testSnapshotProvidesTreeAndFlatViewsFromOneAPI() {
        let snapshot = FolderScanner.snapshot(at: root, sort: .name)

        XCTAssertEqual(snapshot.tree, FolderScanner.tree(at: root, sort: .name))
        XCTAssertEqual(snapshot.flat, FolderScanner.flatList(at: root, sort: .name))
        XCTAssertEqual(snapshot.flat.map(\.name), ["alpha.md", "beta.md", "gamma.md", "notes.txt"])
        XCTAssertEqual(snapshot.flat.first?.id, snapshot.flat.first?.url)
        XCTAssertEqual(snapshot.tree.first?.name, "sub")
        XCTAssertEqual(snapshot.tree.first?.children?.map(\.name), ["gamma.md"])
    }

    func testFolderSortLabelsAndDateSorts() {
        XCTAssertEqual(FolderSort.natural.label, "Sort Naturally")
        XCTAssertEqual(FolderSort.name.label, "Sort by Name")
        XCTAssertEqual(FolderSort.modified.label, "Sort by Modified Date")
        XCTAssertEqual(FolderSort.created.label, "Sort by Created Date")

        XCTAssertFalse(FolderScanner.flatList(at: root, sort: .modified).isEmpty)
        XCTAssertFalse(FolderScanner.flatList(at: root, sort: .created).isEmpty)
    }

    func testSnapshotOfMissingFolderIsEmpty() {
        let missing = root.appendingPathComponent("missing")
        let snapshot = FolderScanner.snapshot(at: missing, sort: .name)

        XCTAssertTrue(snapshot.tree.isEmpty)
        XCTAssertTrue(snapshot.flat.isEmpty)
    }

    func testSymlinkCycleDoesNotCrashOrRecurse() {
        // A symlink loop (cyc/loop -> cyc) must not be followed (no stack overflow).
        let fm = FileManager.default
        let cyc = root.appendingPathComponent("cyc")
        try? fm.createDirectory(at: cyc, withIntermediateDirectories: true)
        try? "# x".write(to: cyc.appendingPathComponent("x.md"), atomically: true, encoding: .utf8)
        try? fm.createSymbolicLink(at: cyc.appendingPathComponent("loop"), withDestinationURL: cyc)

        let tree = FolderScanner.tree(at: cyc, sort: .name)   // must return, not crash
        XCTAssertTrue(tree.contains { $0.name == "x.md" })
        XCTAssertFalse(tree.contains { $0.name == "loop" }, "symlinks must be skipped")
    }

    func testDeepTreeReportsTruncationAtDepthCap() throws {
        var dir = root.appendingPathComponent("deep")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<28 {
            dir = dir.appendingPathComponent("level-\(i)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try "# too deep".write(to: dir.appendingPathComponent("buried.md"), atomically: true, encoding: .utf8)

        let snapshot = FolderScanner.snapshot(at: root.appendingPathComponent("deep"), sort: .name)

        XCTAssertTrue(snapshot.isTruncated)
        XCTAssertFalse(snapshot.isCancelled)
        XCTAssertFalse(snapshot.flat.contains { $0.name == "buried.md" })
    }

    func testUnusualNamesDuplicateBasenamesAndSymlinkedMarkdownAreHandled() throws {
        let fm = FileManager.default
        let weird = root.appendingPathComponent("sp ace/[draft] #1")
        try fm.createDirectory(at: weird, withIntermediateDirectories: true)
        let unicode = weird.appendingPathComponent("Résumé 🧪 10.md")
        let duplicateA = weird.appendingPathComponent("README.md")
        let duplicateBDir = root.appendingPathComponent("other")
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).md")
        try fm.createDirectory(at: duplicateBDir, withIntermediateDirectories: true)
        try "# unicode".write(to: unicode, atomically: true, encoding: .utf8)
        try "# a".write(to: duplicateA, atomically: true, encoding: .utf8)
        try "# b".write(to: duplicateBDir.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try "# outside".write(to: outside, atomically: true, encoding: .utf8)
        try? fm.createSymbolicLink(at: root.appendingPathComponent("linked.md"), withDestinationURL: outside)
        defer { try? fm.removeItem(at: outside) }

        let snapshot = FolderScanner.snapshot(at: root, sort: .name)
        let names = Set(snapshot.flat.map(\.name))
        let duplicateNames = FolderDisplay.duplicateNames(in: snapshot.flat)

        XCTAssertTrue(names.contains("Résumé 🧪 10.md"))
        XCTAssertTrue(names.contains("README.md"))
        XCTAssertTrue(names.contains("readme.md"))
        XCTAssertFalse(names.contains("linked.md"))
        XCTAssertTrue(duplicateNames.contains("readme.md"))
        let unicodeNode = try XCTUnwrap(snapshot.flat.first { $0.name == "Résumé 🧪 10.md" })
        XCTAssertEqual(FolderDisplay.parentHint(unicodeNode.url, under: root), "sp ace/[draft] #1")
        XCTAssertTrue(
            FolderDisplay.accessibilityLabel(for: unicodeNode, under: root, includeParent: true)
                .contains("Résumé 🧪 10.md")
        )
    }

    func testLargeWorkspaceBudgetSkipsOversizedHiddenAndSymlinkedFiles() throws {
        let fm = FileManager.default
        let large = root.appendingPathComponent("large")
        try fm.createDirectory(at: large, withIntermediateDirectories: true)
        for bucket in 0..<11 {
            try fm.createDirectory(at: large.appendingPathComponent("bucket-\(bucket)"), withIntermediateDirectories: true)
        }
        for i in 0..<5_080 {
            let dir = large.appendingPathComponent("bucket-\(i % 11)")
            let file = dir.appendingPathComponent(String(format: "note-%04d.md", i))
            try "needle \(i)\n".write(to: file, atomically: true, encoding: .utf8)
        }
        try Data(repeating: 0x61, count: 2_000_001)
            .write(to: large.appendingPathComponent("oversized.md"))
        try "# hidden".write(to: large.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)
        try? fm.createSymbolicLink(
            at: large.appendingPathComponent("loop"),
            withDestinationURL: large
        )

        let start = Date()
        let snapshot = FolderScanner.snapshot(at: large, sort: .name)
        let elapsed = Date().timeIntervalSince(start)
        let names = Set(snapshot.flat.map(\.name))

        XCTAssertEqual(snapshot.flat.count, 5_000, "scanner should stop at its fixed safety budget")
        XCTAssertTrue(snapshot.isTruncated, "scanner should report that additional openable files were omitted")
        XCTAssertLessThan(elapsed, 10, "budgeted scan should stay responsive even with thousands of files")
        XCTAssertFalse(names.contains("oversized.md"))
        XCTAssertFalse(names.contains(".hidden.md"))
        XCTAssertFalse(names.contains("loop"))
        XCTAssertFalse(snapshot.tree.isEmpty)
    }

    func testReadsNonUTF8File() {
        let url = root.appendingPathComponent("utf16.md")
        try? "# café — résumé".data(using: .utf16)!.write(to: url)
        XCTAssertEqual(AppModel.readText(at: url), "# café — résumé")
    }

    func testOpenFolderPopulatesModelAndFilter() {
        let model = AppModel()
        model.openFolder(root)
        let populated = expectation(description: "folder scanned")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if !model.folderFlat.isEmpty { populated.fulfill() }
        }
        wait(for: [populated], timeout: 3)
        XCTAssertEqual(model.mountedFolderName, root.lastPathComponent)
        XCTAssertEqual(model.folderFlat.count, 4)
        XCTAssertFalse(model.folderScanIsTruncated)
        XCTAssertNil(model.folderTruncationMessage)

        model.folderFilter = "gam"
        XCTAssertEqual(model.filteredFolderFiles.map(\.name), ["gamma.md"])
        model.folderFilter = "a md"   // fuzzy ordered-subsequence
        XCTAssertTrue(model.filteredFolderFiles.contains { $0.name == "alpha.md" })
    }
}
