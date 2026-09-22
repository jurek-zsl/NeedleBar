import Foundation

public struct HistoryRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let query: String
    public let toolNames: [String]
    public let success: Bool
    public let summary: String
    public let confidence: Double?
    public let riskLevel: RiskLevel

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        query: String,
        toolNames: [String],
        success: Bool,
        summary: String,
        confidence: Double?,
        riskLevel: RiskLevel
    ) {
        self.id = id
        self.timestamp = timestamp
        self.query = query
        self.toolNames = toolNames
        self.success = success
        self.summary = summary
        self.confidence = confidence
        self.riskLevel = riskLevel
    }
}
