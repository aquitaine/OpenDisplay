import XCTest
@testable import TopologyCore

final class KeyboardShortcutRegistryTests: XCTestCase {
    private let r = KeyBinding(keyCode: 0x0F, modifiers: KeyBinding.controlOptionCommand)
    private let up = KeyBinding(keyCode: 0x7E, modifiers: KeyBinding.controlOptionCommand)   // arrow up

    func testDefaultsBindReconnectAllToCtrlOptCmdR() {
        let defaults = KeyboardShortcutRegistry.defaults
        XCTAssertEqual(defaults.binding(for: .reconnectAll), r)
        XCTAssertNil(defaults.binding(for: .brightnessUp))   // unbound by default
    }

    func testControlOptionCommandMaskMatchesCarbon() {
        // cmd 0x100 | option 0x800 | control 0x1000 = 0x1900
        XCTAssertEqual(KeyBinding.controlOptionCommand, 0x1900)
    }

    func testSetAndClearBinding() {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(up, for: .brightnessUp)
        XCTAssertEqual(reg.binding(for: .brightnessUp), up)
        reg.setBinding(nil, for: .brightnessUp)
        XCTAssertNil(reg.binding(for: .brightnessUp))
    }

    func testReverseLookupByCombo() {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(r, for: .reconnectAll)
        XCTAssertEqual(reg.action(for: r), .reconnectAll)
        XCTAssertNil(reg.action(for: up))
    }

    func testConflictDetection() {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(r, for: .reconnectAll)
        XCTAssertTrue(reg.conflicts(r, excluding: nil))                 // r is taken
        XCTAssertFalse(reg.conflicts(r, excluding: .reconnectAll))      // ...but by reconnectAll itself
        XCTAssertFalse(reg.conflicts(up))                              // up is free
        reg.setBinding(r, for: .brightnessUp)                          // same combo, two actions
        XCTAssertEqual(reg.conflictingBindings()[r]?.sorted { $0.rawValue < $1.rawValue },
                       [.brightnessUp, .reconnectAll])
    }

    func testMergeOverDefaultsKeepsOverridesAndFillsGaps() {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(up, for: .reconnectAll)    // override the default reconnect chord
        let merged = reg.mergedWithDefaults()
        XCTAssertEqual(merged.binding(for: .reconnectAll), up)        // override wins
        XCTAssertNil(merged.binding(for: .brightnessUp))             // still unbound (no default)
    }

    func testCodableRoundTripsIncludingUnknownKeyTolerance() throws {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(r, for: .reconnectAll)
        reg.setBinding(up, for: .brightnessUp)
        let data = try JSONEncoder().encode(reg)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcutRegistry.self, from: data), reg)
        // A future action key the current build doesn't know is ignored on decode (object form).
        let withUnknown = #"{"reconnectAll":{"keyCode":15,"modifiers":6400},"futureAction":{"keyCode":1,"modifiers":0}}"#
        let decoded = try JSONDecoder().decode(KeyboardShortcutRegistry.self, from: Data(withUnknown.utf8))
        XCTAssertEqual(decoded.binding(for: .reconnectAll), r)
        XCTAssertEqual(decoded.bindings.count, 1)  // futureAction dropped
    }
}
