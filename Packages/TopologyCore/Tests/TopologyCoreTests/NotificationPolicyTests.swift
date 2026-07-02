import XCTest
import DisplayDomain
@testable import TopologyCore

final class NotificationPolicyTests: XCTestCase {
    private func obs(_ id: String, builtIn: Bool = false) -> DisplayObservation {
        DisplayObservation(recordID: .init(rawValue: id), isActive: true, isMain: false,
                           displayClass: builtIn ? .builtIn : .external, generation: .initial)
    }
    private func names(_ pairs: [String: String]) -> [DisplayRecordID: String] {
        Dictionary(uniqueKeysWithValues: pairs.map { (DisplayRecordID(rawValue: $0.key), $0.value) })
    }

    func testDisabledProducesNothing() {
        let n = NotificationPolicy.notifications(
            prior: [obs("A", builtIn: true)], current: [obs("A", builtIn: true), obs("B")],
            names: names(["B": "Desk"]), enabled: false)
        XCTAssertTrue(n.isEmpty)
    }

    func testExternalConnected() {
        let n = NotificationPolicy.notifications(
            prior: [obs("A", builtIn: true)],
            current: [obs("A", builtIn: true), obs("B")],
            names: names(["B": "Desk"]), enabled: true)
        XCTAssertEqual(n, [.init(title: "Display connected", body: "Desk")])
    }

    func testExternalDisconnected() {
        let n = NotificationPolicy.notifications(
            prior: [obs("A", builtIn: true), obs("B")],
            current: [obs("A", builtIn: true)],
            names: names(["B": "Desk"]), enabled: true)
        XCTAssertEqual(n, [.init(title: "Display disconnected", body: "Desk")])
    }

    func testNoChangeProducesNothing() {
        let same = [obs("A", builtIn: true), obs("B")]
        XCTAssertTrue(NotificationPolicy.notifications(prior: same, current: same, names: [:], enabled: true).isEmpty)
    }

    func testBuiltInIsNotTreatedAsExternalTransition() {
        // The built-in dropping out (e.g. auto-disconnect) is NOT a "Display disconnected" external event.
        let n = NotificationPolicy.notifications(
            prior: [obs("A", builtIn: true), obs("B")],
            current: [obs("B")],
            names: names(["A": "Built-in", "B": "Desk"]), enabled: true)
        XCTAssertTrue(n.isEmpty)
    }

    func testBuiltInAutoDisconnectedAnnouncedDistinctly() {
        let n = NotificationPolicy.notifications(
            prior: [obs("A", builtIn: true), obs("B")],
            current: [obs("B")],
            names: names(["A": "Built-in", "B": "Desk"]),
            builtInAutoDisconnected: true, enabled: true)
        XCTAssertEqual(n, [.init(title: "Built-in display turned off",
                                 body: "Turned off automatically because an external display connected.")])
    }

    func testNameFallbackWhenUnknown() {
        let n = NotificationPolicy.notifications(
            prior: [], current: [obs("B")], names: [:], enabled: true)
        XCTAssertEqual(n, [.init(title: "Display connected", body: "A display")])
    }

    func testMultipleTransitionsOrderedDeterministically() {
        let n = NotificationPolicy.notifications(
            prior: [obs("B")],
            current: [obs("C"), obs("D")],
            names: names(["C": "Mon C", "D": "Mon D", "B": "Mon B"]), enabled: true)
        // Two connects (sorted), one disconnect.
        XCTAssertEqual(n, [
            .init(title: "Display connected", body: "Mon C"),
            .init(title: "Display connected", body: "Mon D"),
            .init(title: "Display disconnected", body: "Mon B"),
        ])
    }
}
