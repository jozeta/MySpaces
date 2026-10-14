import XCTest
@testable import MySpacesCore

final class NameStoreTests: XCTestCase {
    var dir: URL!
    var file: URL { dir.appendingPathComponent("nested/names.json") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRoundTripCreatesMissingDirectory() throws {
        let store = NameStore(fileURL: file)
        try store.setName("Development", for: "A")
        XCTAssertEqual(NameStore(fileURL: file).name(for: "A"), "Development")
    }

    func testNameIsTrimmedAndWhitespaceCollapsed() throws {
        let store = NameStore(fileURL: file)
        try store.setName("  Security \n  Lab  ", for: "A")
        XCTAssertEqual(store.name(for: "A"), "Security Lab")
    }

    func testEmptyNameRemovesEntry() throws {
        let store = NameStore(fileURL: file)
        try store.setName("Research", for: "A")
        try store.setName("   ", for: "A")
        XCTAssertNil(store.name(for: "A"))
        XCTAssertNil(NameStore(fileURL: file).name(for: "A"))
    }

    func testNameIsCappedAt40Characters() throws {
        let store = NameStore(fileURL: file)
        try store.setName(String(repeating: "🧪", count: 50), for: "A")
        XCTAssertEqual(store.name(for: "A")?.count, 40)
    }

    func testDuplicateNamesAreAllowed() throws {
        let store = NameStore(fileURL: file)
        try store.setName("Work", for: "A")
        try store.setName("Work", for: "B")
        XCTAssertEqual(store.names, ["A": "Work", "B": "Work"])
    }

    func testRemoveNames() throws {
        let store = NameStore(fileURL: file)
        try store.setName("One", for: "A")
        try store.setName("Two", for: "B")
        try store.removeNames(for: ["A"])
        XCTAssertEqual(NameStore(fileURL: file).names, ["B": "Two"])
    }

    func testCorruptFileIsBackedUpAndStoreStartsEmpty() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: file)
        let store = NameStore(fileURL: file)
        XCTAssertTrue(store.names.isEmpty)
        XCTAssertTrue(store.recoveredFromCorruption)
        let backup = file.appendingPathExtension("bak")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "{not json")
    }

    func testMissingFileIsNotCorruption() {
        let store = NameStore(fileURL: file)
        XCTAssertTrue(store.names.isEmpty)
        XCTAssertFalse(store.recoveredFromCorruption)
    }
}
