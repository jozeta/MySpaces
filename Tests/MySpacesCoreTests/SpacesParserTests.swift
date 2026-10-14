import XCTest
@testable import MySpacesCore

final class SpacesParserTests: XCTestCase {
    // Shape captured from CGSCopyManagedDisplaySpaces on macOS 27.0 (trimmed).
    let monitorsJSON = """
    [{
      "Display Identifier": "Main",
      "Current Space": {"ManagedSpaceID": 1387, "uuid": "8D3129CF", "type": 4},
      "Spaces": [
        {"ManagedSpaceID": 1, "uuid": "", "type": 0},
        {"ManagedSpaceID": 1312, "uuid": "69A75D05", "type": 0},
        {"ManagedSpaceID": 1387, "uuid": "8D3129CF", "type": 4,
         "TileLayoutManager": {"TileSpaces": [{"appName": "Safari", "type": 5}]}},
        {"ManagedSpaceID": 1063, "uuid": "72A63542", "type": 0}
      ]
    }, {
      "Display Identifier": "BA77B0AB", "Spaces": []
    }]
    """

    func monitors() throws -> [[String: Any]] {
        try JSONSerialization.jsonObject(with: Data(monitorsJSON.utf8)) as! [[String: Any]]
    }

    func testParsesDesktopsAndFullscreenInOrder() throws {
        let spaces = SpacesParser.parse(monitors: try monitors())
        XCTAssertEqual(spaces.map(\.managedID), [1, 1312, 1387, 1063])
        XCTAssertEqual(spaces[2].kind, .fullscreen(appName: "Safari"))
        XCTAssertEqual(spaces[0].kind, .desktop)
        XCTAssertEqual(spaces.filter(\.isCurrent).map(\.managedID), [1387])
        XCTAssertEqual(Set(spaces.map(\.displayID)), ["Main"])
    }

    func testEmptyUUIDGetsMainKey() throws {
        let spaces = SpacesParser.parse(monitors: try monitors())
        XCTAssertEqual(spaces[0].key, "main:Main")
        XCTAssertEqual(spaces[1].key, "69A75D05")
    }

    func testDesktopNumberSkipsFullscreen() throws {
        let spaces = SpacesParser.parse(monitors: try monitors())
        XCTAssertEqual(spaces.desktopNumber(of: spaces[0]), 1)
        XCTAssertEqual(spaces.desktopNumber(of: spaces[1]), 2)
        XCTAssertNil(spaces.desktopNumber(of: spaces[2]))
        XCTAssertEqual(spaces.desktopNumber(of: spaces[3]), 3)
    }

    func testFullscreenWithoutTileInfoGetsGenericName() {
        let spaces = SpacesParser.parse(monitors: [[
            "Display Identifier": "Main",
            "Spaces": [["ManagedSpaceID": 9, "uuid": "X", "type": 4]],
        ]])
        XCTAssertEqual(spaces.first?.kind, .fullscreen(appName: "Full-screen app"))
    }

    func testUnknownSpaceTypesAreSkipped() {
        let spaces = SpacesParser.parse(monitors: [[
            "Display Identifier": "Main",
            "Spaces": [["ManagedSpaceID": 9, "uuid": "X", "type": 6]],
        ]])
        XCTAssertTrue(spaces.isEmpty)
    }

    func testParsesSpacesPreferencesDomain() throws {
        let prefs: [String: Any] = [
            "SpacesDisplayConfiguration": ["Management Data": ["Monitors": try monitors()]],
        ]
        XCTAssertEqual(SpacesParser.parse(spacesPreferences: prefs).count, 4)
        XCTAssertTrue(SpacesParser.parse(spacesPreferences: [:]).isEmpty)
    }

    func testPrimaryDisplayIsFirstWithSpaces() throws {
        let spaces = SpacesParser.parse(monitors: try monitors())
        XCTAssertEqual(spaces.primaryDisplayID, "Main")
        XCTAssertEqual(spaces.displayIDs, ["Main"])
        XCTAssertEqual(spaces.onDisplay("Main").count, 4)
    }
}
