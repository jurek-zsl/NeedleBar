import Foundation

public struct ToolCall: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let arguments: [String: AnyCodable]

    public init(id: UUID = UUID(), name: String, arguments: [String: AnyCodable]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    enum CodingKeys: String, CodingKey {
        case name
        case arguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.arguments = (try? container.decode([String: AnyCodable].self, forKey: .arguments)) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(arguments, forKey: .arguments)
    }

    public func string(for key: String) -> String? {
        arguments[key]?.stringValue
    }

    public func int(for key: String) -> Int? {
        arguments[key]?.intValue
    }

    public func bool(for key: String) -> Bool? {
        arguments[key]?.boolValue
    }

    public func double(for key: String) -> Double? {
        arguments[key]?.doubleValue
    }
}
