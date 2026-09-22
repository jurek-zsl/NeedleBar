import XCTest
@testable import NeedleBarCore

final class ConfirmationPolicyTests: XCTestCase {
    let policy = ConfirmationPolicy(highConfidenceThreshold: 0.85, mediumConfidenceThreshold: 0.50)

    func testHighConfidenceSafeActionExecutesAutomatically() {
        let decision = policy.evaluate(
            toolName: "open_application",
            riskLevel: .safe,
            confidence: 0.95,
            reasoning: "Open app",
            hasSuppressedCalls: false
        )
        XCTAssertEqual(decision, .executeAutomatically)
    }

    func testHighConfidenceMutativeActionRequiresConfirmation() {
        let decision = policy.evaluate(
            toolName: "move_file",
            riskLevel: .requiresConfirmation,
            confidence: 0.95,
            reasoning: "Move file",
            hasSuppressedCalls: false
        )
        guard case .requiresConfirmation = decision else {
            return XCTFail("Expected requiresConfirmation, got \(decision)")
        }
    }

    func testHighConfidenceDestructiveActionRequiresConfirmation() {
        let decision = policy.evaluate(
            toolName: "delete_file",
            riskLevel: .destructive,
            confidence: 0.99,
            reasoning: "Delete",
            hasSuppressedCalls: false
        )
        guard case .requiresConfirmation = decision else {
            return XCTFail("Expected requiresConfirmation, got \(decision)")
        }
    }

    func testMediumConfidenceRequiresConfirmationEvenForSafeAction() {
        let decision = policy.evaluate(
            toolName: "open_application",
            riskLevel: .safe,
            confidence: 0.70, // between 0.50 and 0.85
            reasoning: "Maybe Safari?",
            hasSuppressedCalls: false
        )
        guard case .requiresConfirmation = decision else {
            return XCTFail("Expected requiresConfirmation due to medium confidence, got \(decision)")
        }
    }

    func testLowConfidenceNeedsClarification() {
        let decision = policy.evaluate(
            toolName: "open_application",
            riskLevel: .safe,
            confidence: 0.40, // below 0.50
            reasoning: "Could you clarify?",
            hasSuppressedCalls: false
        )
        guard case .needsClarification = decision else {
            return XCTFail("Expected needsClarification, got \(decision)")
        }
    }

    func testSuppressedCallsAlwaysRequireConfirmation() {
        let decision = policy.evaluate(
            toolName: "move_file",
            riskLevel: .safe,
            confidence: 0.99,
            reasoning: "Suppressed call",
            hasSuppressedCalls: true
        )
        guard case .requiresConfirmation = decision else {
            return XCTFail("Expected requiresConfirmation for suppressed calls, got \(decision)")
        }
    }

    func testUncalibratedWeightsBehavior() {
        let safeDecision = policy.evaluate(
            toolName: "open_application",
            riskLevel: .safe,
            confidence: nil,
            reasoning: nil,
            hasSuppressedCalls: false
        )
        XCTAssertEqual(safeDecision, .executeAutomatically)

        let mutativeDecision = policy.evaluate(
            toolName: "move_file",
            riskLevel: .requiresConfirmation,
            confidence: nil,
            reasoning: nil,
            hasSuppressedCalls: false
        )
        guard case .requiresConfirmation = mutativeDecision else {
            return XCTFail("Expected requiresConfirmation for uncalibrated non-safe tool")
        }
    }
}
