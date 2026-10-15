import XCTest
@testable import MySpacesCore

final class OverlayScanGateTests: XCTestCase {
    let p = [LabelPlacement(rect: CGRect(x: 0, y: 0, width: 60, height: 16), name: "Dev", spaceKey: "A", maxWidth: 80)]

    func testShowsConsistentScan() throws {
        let gate = OverlayScanGate()
        gate.open()
        let t = try XCTUnwrap(gate.issueScan())
        XCTAssertEqual(gate.decide(t, placements: p), .show(p))
    }

    func testMismatchHidesAndDisablesRestOfSession() throws {
        let gate = OverlayScanGate()
        gate.open()
        let t1 = try XCTUnwrap(gate.issueScan())
        XCTAssertEqual(gate.decide(t1, placements: p), .show(p))
        let t2 = try XCTUnwrap(gate.issueScan())
        XCTAssertEqual(gate.decide(t2, placements: nil), .hide)
        XCTAssertNil(gate.issueScan(), "no more scans this session")
        gate.close()
        gate.open()
        XCTAssertNotNil(gate.issueScan(), "next Mission Control session starts fresh")
    }

    func testOlderScanFinishingLastIsIgnored() throws {
        let gate = OverlayScanGate()
        gate.open()
        let older = try XCTUnwrap(gate.issueScan())
        let newer = try XCTUnwrap(gate.issueScan())
        XCTAssertEqual(gate.decide(newer, placements: p), .show(p))
        XCTAssertEqual(gate.decide(older, placements: []), .ignore)
    }

    func testResultAfterCloseIsIgnored() throws {
        let gate = OverlayScanGate()
        gate.open()
        let t = try XCTUnwrap(gate.issueScan())
        gate.close()
        XCTAssertEqual(gate.decide(t, placements: p), .ignore)
        gate.open()
        XCTAssertEqual(gate.decide(t, placements: p), .ignore, "ticket from a previous session")
    }

    func testNoScansWhileClosed() {
        XCTAssertNil(OverlayScanGate().issueScan())
    }

    func testMismatchWhileSettlingRetriesWithoutDisabling() throws {
        let gate = OverlayScanGate()
        gate.open()
        let t1 = try XCTUnwrap(gate.issueScan())
        XCTAssertEqual(gate.decide(t1, placements: nil, settling: true), .retry)
        let t2 = try XCTUnwrap(gate.issueScan(), "captions not drawn yet must not disable the session")
        XCTAssertEqual(gate.decide(t2, placements: p, settling: true), .show(p))
    }

    func testChangedDesktopsReenableAfterMismatch() throws {
        // A desktop added or removed in Mission Control: captions read against the old list
        // mismatched, but the new list deserves a fresh start in the same session.
        let gate = OverlayScanGate()
        gate.open()
        let t1 = try XCTUnwrap(gate.issueScan())
        XCTAssertEqual(gate.decide(t1, placements: nil), .hide)
        XCTAssertNil(gate.issueScan())
        gate.desktopsChanged()
        let t2 = try XCTUnwrap(gate.issueScan())
        XCTAssertEqual(gate.decide(t2, placements: p), .show(p))
    }
}
