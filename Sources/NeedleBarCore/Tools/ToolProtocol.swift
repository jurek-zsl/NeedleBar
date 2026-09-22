import Foundation

public protocol ToolProtocol: Sendable {
    var definition: ToolDefinition { get }
    var riskLevel: RiskLevel { get }
    var requiredPermission: PermissionType? { get }
    func execute(arguments: [String: AnyCodable]) async throws -> ToolResult
}

extension ToolProtocol {
    public var name: String { definition.name }
    public var description: String { definition.description }
    public var requiredPermission: PermissionType? { nil }
}
