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

        model.folderFilter = "gam"
        XCTAssertEqual(model.filteredFolderFiles.map(\.name), ["gamma.md"])
        model.folderFilter = "a md"   // fuzzy ordered-subsequence
        XCTAssertTrue(model.filteredFolderFiles.contains { $0.name == "alpha.md" })
    }
}
