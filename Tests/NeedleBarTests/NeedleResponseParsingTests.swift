import XCTest
@testable import NeedleBarCore

final class NeedleResponseParsingTests: XCTestCase {

    func testParseValidSingleCall() throws {
        let json = """
        {
          "type": "call",
          "success": true,
          "error": null,
          "error_code": null,
          "reason": null,
          "function_calls": [{"name": "open_application", "arguments": {"name": "Safari"}}],
          "suppressed_calls": [],
          "reasoning": "'Safari' -> name 'Safari'",
          "confidence": 1.0,
          "prefill_tps": 2678.9,
          "decode_tps": 698.9,
          "peak_ram_mb": 90.6,
          "validation": {"ungrounded": [], "negation": false}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(NeedleResponse.self, from: json)
        XCTAssertEqual(response.type, "call")
        XCTAssertEqual(response.success, true)
        XCTAssertEqual(response.confidence, 1.0)
        XCTAssertEqual(response.prefillTps, 2678.9)
        XCTAssertEqual(response.decodeTps, 698.9)
        XCTAssertEqual(response.peakRamMb, 90.6)

        XCTAssertEqual(response.functionCalls?.count, 1)
        XCTAssertEqual(response.functionCalls?.first?.name, "open_application")
        XCTAssertEqual(response.functionCalls?.first?.string(for: "name"), "Safari")
        XCTAssertFalse(response.hasSuppressedCalls)
    }

    func testParseMultipleCalls() throws {
        let json = """
        {
          "type": "call",
          "success": true,
          "function_calls": [
            {"name": "open_application", "arguments": {"name": "Xcode"}},
            {"name": "open_application", "arguments": {"name": "Terminal"}}
          ],
          "suppressed_calls": [],
          "confidence": 0.95
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(NeedleResponse.self, from: json)
        XCTAssertEqual(response.functionCalls?.count, 2)
        XCTAssertEqual(response.functionCalls?[0].string(for: "name"), "Xcode")
        XCTAssertEqual(response.functionCalls?[1].string(for: "name"), "Terminal")
    }

    func testParseSuppressedCalls() throws {
        let json = """
        {
          "type": "call",
          "success": true,
          "function_calls": [],
          "suppressed_calls": [
            {"name": "move_file", "arguments": {"source": "a.txt", "destination": "b.txt"}}
          ],
          "confidence": 0.85
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(NeedleResponse.self, from: json)
        XCTAssertTrue(response.hasSuppressedCalls)
        XCTAssertEqual(response.suppressedCalls?.count, 1)
        XCTAssertEqual(response.suppressedCalls?.first?.name, "move_file")
    }

    func testParseEmptyRefusal() throws {
        let json = """
        {
          "type": "call",
          "success": true,
          "function_calls": [],
          "suppressed_calls": [],
          "reasoning": "No tool available for geography."
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(NeedleResponse.self, from: json)
        XCTAssertTrue(response.effectiveCalls.isEmpty)
        XCTAssertFalse(response.hasSuppressedCalls)
        XCTAssertEqual(response.reasoning, "No tool available for geography.")
    }

    func testRejectMalformedJSON() {
        let invalidJson = "{ invalid json content }".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(NeedleResponse.self, from: invalidJson))
    }
}
