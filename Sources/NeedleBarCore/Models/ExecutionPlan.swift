import Foundation

public enum ExecutionStepStatus: String, Codable, Equatable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case skipped
}

public enum PlanStatus: String, Codable, Equatable, Sendable {
    case pending
    case awaitingConfirmation
    case executing
    case completed
    case failed
    case cancelled
}

public struct ExecutionStep: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let index: Int
    public let toolCall: ToolCall
    public let riskLevel: RiskLevel
    public let requiresConfirmation: Bool
    public let description: String
    public let affectedItems: [String]
    public var status: ExecutionStepStatus
    public var result: ToolResult?

    public init(
        id: UUID = UUID(),
        index: Int,
        toolCall: ToolCall,
        riskLevel: RiskLevel,
        requiresConfirmation: Bool,
        description: String,
        affectedItems: [String] = [],
        status: ExecutionStepStatus = .pending,
        result: ToolResult? = nil
    ) {
        self.id = id
        self.index = index
        self.toolCall = toolCall
        self.riskLevel = riskLevel
        self.requiresConfirmation = requiresConfirmation
        self.description = description
        self.affectedItems = affectedItems
        self.status = status
        self.result = result
    }
}

public struct ExecutionPlan: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let query: String
    public let confidence: Double?
    public let reasoning: String?
    public var steps: [ExecutionStep]
    public let requiresConfirmation: Bool
    public let overallRisk: RiskLevel
    public var status: PlanStatus

    public init(
        id: UUID = UUID(),
        query: String,
        confidence: Double?,
        reasoning: String?,
        steps: [ExecutionStep],
        requiresConfirmation: Bool,
        overallRisk: RiskLevel,
        status: PlanStatus = .pending
    ) {
        self.id = id
        self.query = query
        self.confidence = confidence
        self.reasoning = reasoning
        self.steps = steps
        self.requiresConfirmation = requiresConfirmation
        self.overallRisk = overallRisk
        self.status = status
    }
}
