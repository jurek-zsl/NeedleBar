import Foundation

public enum ConfirmationDecision: Equatable, Sendable {
    case executeAutomatically
    case requiresConfirmation(reason: String)
    case needsClarification(question: String)
    case unsupported(reason: String)
}

public struct ConfirmationPolicy: Sendable {
    public let highConfidenceThreshold: Double
    public let mediumConfidenceThreshold: Double

    public init(highConfidenceThreshold: Double = 0.85, mediumConfidenceThreshold: Double = 0.50) {
        self.highConfidenceThreshold = highConfidenceThreshold
        self.mediumConfidenceThreshold = mediumConfidenceThreshold
    }

    public func evaluate(
        toolName: String,
        riskLevel: RiskLevel,
        confidence: Double?,
        reasoning: String?,
        hasSuppressedCalls: Bool
    ) -> ConfirmationDecision {
        if hasSuppressedCalls {
            return .requiresConfirmation(
                reason: "Needle 3 flagged this action as potentially ambiguous. Please review the details before running."
            )
        }

        guard let conf = confidence else {
            // Uncalibrated weights or missing confidence score: default to requiring confirmation for non-safe actions
            if riskLevel == .safe {
                return .executeAutomatically
            } else {
                return .requiresConfirmation(reason: "Action modifies system or user state.")
            }
        }

        if conf < mediumConfidenceThreshold {
            return .needsClarification(
                question: reasoning ?? "I'm not sure how to perform this request safely. Could you clarify what you'd like to do?"
            )
        }

        if conf < highConfidenceThreshold {
            return .requiresConfirmation(
                reason: "Moderate confidence (\(Int(conf * 100))%). Please verify the action before proceeding."
            )
        }

        // High confidence (>= highConfidenceThreshold)
        switch riskLevel {
        case .safe:
            return .executeAutomatically
        case .requiresConfirmation:
            return .requiresConfirmation(reason: "This action will modify files, reminders, or application state.")
        case .destructive:
            return .requiresConfirmation(reason: "Destructive or high-impact action. Explicit confirmation is required.")
        }
    }
}
