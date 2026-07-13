// ABOUTME: Tests for TriggerBinding, the pure matching logic behind hold/double-click triggers.
// ABOUTME: Covers mouse-down open gating, key matching, accessors, and Codable round-trips.
import XCTest
import CoreGraphics
@testable import SnipKit

final class TriggerConfigTests: XCTestCase {

    // MARK: mouseDownOpens — the hold vs. double-click gate

    func testHoldMouseButtonOpensOnSinglePress() {
        let binding = TriggerBinding.holdMouseButton(2)
        XCTAssertTrue(binding.mouseDownOpens(button: 2, clickState: 1))
    }

    func testHoldMouseButtonIgnoresOtherButtons() {
        let binding = TriggerBinding.holdMouseButton(2)
        XCTAssertFalse(binding.mouseDownOpens(button: 3, clickState: 1))
    }

    func testDoubleClickMouseButtonDoesNotOpenOnSingleClick() {
        let binding = TriggerBinding.doubleClickMouseButton(2)
        XCTAssertFalse(binding.mouseDownOpens(button: 2, clickState: 1))
    }

    func testDoubleClickMouseButtonOpensOnSecondClick() {
        let binding = TriggerBinding.doubleClickMouseButton(2)
        XCTAssertTrue(binding.mouseDownOpens(button: 2, clickState: 2))
    }

    func testDoubleClickMouseButtonOpensOnTripleClick() {   // clickState climbs; >= 2 arms it
        let binding = TriggerBinding.doubleClickMouseButton(2)
        XCTAssertTrue(binding.mouseDownOpens(button: 2, clickState: 3))
    }

    func testDoubleClickMouseButtonRespectsButtonNumber() {
        let binding = TriggerBinding.doubleClickMouseButton(3)
        XCTAssertTrue(binding.mouseDownOpens(button: 3, clickState: 2))
        XCTAssertFalse(binding.mouseDownOpens(button: 2, clickState: 2))
    }

    func testKeyBindingNeverOpensOnMouseDown() {
        let binding = TriggerBinding.holdKey(code: 49, modifierRawValue: CGEventFlags.maskAlternate.rawValue)
        XCTAssertFalse(binding.mouseDownOpens(button: 2, clickState: 2))
    }

    // MARK: keyOpens — keycode plus exact watched-modifier match

    private func optionSpace() -> TriggerBinding {
        .holdKey(code: 49, modifierRawValue: CGEventFlags.maskAlternate.rawValue)
    }

    func testKeyOpensWhenKeycodeAndModifierMatch() {
        XCTAssertTrue(optionSpace().keyOpens(code: 49, flags: [.maskAlternate]))
    }

    func testKeyDoesNotOpenWithoutTheModifier() {
        XCTAssertFalse(optionSpace().keyOpens(code: 49, flags: []))
    }

    func testKeyDoesNotOpenWithAnExtraModifier() {   // ⌘⌥Space must not fire an ⌥Space binding
        XCTAssertFalse(optionSpace().keyOpens(code: 49, flags: [.maskAlternate, .maskCommand]))
    }

    func testKeyDoesNotOpenOnWrongKeycode() {
        XCTAssertFalse(optionSpace().keyOpens(code: 50, flags: [.maskAlternate]))
    }

    func testKeyOpensIgnoresUnwatchedFlags() {   // caps-lock / numeric-pad bits must not block a match
        XCTAssertTrue(optionSpace().keyOpens(code: 49, flags: [.maskAlternate, .maskAlphaShift]))
    }

    func testModifierlessKeyOpensOnlyWithNoModifiers() {
        let f13 = TriggerBinding.holdKey(code: 105, modifierRawValue: 0)
        XCTAssertTrue(f13.keyOpens(code: 105, flags: []))
        XCTAssertFalse(f13.keyOpens(code: 105, flags: [.maskShift]))
    }

    func testMouseBindingNeverOpensOnKey() {
        XCTAssertFalse(TriggerBinding.holdMouseButton(2).keyOpens(code: 49, flags: [.maskAlternate]))
    }

    func testIsKeyCodeMatchesKeycodeIgnoringModifiers() {   // keyUp/autorepeat arrive after the modifier is released
        XCTAssertTrue(optionSpace().isKeyCode(49))
        XCTAssertFalse(optionSpace().isKeyCode(50))
        XCTAssertFalse(TriggerBinding.holdMouseButton(2).isKeyCode(49))
    }

    // MARK: accessors used by the drag/up path and the watchdog

    func testIsMouseButtonMatchesForBothMouseGestures() {
        XCTAssertTrue(TriggerBinding.holdMouseButton(4).isMouseButton(4))
        XCTAssertFalse(TriggerBinding.holdMouseButton(4).isMouseButton(2))
        XCTAssertTrue(TriggerBinding.doubleClickMouseButton(2).isMouseButton(2))
        XCTAssertFalse(optionSpace().isMouseButton(2))
    }

    func testKeyCodeAccessor() {
        XCTAssertEqual(optionSpace().keyCode, 49)
        XCTAssertNil(TriggerBinding.holdMouseButton(2).keyCode)
        XCTAssertNil(TriggerBinding.doubleClickMouseButton(3).keyCode)
    }

    func testMouseButtonNumberAccessor() {
        XCTAssertEqual(TriggerBinding.holdMouseButton(2).mouseButtonNumber, 2)
        XCTAssertEqual(TriggerBinding.doubleClickMouseButton(3).mouseButtonNumber, 3)
        XCTAssertNil(optionSpace().mouseButtonNumber)
    }

    // MARK: Codable — a stale UserDefaults blob must survive a round-trip for every case

    private func roundTrip(_ binding: TriggerBinding) throws -> TriggerBinding {
        let data = try JSONEncoder().encode(binding)
        return try JSONDecoder().decode(TriggerBinding.self, from: data)
    }

    func testCodableRoundTripHoldKey() throws {
        let b = optionSpace()
        XCTAssertEqual(try roundTrip(b), b)
    }

    func testCodableRoundTripHoldMouseButton() throws {
        let b = TriggerBinding.holdMouseButton(4)
        XCTAssertEqual(try roundTrip(b), b)
    }

    func testCodableRoundTripDoubleClickMouseButton() throws {
        let b = TriggerBinding.doubleClickMouseButton(2)
        XCTAssertEqual(try roundTrip(b), b)
    }

    // MARK: TriggerConfig default — the out-of-box gesture is a middle-button hold

    func testDefaultConfigIsMiddleButtonHold() {
        let config = TriggerConfig()
        XCTAssertEqual(config.binding, .holdMouseButton(2))
        XCTAssertEqual(config.label, "Middle Button")
    }
}
