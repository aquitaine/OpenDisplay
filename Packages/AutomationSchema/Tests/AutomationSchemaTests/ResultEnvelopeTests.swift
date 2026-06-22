import XCTest
import DisplayDomain
@testable import AutomationSchema

final class ResultEnvelopeTests: XCTestCase {
    func testRoundTripPreservesAllFields() throws {
        let envelope = ResultEnvelope(
            transactionId: "txn_1",
            status: .committed,
            actor: .cli,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            topologyGeneration: 419,
            targets: [
                .init(displayId: "disp_1", alias: "DeskLeft", identityConfidence: 0.98, operations: [
                    .init(field: "lifecycle.connected",
                          requested: .bool(false),
                          observed: .bool(false),
                          verification: .verified,
                          provider: "experimentalLifecycle.v1")
                ])
            ],
            recovery: .init(checkpointId: "cp_1", available: true)
        )

        let data = try ResultEnvelope.makeEncoder().encode(envelope)
        let decoded = try ResultEnvelope.makeDecoder().decode(ResultEnvelope.self, from: data)
        XCTAssertEqual(decoded, envelope)
    }

    func testUnknownFieldsAreIgnored() throws {
        // Forward compatibility (AUT-012): a client on schema 1.0 must ignore unknown fields.
        let json = """
        {
          "schemaVersion": "1.1",
          "transactionId": "txn_9",
          "status": "noOp",
          "actor": "ui",
          "requestedAt": "2026-06-22T00:00:00Z",
          "topologyGeneration": 1,
          "targets": [],
          "errors": [],
          "futureOnlyField": { "nested": true }
        }
        """
        let data = Data(json.utf8)
        let decoded = try ResultEnvelope.makeDecoder().decode(ResultEnvelope.self, from: data)
        XCTAssertEqual(decoded.status, .noOp)
        XCTAssertEqual(decoded.transactionId, "txn_9")
    }

    func testAnyCodableValueVariants() throws {
        let values: [AnyCodableValue] = [.bool(true), .int(42), .double(3.5), .string("hi")]
        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
            XCTAssertEqual(decoded, value)
        }
    }

    func testCurrentSchemaVersionDefault() {
        let envelope = ResultEnvelope(transactionId: "t", status: .failed, actor: .ui,
                                      requestedAt: Date(), topologyGeneration: 0)
        XCTAssertEqual(envelope.schemaVersion, "1.0")
    }
}
