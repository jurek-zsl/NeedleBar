import XCTest
@testable import NeedleBarCore

final class ToolCallValidatorTests: XCTestCase {
    var registry: ToolRegistry!
    var validator: ToolCallValidator!

    override func setUp() {
        super.setUp()
        registry = ToolRegistry.createDefaultRegistry(
            workspaceService: MockWorkspaceService(),
            fileService: MockFileSystemService(),
            productivityService: MockProductivityService(),
            systemInfoService: MockSystemInfoService(),
            notesService: MockNotesService()
        )
        validator = ToolCallValidator(toolRegistry: registry)
    }

    func testValidToolCallBuildsPlan() throws {
        let response = NeedleResponse(
            type: "call",
            success: true,
            functionCalls: [
                ToolCall(name: "open_application", arguments: ["name": AnyCodable("Safari")])
            ],
            reasoning: "Open Safari",
            confidence: 0.95
        )

        let plan = try validator.validateAndBuildPlan(query: "Open Safari", response: response)
        XCTAssertEqual(plan.query, "Open Safari")
        XCTAssertEqual(plan.steps.count, 1)
        XCTAssertEqual(plan.steps[0].toolCall.name, "open_application")
        XCTAssertEqual(plan.steps[0].riskLevel, .safe)
        XCTAssertFalse(plan.requiresConfirmation)
        XCTAssertEqual(plan.status, .pending)
    }

    func testRejectUnknownTool() {
        let response = NeedleResponse(
            type: "call",
            success: true,
            functionCalls: [
                ToolCall(name: "arbitrary_shell_command", arguments: ["cmd": AnyCodable("rm -rf /")])
            ],
            confidence: 0.95
        )

        XCTAssertThrowsError(try validator.validateAndBuildPlan(query: "Bad command", response: response)) { error in
            guard case ValidationError.unknownTool(let name) = error else {
                return XCTFail("Expected unknownTool error, got \(error)")
            }
            XCTAssertEqual(name, "arbitrary_shell_command")
        }
    }

    func testRejectMissingRequiredArgument() {
        // open_application requires 'name'
        let response = NeedleResponse(
            type: "call",
            success: true,
            functionCalls: [
                ToolCall(name: "open_application", arguments: [:])
            ],
            confidence: 0.95
        )

        XCTAssertThrowsError(try validator.validateAndBuildPlan(query: "Open", response: response)) { error in
            guard case ValidationError.missingRequiredArgument(let tool, let arg) = error else {
                return XCTFail("Expected missingRequiredArgument, got \(error)")
            }
            XCTAssertEqual(tool, "open_application")
            XCTAssertEqual(arg, "name")
        }
    }

    func testHandleMultipleToolCalls() throws {
        let response = NeedleResponse(
            type: "call",
            success: true,
            functionCalls: [
                ToolCall(name: "open_application", arguments: ["name": AnyCodable("Xcode")]),
                ToolCall(name: "open_application", arguments: ["name": AnyCodable("Terminal")])
            ],
            confidence: 0.95
        )

        let plan = try validator.validateAndBuildPlan(query: "Open Xcode and Terminal", response: response)
        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertEqual(plan.steps[0].description, "Open application 'Xcode'")
        XCTAssertEqual(plan.steps[1].description, "Open application 'Terminal'")
    }

    func testRejectEmptyOrUnsupportedResponse() {
        let response = NeedleResponse(
            type: "call",
            success: true,
            functionCalls: [],
            suppressedCalls: [],
            reasoning: "Not supported"
        )

        XCTAssertThrowsError(try validator.validateAndBuildPlan(query: "Sing a song", response: response)) { error in
            guard case ValidationError.unsupportedRequest = error else {
                return XCTFail("Expected unsupportedRequest, got \(error)")
            }
        }
    }

    func testLowConfidenceTriggersClarificationError() {
        let response = NeedleResponse(
            type: "call",
            success: true,
            functionCalls: [
                ToolCall(name: "open_application", arguments: ["name": AnyCodable("Safari")])
            ],
            confidence: 0.35 // Below 0.50 threshold
        )

        XCTAssertThrowsError(try validator.validateAndBuildPlan(query: "Maybe open something?", response: response)) { error in
            guard case ValidationError.lowConfidence = error else {
                return XCTFail("Expected lowConfidence, got \(error)")
            }
        }
    }

    func testConfirmatoryToolRequiresConfirmation() throws {
        let response = NeedleResponse(
            type: "call",
            success: true,
            functionCalls: [
                ToolCall(name: "move_file", arguments: [
                    "source": AnyCodable("~/Downloads/report.pdf"),
                    "destination": AnyCodable("~/Documents")
                ])
            ],
            confidence: 0.95
        )

        let plan = try validator.validateAndBuildPlan(query: "Move report to Documents", response: response)
        XCTAssertTrue(plan.requiresConfirmation)
        XCTAssertEqual(plan.overallRisk, .requiresConfirmation)
        XCTAssertEqual(plan.status, .awaitingConfirmation)
        XCTAssertEqual(plan.steps[0].affectedItems.count, 2)
    }
}
