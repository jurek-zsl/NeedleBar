import Foundation

public struct PropertyDefinition: Codable, Equatable, Sendable {
    public let type: String
    public let description: String
    public let `enum`: [String]?

    public init(type: String, description: String, enum: [String]? = nil) {
        self.type = type
        self.description = description
        self.`enum` = `enum`
    }
}

public struct ParametersSchema: Codable, Equatable, Sendable {
    public let type: String
    public let properties: [String: PropertyDefinition]
    public let required: [String]?

    public init(properties: [String: PropertyDefinition] = [:], required: [String]? = nil) {
        self.type = "object"
        self.properties = properties
        self.required = required
    }
}

public struct ToolDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let parameters: ParametersSchema

    public init(name: String, description: String, parameters: ParametersSchema) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}
