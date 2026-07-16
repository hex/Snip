// ABOUTME: Tests for TriggerRouting, the per-app resolution of which trigger opens the ring.
// ABOUTME: Covers global fallback, suppression, per-app overrides, and AppRule's stored-list decoding.
import XCTest
@testable import SnipKit

final class TriggerRoutingTests: XCTestCase {

    private let global = TriggerConfig(binding: .holdKey(code: 49, modifierRawValue: 0), label: "Space")

    // MARK: config(for:) — which trigger is armed in front of a given app

    func testAppWithoutRuleGetsGlobalConfig() {
        let routing = TriggerRouting(global: global, rules: [:])
        XCTAssertEqual(routing.config(for: "com.apple.finder"), global)
    }

    func testSuppressedAppGetsNoConfig() {
        let routing = TriggerRouting(global: global, rules: ["org.blenderfoundation.blender": .suppress])
        XCTAssertNil(routing.config(for: "org.blenderfoundation.blender"))
    }

    func testCustomTriggerReplacesGlobalInThatApp() {
        let middle = TriggerConfig(binding: .holdMouseButton(2), label: "Middle Button")
        let routing = TriggerRouting(global: global, rules: ["com.googlecode.iterm2": .trigger(middle)])
        XCTAssertEqual(routing.config(for: "com.googlecode.iterm2"), middle)
    }

    func testRuleForOneAppLeavesOthersOnGlobal() {
        let middle = TriggerConfig(binding: .holdMouseButton(2), label: "Middle Button")
        let routing = TriggerRouting(global: global,
                                     rules: ["com.googlecode.iterm2": .trigger(middle),
                                             "org.blenderfoundation.blender": .suppress])
        XCTAssertEqual(routing.config(for: "com.apple.finder"), global)
    }

    func testUnknownFrontmostGetsGlobalConfig() {   // no bundle id (e.g. no frontmost app yet)
        let routing = TriggerRouting(global: global, rules: ["com.googlecode.iterm2": .suppress])
        XCTAssertEqual(routing.config(for: nil), global)
    }

    // MARK: AppRule decoding — a stored list from before behaviors existed must load as suppress rules

    func testRuleWithoutBehaviorDecodesAsSuppress() throws {
        let stored = Data(#"[{"bundleID":"org.blenderfoundation.blender","name":"Blender"}]"#.utf8)
        let rules = try JSONDecoder().decode([AppRule].self, from: stored)
        XCTAssertEqual(rules, [AppRule(bundleID: "org.blenderfoundation.blender",
                                       name: "Blender",
                                       behavior: .suppress)])
    }

    func testCustomTriggerRuleSurvivesCodableRoundTrip() throws {
        let rule = AppRule(bundleID: "com.googlecode.iterm2",
                           name: "iTerm2",
                           behavior: .trigger(TriggerConfig(binding: .holdMouseButton(2), label: "Middle Button")))
        let decoded = try JSONDecoder().decode(AppRule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(decoded, rule)
    }
}
