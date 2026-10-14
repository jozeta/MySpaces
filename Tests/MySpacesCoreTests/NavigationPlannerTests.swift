import XCTest
@testable import MySpacesCore

final class NavigationPlannerTests: XCTestCase {
    let left = KeyChord(keyCode: 123, modifierFlags: 0x840000)
    let right = KeyChord(keyCode: 124, modifierFlags: 0x840000)
    var stepOnly: SpaceHotkeys { SpaceHotkeys(moveLeft: left, moveRight: right, desktops: [:]) }
    // Order: Desktop 1 (current), Desktop 2, Safari (full screen), Desktop 3
    let spaces = [desktop(1, "", current: true), desktop(2, "B"), fullscreen(3, "F", app: "Safari"), desktop(4, "D")]

    func testAlreadyThere() {
        XCTAssertEqual(NavigationPlanner.plan(to: spaces[0], in: spaces, hotkeys: stepOnly), .alreadyThere)
    }

    func testStepsRightAcrossFullscreen() {
        XCTAssertEqual(NavigationPlanner.plan(to: spaces[3], in: spaces, hotkeys: stepOnly), .step(right, count: 3))
    }

    func testStepsLeft() {
        let fromEnd = [desktop(1, ""), desktop(2, "B"), desktop(4, "D", current: true)]
        XCTAssertEqual(NavigationPlanner.plan(to: fromEnd[0], in: fromEnd, hotkeys: stepOnly), .step(left, count: 2))
    }

    func testDirectWhenDesktopShortcutEnabled() {
        let ctrl3 = KeyChord(keyCode: 20, modifierFlags: 262144)
        var hk = stepOnly
        hk.desktops = [3: ctrl3]
        // spaces[3] is "Desktop 3" because the full-screen Space is not numbered.
        XCTAssertEqual(NavigationPlanner.plan(to: spaces[3], in: spaces, hotkeys: hk), .direct(ctrl3))
    }

    func testFullscreenTargetAlwaysSteps() {
        var hk = stepOnly
        hk.desktops = [1: KeyChord(keyCode: 18, modifierFlags: 262144)]
        XCTAssertEqual(NavigationPlanner.plan(to: spaces[2], in: spaces, hotkeys: hk), .step(right, count: 2))
    }

    func testUnavailableWhenNeededDirectionDisabled() {
        let hk = SpaceHotkeys(moveLeft: left, moveRight: nil, desktops: [:])
        XCTAssertEqual(NavigationPlanner.plan(to: spaces[1], in: spaces, hotkeys: hk), .unavailable)
    }

    func testUnavailableWhenNoCurrentSpace() {
        let noCurrent = [desktop(1, ""), desktop(2, "B")]
        XCTAssertEqual(NavigationPlanner.plan(to: noCurrent[1], in: noCurrent, hotkeys: stepOnly), .unavailable)
    }

    func testVerificationDelayGrowsWithSteps() {
        XCTAssertEqual(NavigationPlan.direct(right).verificationDelay, 1.0, accuracy: 0.001)
        XCTAssertEqual(NavigationPlan.step(right, count: 1).verificationDelay, 1.4, accuracy: 0.001)
        XCTAssertEqual(NavigationPlan.step(right, count: 5).verificationDelay, 3.0, accuracy: 0.001)
        XCTAssertEqual(NavigationPlan.alreadyThere.verificationDelay, 0)
        XCTAssertEqual(NavigationPlan.unavailable.verificationDelay, 0)
    }
}
