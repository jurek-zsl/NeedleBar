import Foundation

public struct AnyCodable: Codable, Equatable, Hashable, Sendable {
    public let value: AnySendable

    public init(_ value: (any Sendable)?) {
        if let val = value {
            self.value = AnySendable(val)
        } else {
            self.value = AnySendable(NSNull())
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = AnySendable(NSNull())
        } else if let bool = try? container.decode(Bool.self) {
            self.value = AnySendable(bool)
        } else if let int = try? container.decode(Int.self) {
            self.value = AnySendable(int)
        } else if let double = try? container.decode(Double.self) {
            self.value = AnySendable(double)
        } else if let string = try? container.decode(String.self) {
            self.value = AnySendable(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = AnySendable(array.map { $0.value.base })
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = AnySendable(dict.mapValues { $0.value.base })
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported AnyCodable value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value.base {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [any Sendable]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: any Sendable]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encode(String(describing: value.base))
        }
    }

    public var stringValue: String? {
        if let s = value.base as? String { return s }
        if let i = value.base as? Int { return String(i) }
        if let d = value.base as? Double { return String(d) }
        return nil
    }

    public var intValue: Int? {
        if let i = value.base as? Int { return i }
        if let d = value.base as? Double { return Int(d) }
        if let s = value.base as? String { return Int(s) }
        return nil
    }

    public var doubleValue: Double? {
        if let d = value.base as? Double { return d }
        if let i = value.base as? Int { return Double(i) }
        if let s = value.base as? String { return Double(s) }
        return nil
    }

    public var boolValue: Bool? {
        if let b = value.base as? Bool { return b }
        if let s = value.base as? String {
            if s.lowercased() == "true" { return true }
            if s.lowercased() == "false" { return false }
        }
        return nil
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value.base) == String(describing: rhs.value.base)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value.base))
    }
}

public struct AnySendable: @unchecked Sendable {
    public let base: Any

    public init(_ base: Any) {
        self.base = base
    }
}
