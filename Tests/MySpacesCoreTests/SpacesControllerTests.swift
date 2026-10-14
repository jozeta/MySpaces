import XCTest
@testable import MySpacesCore

final class FakeSource: SpacesSource {
    var result: Result<[Space], Error>
    init(_ spaces: [Space]) { result = .success(spaces) }
    func currentSpaces() throws -> [Space] { try result.get() }
}

struct FakeHotkeys: HotkeySource {
    var value = SpaceHotkeys(moveLeft: KeyChord(keyCode: 123, modifierFlags: 0x840000),
                             moveRight: KeyChord(keyCode: 124, modifierFlags: 0x840000), desktops: [:])
    func hotkeys() -> SpaceHotkeys { value }
}

final class FakeKeys: KeyPosting {
    var posted: [(KeyChord, Int)] = []
    func post(_ chord: KeyChord, times: Int) { posted.append((chord, times)) }
}

final class SpacesControllerTests: XCTestCase {
    var file: URL!
    override func setUp() { file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json") }
    override func tearDown() { try? FileManager.default.removeItem(at: file) }

    func make(_ spaces: [Space], keys: FakeKeys = FakeKeys()) -> (SpacesController, FakeSource, NameStore) {
        let source = FakeSource(spaces)
        let store = NameStore(fileURL: file)
        return (SpacesController(source: source, store: store, hotkeys: FakeHotkeys(), keys: keys), source, store)
    }

    func testRefreshBuildsRows() {
        let (c, _, _) = make([desktop(1, "", current: true), desktop(2, "B")])
        c.refresh()
        XCTAssertEqual(c.rows.map(\.title), ["Desktop 1", "Desktop 2"])
        XCTAssertNil(c.lastError)
    }

    func testRenameUpdatesRowsAndStore() throws {
        let (c, _, store) = make([desktop(1, "", current: true), desktop(2, "B")])
        c.refresh()
        try c.rename(key: "B", to: " Research ")
        XCTAssertEqual(c.rows[1].title, "Research")
        XCTAssertEqual(store.name(for: "B"), "Research")
    }

    func testDeletedSpaceNamePrunedOnSecondRefresh() throws {
        let (c, source, store) = make([desktop(1, "", current: true), desktop(2, "B")])
        c.refresh()
        try c.rename(key: "B", to: "Gone soon")
        source.result = .success([desktop(1, "", current: true)])
        c.refresh()
        XCTAssertEqual(store.name(for: "B"), "Gone soon")
        c.refresh()
        XCTAssertNil(store.name(for: "B"))
    }

    func testRefreshFailureKeepsNamesAndReportsError() throws {
        let (c, source, store) = make([desktop(1, "", current: true), desktop(2, "B")])
        c.refresh()
        try c.rename(key: "B", to: "Keep")
        source.result = .failure(NSError(domain: "t", code: 1))
        c.refresh(); c.refresh(); c.refresh()
        XCTAssertEqual(store.name(for: "B"), "Keep")
        XCTAssertEqual(c.lastError, "Couldn't read Spaces")
        XCTAssertEqual(c.rows.count, 2, "keeps last good rows")
    }

    func testSwitchPostsPlannedKeys() {
        let keys = FakeKeys()
        let (c, _, _) = make([desktop(1, "", current: true), desktop(2, "B"), desktop(3, "C")], keys: keys)
        c.refresh()
        XCTAssertEqual(c.switchTo(key: "C"), .step(KeyChord(keyCode: 124, modifierFlags: 0x840000), count: 2))
        XCTAssertEqual(keys.posted.count, 1)
        XCTAssertEqual(keys.posted.first?.1, 2)
    }

    func testSwitchToCurrentPostsNothing() {
        let keys = FakeKeys()
        let (c, _, _) = make([desktop(1, "", current: true)], keys: keys)
        c.refresh()
        XCTAssertEqual(c.switchTo(key: "main:Main"), .alreadyThere)
        XCTAssertTrue(keys.posted.isEmpty)
    }

    func testMultipleDisplaysFlag() {
        let (c, _, _) = make([desktop(1, "", current: true), desktop(2, "Z", display: "Other")])
        c.refresh()
        XCTAssertTrue(c.hasMultipleDisplaysWithSpaces)
        XCTAssertEqual(c.primaryDisplaySpaces.count, 1)
    }
}
