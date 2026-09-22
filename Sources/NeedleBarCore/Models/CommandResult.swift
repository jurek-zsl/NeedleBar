import Foundation

public struct ToolResult: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let toolName: String
    public let success: Bool
    public let message: String
    public let data: [String: AnyCodable]?
    public let error: String?

    public init(
        id: UUID = UUID(),
        toolName: String,
        success: Bool,
        message: String,
        data: [String: AnyCodable]? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.success = success
        self.message = message
        self.data = data
        self.error = error
    }

    public static func success(tool: String, message: String, data: [String: AnyCodable]? = nil) -> ToolResult {
        ToolResult(toolName: tool, success: true, message: message, data: data)
    }

    public static func failure(tool: String, error: String) -> ToolResult {
        ToolResult(toolName: tool, success: false, message: error, error: error)
    }
}

public struct ExecutionResult: Codable, Equatable, Sendable {
    public let query: String
    public let success: Bool
    public let results: [ToolResult]
    public let summary: String
    public let duration: TimeInterval

    public init(
        query: String,
        success: Bool,
        results: [ToolResult],
        summary: String,
        duration: TimeInterval
    ) {
        self.query = query
        self.success = success
        self.results = results
        self.summary = summary
        self.duration = duration
    }
}
