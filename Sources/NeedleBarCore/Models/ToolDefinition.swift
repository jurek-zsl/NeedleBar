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

    private enum CodingKeys: String, CodingKey {
        case type, properties, required
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = (try? container.decode(String.self, forKey: .type)) ?? "object"
        self.properties = (try? container.decode([String: PropertyDefinition].self, forKey: .properties)) ?? [:]
        self.required = try? container.decodeIfPresent([String].self, forKey: .required)
    }
}

public struct ToolDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let parameters: ParametersSchema
    public let triggers: [String]?

    public init(
        name: String,
        description: String,
        parameters: ParametersSchema,
        triggers: [String]? = nil
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.triggers = triggers
    }
}
